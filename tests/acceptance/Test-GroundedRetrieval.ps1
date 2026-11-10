#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 5: the agent answers the five scripted questions citing the expected sources.

.DESCRIPTION
    Sends each question in grounded-questions.json to the agent through the Foundry Responses API, as
    the signed-in Senior Technician, in a new conversation. It collects the answer's url_citation
    annotations, maps each cited URL to its record (the sourceId of the index document with that url)
    and passes a question when every expected source is cited. Any approval request is rejected, so
    the test never changes data.

    Preconditions: Exercise 1 Task 2 is done (the agent has the Azure AI Search tool on
    servicedesk-knowledge), and the Senior Technician has given OAuth consent to the Service Desk
    connections once in the playground. Also used for criterion 13 (concurrency): -Repeat and the
    per-question timings.

.EXAMPLE
    .\Test-GroundedRetrieval.ps1 -EvidencePath C:\Acceptance\evidence
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$QuestionsPath = (Join-Path $PSScriptRoot 'grounded-questions.json'),
    [ValidateRange(1, 10)][int]$Repeat = 1,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

$settings = Read-LabSettings $SettingsPath @('FoundryProjectEndpoint', 'AgentName', 'SearchEndpoint', 'SearchIndex', 'SeniorUser')
$report = New-AcceptanceReport 5 'Grounded retrieval: five scripted questions cite the expected sources' $settings
try {
    $questions = @((Get-Content -LiteralPath $QuestionsPath -Raw | ConvertFrom-Json).questions)
    if ($questions.Count -ne 5) { Add-Note $report "The questions file holds $($questions.Count) questions; the criterion names five." }
    Use-LabIdentity Senior $settings

    # The agent must carry the knowledge tool.
    $endpoint = ([string]$settings.FoundryProjectEndpoint).TrimEnd('/')
    $agent = Invoke-LabRest GET "$endpoint/agents/$($settings.AgentName)?api-version=v1" (Get-LabToken 'https://ai.azure.com')
    $searchTool = @($agent.Body.versions.latest.definition.tools) | Where-Object { $_ -and $_.type -eq 'azure_ai_search' } | Select-Object -First 1
    Add-Check $report 'The agent has the Azure AI Search tool' ([bool]$searchTool) $(if ($searchTool) { "version $($agent.Body.versions.latest.version), index $(@($searchTool.azure_ai_search.indexes)[0].index_name), $(@($searchTool.azure_ai_search.indexes)[0].query_type)" } else { 'Complete Exercise 1 Task 2 or run C:\LabFiles\tools\Update-AgentDefinition.ps1 -Instructions first.' })
    if (-not $searchTool) { exit (Complete-AcceptanceReport $report $EvidencePath) }

    # Map every index document's url and title to its sourceId.
    $search = ([string]$settings.SearchEndpoint).TrimEnd('/')
    $docs = Invoke-LabRest POST "$search/indexes/$($settings.SearchIndex)/docs/search?api-version=2024-07-01" (Get-LabToken 'https://search.azure.com') @{ search = '*'; select = 'sourceId,url,title'; top = 1000 }
    if ($docs.Status -ne 200) { throw "Reading the index failed (HTTP $($docs.Status)): $($docs.Error). The Senior Technician needs Search Index Data Reader." }
    $byUrl = @{}; $byTitle = @{}
    foreach ($d in @($docs.Body.value)) {
        if ($d.url) { $byUrl[([string]$d.url).TrimEnd('/').ToLowerInvariant()] = [string]$d.sourceId }
        if ($d.title) { $byTitle[([string]$d.title).ToLowerInvariant()] = [string]$d.sourceId }
    }
    Add-Note $report "Index lookup built from $(@($docs.Body.value).Count) documents."
    $idPattern = '\b(KB\d{4}|CDOC-\d{3}|RB-\d{3}|TCK-\d{5}|CUST-\d{3})\b'

    $results = [System.Collections.Generic.List[object]]::new()
    for ($round = 1; $round -le $Repeat; $round++) {
        foreach ($q in $questions) {
            Write-Host "Asking $($q.id)$(if ($Repeat -gt 1) { " (round $round)" }): $($q.question)" -ForegroundColor Cyan
            $turn = Invoke-AgentTurn $settings $q.question
            Assert-NoConsentNeeded $turn
            $cited = @(@(foreach ($c in $turn.Citations) {
                $id = $byUrl[$c.Url.TrimEnd('/').ToLowerInvariant()]
                if (-not $id) { $id = $byTitle[$c.Title.ToLowerInvariant()] }
                if (-not $id -and "$($c.Title) $($c.Url)" -match $idPattern) { $id = $Matches[1] }
                if ($id) { $id }
            }) | Select-Object -Unique)
            $mentioned = @([regex]::Matches($turn.Text, $idPattern) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            $missing = @($q.expected_sources | Where-Object { $_ -notin $cited })
            $unexpected = @($cited | Where-Object { $_ -notin @($q.expected_sources) -and $_ -notin @($q.acceptable_sources) })
            $results.Add([pscustomobject]@{
                Round = $round; Id = $q.id; Kind = $q.kind; Question = $q.question; Expected = @($q.expected_sources); Cited = @($cited); MentionedInText = $mentioned
                Missing = $missing; OtherCited = $unexpected; Seconds = $turn.Seconds; ConversationId = $turn.ConversationId; ResponseIds = $turn.ResponseIds
                ToolCalls = @($turn.McpCalls | ForEach-Object { "$($_.Server)/$($_.Tool) $($_.Status)" }); Approvals = $turn.Approvals
                Answer = (Protect-Text ($turn.Text.Substring(0, [Math]::Min(3000, $turn.Text.Length))) -FreeText)
            })
            $detail = "cited $(if ($cited.Count) { $cited -join ', ' } else { 'nothing' }); expected $($q.expected_sources -join ', '); $($turn.Seconds) s"
            if ($missing.Count -and @($missing | Where-Object { $_ -in $mentioned }).Count) { $detail += "; named in the text but not cited: $(@($missing | Where-Object { $_ -in $mentioned }) -join ', ')" }
            if ($unexpected.Count) { $detail += "; also cited: $($unexpected -join ', ')" }
            Add-Check $report "$($q.id)$(if ($Repeat -gt 1) { " round $round" }) cites $($q.expected_sources -join ' and ')" ($missing.Count -eq 0) $detail
        }
    }
    $report.Evidence['questions'] = @($results)
    $seconds = @($results | ForEach-Object { [double]$_.Seconds } | Sort-Object)
    if ($seconds.Count) {
        $median = $seconds[[int][Math]::Floor(($seconds.Count - 1) / 2)]
        $report.Evidence['timing'] = [pscustomobject]@{ Questions = $seconds.Count; MedianSeconds = $median; MaxSeconds = $seconds[-1] }
        Add-Note $report "Answer time: median $median s, longest $($seconds[-1]) s over $($seconds.Count) answers."
    }
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
