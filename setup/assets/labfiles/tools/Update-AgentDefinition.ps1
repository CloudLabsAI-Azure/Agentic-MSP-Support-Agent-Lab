#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a new version of your Foundry agent from the lab's known parts: instructions, the
    Service Desk MCP tool, and optionally the knowledge index.

.DESCRIPTION
    -Knowledge  Exercise 1 Task 2 fallback, if the portal doesn't offer the knowledge options in
                the guide: instructions from C:\LabFiles\agent\instructions-grounded.md, the
                Azure AI Search tool on index servicedesk-knowledge (query type
                vector_semantic_hybrid, 10 results) and the Service Desk MCP tool. Uses the Azure
                AI Search connection you created in the Foundry portal; creates
                'servicedesk-search' (Microsoft Entra ID, keyless) only if the project has none
                for your search service.
    -Reset      Back to the baseline the lab starts with: instructions-baseline.md and the
                Service Desk MCP tool, no knowledge source.

    The Service Desk MCP tool always uses the project connection 'servicedesk-mcp' (OAuth
    identity passthrough) and needs approval for every tool except the nine read tools. A new
    version replaces the tool list of the previous one; the agent's endpoint serves the latest.
    Uses your own Azure CLI sign-in: run 'az login' first.
#>
[CmdletBinding(DefaultParameterSetName = 'Knowledge')]
param(
    [Parameter(ParameterSetName = 'Knowledge', Mandatory)][switch]$Knowledge,
    [Parameter(ParameterSetName = 'Reset', Mandatory)][switch]$Reset,
    [string]$SettingsPath = 'C:\LabFiles\team-settings.json'
)

$ErrorActionPreference = 'Stop'
$s = Get-Content $SettingsPath -Raw | ConvertFrom-Json
$project = "/subscriptions/$($s.SubscriptionId)/resourceGroups/$($s.ResourceGroup)/providers/Microsoft.CognitiveServices/accounts/$($s.FoundryResource)/projects/$($s.FoundryProject)"

function Find-Connection([string]$category, [string]$target) {
    $list = az rest --method get --uri "https://management.azure.com$project/connections?api-version=2025-06-01" | ConvertFrom-Json
    if ($LASTEXITCODE) { throw "Could not list the project connections. Run 'az login' and try again." }
    return $list.value | Where-Object {
        $_.properties.category -eq $category -and "$($_.properties.target)".TrimEnd('/') -eq $target.TrimEnd('/')
    } | Select-Object -First 1
}

$toolDefs = @(@{
    type = 'mcp'; server_label = 'servicedesk'; server_url = $s.McpGatewayUrl; project_connection_id = $s.McpConnectionName
    require_approval = @{ never = @{ tool_names = @($s.McpReadTools) } }
})

if ($Knowledge) {
    $search = Find-Connection 'CognitiveSearch' $s.SearchEndpoint
    if ($search) {
        Write-Host "Using the Azure AI Search connection '$($search.name)'." -ForegroundColor DarkGray
        $searchId = $search.id
    }
    else {
        $file = New-TemporaryFile
        try {
            @{ properties = @{ category = 'CognitiveSearch'; target = $s.SearchEndpoint; authType = 'AAD' } } |
                ConvertTo-Json -Depth 5 | Set-Content $file -Encoding utf8
            az rest --method put --uri "https://management.azure.com$project/connections/servicedesk-search?api-version=2025-06-01" `
                --body "@$file" --output none
            if ($LASTEXITCODE) { throw 'Creating the servicedesk-search connection failed.' }
        }
        finally { Remove-Item $file -Force -ErrorAction SilentlyContinue }
        Write-Host "Created project connection 'servicedesk-search'." -ForegroundColor DarkGray
        $searchId = "$project/connections/servicedesk-search"
    }
    $toolDefs = @(@{ type = 'azure_ai_search'; azure_ai_search = @{ indexes = @(@{
        project_connection_id = $searchId; index_name = $s.SearchIndex; query_type = 'vector_semantic_hybrid'; top_k = 10 }) } }) + $toolDefs
}

$instructionsFile = if ($Knowledge) { 'C:\LabFiles\agent\instructions-grounded.md' } else { 'C:\LabFiles\agent\instructions-baseline.md' }
$body = @{ definition = @{ kind = 'prompt'; model = $s.ChatDeployment; instructions = (Get-Content $instructionsFile -Raw); tools = $toolDefs } } |
    ConvertTo-Json -Depth 12
$token = az account get-access-token --resource 'https://ai.azure.com' --query accessToken --output tsv
if (-not $token) { throw "Run 'az login' first." }
$version = Invoke-RestMethod -Method Post -Uri "$($s.FoundryProjectEndpoint)/agents/$($s.AgentName)/versions?api-version=v1" `
    -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' -Body $body
Write-Host ("Created version {0} of {1} with tools: {2}." -f $version.version, $s.AgentName, (($toolDefs | ForEach-Object type) -join ', ')) -ForegroundColor Green
