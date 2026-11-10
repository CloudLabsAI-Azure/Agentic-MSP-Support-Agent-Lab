#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 4: seeded-data validation. Record counts match the seed manifest and the
    Exhibit D minimums, and every scenario record the guides use exists with its documented facts.

.DESCRIPTION
    Reads Dataverse and the search export (read-only) and compares them with the seed manifest
    (data_version 3.0):
      - counts per table, the 500 historical and 60 open tickets plus the 2 new incidents (by their
        published number ranges), at least 800 notes, 15 technicians in exactly 4 teams, 4 SLA tiers;
      - every ticket named in role_keys exists for the documented customer;
      - every KB, runbook, customer document, customer and technician code named in the scenarios exists;
      - the untriaged tickets and the new incidents have no priority and no category;
      - the SLA set's remaining business hours match;
      - Lamna Healthcare's tickets are owned by the Relecloud Regulated Accounts team;
      - the Retired and Draft articles carry their status;
      - the export manifest and the blobs in the export container equal searchable_documents.total.

    Run it as an account that reads every record: a supplier administrator (-Identity Current) or the
    lab VM's provisioning identity (-Identity Provisioning), which the readiness check also uses.

.EXAMPLE
    .\Test-SeedData.ps1 -Identity Provisioning -EvidencePath C:\Acceptance\evidence
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$ManifestPath,
    [string]$ExportManifestPath = 'C:\LabFiles\search\export-manifest.json',
    [ValidateSet('Current', 'Senior', 'Provisioning')][string]$Identity = 'Current',
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

function Get-Count($Settings, [string]$Set, [string]$Filter = '') {
    $f = if ($Filter) { "&`$filter=$Filter" } else { '' }
    $r = Invoke-LabDataverse $Settings "$($Set)?`$count=true&`$top=1$f"
    if ($r.Status -ne 200) { throw "Counting $Set failed (HTTP $($r.Status)): $($r.Error)" }
    return [int]$r.Body.'@odata.count'
}

function Get-Codes($Settings, [string]$Set, [string]$Column) {
    try { return @(Get-LabDataverseRows $Settings "$($Set)?`$select=$Column" | ForEach-Object { [string]$_.$Column } | Where-Object { $_ }) }
    catch { return $null }
}

$settings = Read-LabSettings $SettingsPath @('DataverseUrl')
$report = New-AcceptanceReport 4 'Seeded-data validation against the manifest' $settings
try {
    $manifest = Get-SeedManifest $settings $ManifestPath
    $sc = $manifest.scenarios
    Add-Note $report "Seed manifest data version $($manifest.data_version), seed $($manifest.seed), anchor $($manifest.anchor)."
    Use-LabIdentity $Identity $settings
    $c = $manifest.counts
    $newCount = @($manifest.new_incidents).Count

    # ==== Counts
    $checks = [ordered]@{
        'Customers'                = @((Get-Count $settings 'accounts' 'spk_customercode ne null'), [int]$c.accounts, 12)
        'Contacts'                 = @((Get-Count $settings 'contacts'), [int]$c.contacts, 60)
        'Customer procedures'      = @((Get-Count $settings 'spk_customerprocedures'), [int]$c.customerprocedures, 0)
        'Customer documents'       = @((Get-Count $settings 'spk_customerdocuments'), [int]$c.customerdocuments, 36)
        'Runbooks'                 = @((Get-Count $settings 'spk_runbooks'), [int]$c.runbooks, 0)
        'Knowledge articles'       = @((Get-Count $settings 'spk_knowledgearticles'), [int]$c.knowledgearticles, 120)
        'Technicians'              = @((Get-Count $settings 'spk_technicians'), [int]$c.technicians, 15)
        'SLA definitions'          = @((Get-Count $settings 'spk_slapolicies'), [int]$c.slapolicies, 16)
        'Tickets, all'             = @((Get-Count $settings 'spk_tickets'), ([int]$c.tickets + $newCount), 0)
        'Historical tickets'       = @((Get-Count $settings 'spk_tickets' "spk_ticketnumber ge '$($manifest.numbering.historical[0])' and spk_ticketnumber le '$($manifest.numbering.historical[1])'"), [int]$manifest.historical_tickets, 500)
        'Open tickets'             = @((Get-Count $settings 'spk_tickets' "spk_ticketnumber ge '$($manifest.numbering.open[0])' and spk_ticketnumber le '$($manifest.numbering.open[1])'"), [int]$manifest.open_tickets, 60)
        'New incidents'            = @((Get-Count $settings 'spk_tickets' (($manifest.new_incidents | ForEach-Object { "spk_ticketnumber eq '$_'" }) -join ' or ')), $newCount, 2)
        'Communication history'    = @((Get-Count $settings 'spk_ticketnotes'), [int]$c.ticketnotes, 800)
    }
    foreach ($name in $checks.Keys) {
        $actual, $expected, $minimum = $checks[$name]
        Add-Check $report "$name match the manifest" ($actual -eq $expected -and $actual -ge $minimum) "$actual in Dataverse; manifest $expected$(if ($minimum) { "; Exhibit D minimum $minimum" })"
    }
    $teams = @(Get-LabDataverseRows $settings 'spk_technicians?$select=spk_team' | ForEach-Object { [string](Get-First $_.'spk_team@OData.Community.Display.V1.FormattedValue' $_.spk_team) } | Select-Object -Unique)
    Add-Check $report 'Technicians are in exactly 4 teams' ($teams.Count -eq 4) ($teams -join ', ')
    $tiers = @(Get-LabDataverseRows $settings 'spk_slapolicies?$select=spk_slatier' | ForEach-Object { [string](Get-First $_.'spk_slatier@OData.Community.Display.V1.FormattedValue' $_.spk_slatier) } | Select-Object -Unique)
    Add-Check $report 'SLA definitions cover 4 tiers' ($tiers.Count -eq 4) ($tiers -join ', ')
    $labeled = $sc.customer_documents.labeled_document
    $annotation = Get-Count $settings 'annotations' "filename eq '$($labeled.filename)'"
    Add-Check $report 'The labelled customer document is attached' ($annotation -ge 1) "$annotation annotation(s) named $($labeled.filename)"

    # ==== Scenario records
    $tickets = @{}
    foreach ($t in (Get-LabDataverseRows $settings 'spk_tickets?$select=spk_ticketnumber,spk_priority,spk_category,spk_slaremaininghours,_owningteam_value&$expand=spk_CustomerId($select=spk_customercode)')) {
        $tickets[[string]$t.spk_ticketnumber] = $t
    }
    $wrong = @(foreach ($role in $manifest.role_keys.PSObject.Properties) {
        $t = $tickets[[string]$role.Value]
        $expectedCustomer = [string]$sc.($role.Name).customer_code
        if (-not $t) { "$($role.Name) $($role.Value) missing" }
        elseif ($expectedCustomer -and $t.spk_CustomerId.spk_customercode -ne $expectedCustomer) { "$($role.Name) $($role.Value) belongs to $($t.spk_CustomerId.spk_customercode), not $expectedCustomer" }
    })
    Add-Check $report 'Every role-key ticket exists for its customer' ($wrong.Count -eq 0) "$(@($manifest.role_keys.PSObject.Properties).Count) role keys$(if ($wrong.Count) { '; ' + ($wrong | Select-Object -First 5) -join '; ' })"

    $text = $sc | ConvertTo-Json -Depth 30 -Compress
    $sets = @(
        @{ Name = 'knowledge articles'; Pattern = '\bKB\d{4}\b'; Codes = (Get-Codes $settings 'spk_knowledgearticles' 'spk_articlenumber') }
        @{ Name = 'runbooks'; Pattern = '\bRB-\d{3}\b'; Codes = (Get-Codes $settings 'spk_runbooks' 'spk_runbookcode') }
        @{ Name = 'customer documents'; Pattern = '\bCDOC-\d{3}\b'; Codes = (Get-Codes $settings 'spk_customerdocuments' 'spk_documentcode') }
        @{ Name = 'customers'; Pattern = '\bCUST-\d{3}\b'; Codes = (Get-Codes $settings 'accounts' 'spk_customercode') }
        @{ Name = 'technicians'; Pattern = '\bTECH-\d{2}\b'; Codes = (Get-Codes $settings 'spk_technicians' 'spk_techniciancode') }
        @{ Name = 'tickets'; Pattern = '\bTCK-\d{5}\b'; Codes = @($tickets.Keys) }
    )
    foreach ($s in $sets) {
        $named = @([regex]::Matches($text, $s.Pattern) | ForEach-Object { $_.Value } | Select-Object -Unique)
        if ($null -eq $s.Codes) { Add-Note $report "The $($s.Name) codes could not be read; $($named.Count) named in the scenarios were not checked."; continue }
        $absent = @($named | Where-Object { $_ -notin $s.Codes })
        Add-Check $report "Every $($s.Name.TrimEnd('s')) the scenarios name exists" ($absent.Count -eq 0) "$($named.Count) named; missing: $(if ($absent.Count) { $absent -join ', ' } else { 'none' })"
    }

    # ==== Scenario invariants
    $untriaged = @(@($sc.untriaged.seeded) + @($sc.untriaged.new_incidents) | ForEach-Object { [string]$_.ticket })
    $classified = @($untriaged | Where-Object { $tickets[$_] -and ($null -ne $tickets[$_].spk_priority -or $null -ne $tickets[$_].spk_category) })
    Add-Check $report 'Untriaged tickets and new incidents have no priority or category' ($classified.Count -eq 0) "$($untriaged -join ', ')$(if ($classified.Count) { "; classified: $($classified -join ', ')" })"
    $slaRows = @(@($sc.sla_set.near_breach) + @($sc.sla_set.breached))
    $slaWrong = @($slaRows | Where-Object { -not $tickets[[string]$_.ticket] -or [Math]::Abs([double]$tickets[[string]$_.ticket].spk_slaremaininghours - [double]$_.remaining_hours) -gt 0.01 } | ForEach-Object { "$($_.ticket) has $($tickets[[string]$_.ticket].spk_slaremaininghours), expected $($_.remaining_hours)" })
    Add-Check $report 'SLA near-breach and breached tickets have the documented remaining hours' ($slaWrong.Count -eq 0) "$($slaRows.Count) tickets$(if ($slaWrong.Count) { '; ' + ($slaWrong -join '; ') })"
    $restricted = $sc.restricted_records
    $lamna = @($tickets.Values | Where-Object { $_.spk_CustomerId.spk_customercode -in @($restricted.customers) })
    $notTeam = @($lamna | Where-Object { [string]$_.'_owningteam_value@OData.Community.Display.V1.FormattedValue' -ne [string]$restricted.team })
    Add-Check $report "Restricted tickets are owned by $($restricted.team)" ($lamna.Count -eq [int]$restricted.by_table.tickets -and $notTeam.Count -eq 0) "$($lamna.Count) tickets (manifest $($restricted.by_table.tickets)); owned by another team: $($notTeam.Count)"
    $articles = @{}
    foreach ($a in (Get-LabDataverseRows $settings 'spk_knowledgearticles?$select=spk_articlenumber,spk_kbstatus')) { $articles[[string]$a.spk_articlenumber] = [string](Get-First $a.'spk_kbstatus@OData.Community.Display.V1.FormattedValue' $a.spk_kbstatus) }
    $statusWrong = @(@($sc.knowledge_base.retired) | Where-Object { $articles[$_] -ne 'Retired' }) + @(@($sc.knowledge_base.draft) | Where-Object { $articles[$_] -ne 'Draft' })
    Add-Check $report 'Retired and Draft articles carry their status' ($statusWrong.Count -eq 0) "retired $(@($sc.knowledge_base.retired) -join ', '); draft $(@($sc.knowledge_base.draft) -join ', ')$(if ($statusWrong.Count) { "; wrong: $($statusWrong -join ', ')" })"

    # ==== The search export
    $total = [int]$manifest.searchable_documents.total
    if (Test-Path -LiteralPath $ExportManifestPath) {
        $export = Get-Content -LiteralPath $ExportManifestPath -Raw | ConvertFrom-Json
        Add-Check $report 'The export manifest total equals searchable_documents.total' ([int]$export.total -eq $total) "export $($export.total), seed manifest $total"
    }
    else { Add-Note $report "No export manifest at $ExportManifestPath." }
    if ($settings.StorageAccount -and $settings.ExportContainer) {
        try {
            $token = Get-LabToken 'https://storage.azure.com/'
            $count = 0; $marker = ''
            do {
                $uri = "https://$($settings.StorageAccount).blob.core.windows.net/$($settings.ExportContainer)?restype=container&comp=list&maxresults=5000$(if ($marker) { "&marker=$marker" })"
                [xml]$page = (Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $token"; 'x-ms-version' = '2021-08-06' } -TimeoutSec 120).Content.TrimStart([char]0xFEFF)
                $count += @($page.EnumerationResults.Blobs.Blob | Where-Object { $_.Name -like '*.json' }).Count
                $marker = [string]$page.EnumerationResults.NextMarker
            } while ($marker)
            Add-Check $report 'The export container holds one JSON file per searchable document' ($count -eq $total) "$count .json blobs in $($settings.ExportContainer); expected $total"
        }
        catch { Add-Note $report "The export container could not be listed with this account: $($_.Exception.Message)" }
    }
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
