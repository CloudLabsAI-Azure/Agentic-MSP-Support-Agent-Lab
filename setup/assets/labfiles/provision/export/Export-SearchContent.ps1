#Requires -Version 7.0
<#
.SYNOPSIS
    Exports the searchable Service Desk content from Dataverse to Blob storage, one JSON file per
    document, for the Exercise 1 indexer (BUILD-SPEC 3.7).

.DESCRIPTION
    Runs during provisioning as the provisioning identity (id-prov): Dataverse read (Service Desk
    Agent Read or higher) and Storage Blob Data Contributor on the export account. It runs BEFORE
    the two new incidents are loaded, and it also skips their numbers, so they can never be indexed.

    Writes:
      servicedesk-export/<id>.json                 one document per file (container root)
      servicedesk-export-meta/export-manifest.json counts per document type, total, time, version
      C:\LabFiles\search\export-manifest.json      the same manifest, for the lab tools
      C:\LabFiles\search\sample-documents\         one exported document per type, for review in
                                                   Exercise 1 Task 2 (kb-KB0058.json among them)
    The container holds exactly the current export afterwards: blobs left by an earlier run that
    are not part of it are deleted.

    Documents and ids: kb-<KB number> (Knowledge article), cdoc-<document code> (Customer document),
    rb-<runbook code> (Runbook), ticket-<ticket number> (Ticket: historical and open),
    customer-<customer code> (Customer) and sla-snapshot (SLA snapshot). Fields are strings and
    absent values are left out. Not exported: ticket notes, contact details, the labeled
    configuration document (an annotation) and the two new incidents.

    The total and every per-type count must equal the seed manifest's searchable_documents, or the
    script stops with the difference.
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$SeedManifestPath = 'C:\LabFiles\seed\data\manifest.json',
    [string]$SearchFolder = 'C:\LabFiles\search'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$config = Get-LabConfig
$settings = Read-LabSettings -Path $SettingsPath
foreach ($key in 'DataverseUrl', 'StorageAccount', 'ServiceDeskAppUrl') { if (-not $settings[$key]) { throw "lab-settings.json has no $key." } }
$seed = Get-Content $SeedManifestPath -Raw | ConvertFrom-Json -AsHashtable
$dv = $settings.DataverseUrl.TrimEnd('/')
$account = $settings.StorageAccount
$exportContainer = $config.ExportContainer
$metaContainer = $config.ExportMetaContainer
$newIncidents = @($seed.new_incidents)
$culture = [Globalization.CultureInfo]::InvariantCulture

# ==== Dataverse reads
function Get-Columns([string]$table, [string[]]$wanted) {
    $existing = @((Invoke-Dataverse -OrgUrl $dv -Method GET -Path "EntityDefinitions(LogicalName='$table')/Attributes?`$select=LogicalName").Body.value.LogicalName)
    $missing = @($wanted | Where-Object { $_ -notin $existing })
    if ($missing.Count) { Write-Step "  $table has no column $($missing -join ', '); left out of the export" }
    return @($wanted | Where-Object { $_ -in $existing })
}
function Get-All([string]$path) {
    $rows = New-Object System.Collections.Generic.List[object]
    $uri = "$dv/api/data/v9.2/$path"
    while ($uri) {
        $page = Invoke-LabRest -Method GET -Uri $uri -Token (Get-DataverseToken -OrgUrl $dv) -Headers @{
            Accept = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'
            Prefer = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue",odata.maxpagesize=500' }
        foreach ($row in @($page.Body.value)) { $rows.Add($row) }
        $next = $page.Body.PSObject.Properties['@odata.nextLink']
        $uri = if ($next) { [string]$next.Value } else { $null }
    }
    return $rows.ToArray()
}
function Label($row, [string]$column) {
    if ($null -eq $row) { return $null }
    $p = $row.PSObject.Properties["$column@OData.Community.Display.V1.FormattedValue"]
    if ($p) { return [string]$p.Value }
    return $null
}
function Value($row, [string]$column) {
    if ($null -eq $row) { return $null }
    $p = $row.PSObject.Properties[$column]
    if ($p -and $null -ne $p.Value -and "$($p.Value)" -ne '') { return $p.Value }
    return $null
}
function Iso($value) {
    if ($null -eq $value -or "$value" -eq '') { return $null }
    $d = if ($value -is [datetime]) { $value } elseif ($value -is [datetimeoffset]) { $value.UtcDateTime } else { [datetime]::Parse("$value", $culture, [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal) }
    return $d.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $culture)
}
function Show($value) { if ($null -eq $value -or "$value" -eq '') { return 'not set' } return "$value" }
function When($value) { $iso = Iso $value; if ($iso) { return $iso.Replace('T', ' ').Replace('Z', ' UTC') } return 'not set' }
function RecordUrl([string]$table, [string]$id) { return "$dv/main.aspx?appname=$($config.Dataverse.AppUniqueName)&pagetype=entityrecord&etn=$table&id=$id" }
function New-Doc([System.Collections.IDictionary]$fields) {
    $doc = [ordered]@{}
    foreach ($k in $fields.Keys) { $v = $fields[$k]; if ($null -ne $v -and "$v" -ne '') { $doc[$k] = [string]$v } }
    return $doc
}

Write-Step 'Reading Dataverse'
$articleCols = Get-Columns 'spk_knowledgearticle' @('spk_knowledgearticleid', 'spk_articlenumber', 'spk_name', 'spk_category', 'spk_product', 'spk_symptom', 'spk_cause',
    'spk_resolution', 'spk_appliesto', 'spk_appliestoversions', 'spk_appliestotiers', 'spk_appliestocontracts', 'spk_kbstatus', 'spk_lastreviewedon', 'spk_keywords', 'spk_relatedarticles')
$articles = Get-All "spk_knowledgearticles?`$select=$($articleCols -join ',')"
$runbookCols = Get-Columns 'spk_runbook' @('spk_runbookid', 'spk_runbookcode', 'spk_name', 'spk_category', 'spk_product', 'spk_trigger', 'spk_steps', 'spk_escalationpath',
    'spk_relatedarticles', 'spk_lastreviewedon')
$runbooks = Get-All "spk_runbooks?`$select=$($runbookCols -join ',')"
$accountCols = Get-Columns 'account' @('accountid', 'name', 'spk_customercode', 'spk_industry', 'address1_city', 'spk_slatier', 'spk_contracttype', 'spk_seatcount', 'spk_sitecount',
    'spk_backupagentversion', 'spk_remoteaccessversion', 'spk_gatewayfirmware', 'spk_endpointagentversion', 'spk_accountmanager', 'description', 'spk_servicesinscope', 'spk_configurationnotes')
$customers = Get-All "accounts?`$select=$($accountCols -join ',')&`$filter=spk_customercode ne null"
$procedures = Get-All 'spk_customerprocedures?$select=spk_procedurecode,spk_name,spk_proceduretype,spk_details,spk_appliesto,_spk_customerid_value'
$docCols = Get-Columns 'spk_customerdocument' @('spk_customerdocumentid', 'spk_documentcode', 'spk_name', 'spk_documenttype', 'spk_body', 'spk_version', 'spk_lastreviewedon')
$customerDocuments = Get-All "spk_customerdocuments?`$select=$($docCols -join ',')&`$expand=spk_CustomerId(`$select=name,spk_customercode,spk_slatier,spk_contracttype)"
$ticketCols = Get-Columns 'spk_ticket' @('spk_ticketid', 'spk_ticketnumber', 'spk_name', 'spk_description', 'spk_category', 'spk_subcategory', 'spk_priority', 'spk_status',
    'spk_product', 'spk_productversion', 'spk_affectedusers', 'spk_openedon', 'spk_resolvedon', 'spk_resolutionsummary', 'spk_outcome', 'spk_tags', 'spk_slatargethours',
    'spk_slaelapsedhours', 'spk_slaremaininghours', 'spk_sladueon', 'spk_slastatus', 'spk_slacalculatedon', 'spk_isescalated', 'spk_escalationlevel', 'spk_escalatedon',
    'spk_escalationreason')
$tickets = @(Get-All ("spk_tickets?`$select=$($ticketCols -join ',')" +
    '&$expand=spk_CustomerId($select=name,spk_customercode,spk_slatier,spk_contracttype),spk_AssignedTechnicianId($select=spk_name),spk_RelatedArticleId($select=spk_articlenumber)') |
    Where-Object { $_.spk_ticketnumber -notin $newIncidents })
$policies = Get-All 'spk_slapolicies?$select=spk_slatier,spk_priority,spk_responsehours,spk_resolutionhours,spk_description'
Write-Step ("  {0} articles, {1} customer documents, {2} runbooks, {3} tickets, {4} customers, {5} procedures, {6} SLA policies" -f
    $articles.Count, $customerDocuments.Count, $runbooks.Count, $tickets.Count, $customers.Count, $procedures.Count, $policies.Count)

# ==== Documents
$docs = New-Object System.Collections.Generic.List[object]
foreach ($a in ($articles | Sort-Object spk_articlenumber)) {
    $content = "Knowledge article $($a.spk_articlenumber): $($a.spk_name). Status: $(Show (Label $a 'spk_kbstatus')). Product: $(Show (Label $a 'spk_product')). " +
        "Category: $(Show (Label $a 'spk_category')). Last reviewed: $(When (Value $a 'spk_lastreviewedon')). Applies to: $(Show (Value $a 'spk_appliesto')) " +
        "Versions: $(Show (Value $a 'spk_appliestoversions')). SLA tiers: $(Show (Value $a 'spk_appliestotiers')). Contracts: $(Show (Value $a 'spk_appliestocontracts')). " +
        "Related articles: $(Show (Value $a 'spk_relatedarticles')). Symptom: $(Value $a 'spk_symptom') Cause: $(Value $a 'spk_cause') " +
        "Resolution: $(Value $a 'spk_resolution') Keywords: $(Show (Value $a 'spk_keywords'))"
    $docs.Add((New-Doc ([ordered]@{
        id = "kb-$($a.spk_articlenumber)"; docType = 'Knowledge article'; title = "$($a.spk_articlenumber): $($a.spk_name)"
        url = (RecordUrl 'spk_knowledgearticle' $a.spk_knowledgearticleid); sourceId = $a.spk_articlenumber; content = $content
        slaTier = (Value $a 'spk_appliestotiers'); contractType = (Value $a 'spk_appliestocontracts'); product = (Label $a 'spk_product')
        productVersion = (Value $a 'spk_appliestoversions'); category = (Label $a 'spk_category'); articleStatus = (Label $a 'spk_kbstatus')
        relatedArticles = (Value $a 'spk_relatedarticles'); tags = (Value $a 'spk_keywords') })))
}
foreach ($d in ($customerDocuments | Sort-Object spk_documentcode)) {
    $cust = $d.spk_CustomerId
    $content = "Customer document $($d.spk_documentcode): $($d.spk_name). Type: $(Show (Label $d 'spk_documenttype')). " +
        "Customer: $(if ($cust) { "$($cust.name) ($($cust.spk_customercode))" } else { 'all customers' }). Version: $(Show (Value $d 'spk_version')). " +
        "Last reviewed: $(When (Value $d 'spk_lastreviewedon')). $(Value $d 'spk_body')"
    $docs.Add((New-Doc ([ordered]@{
        id = "cdoc-$($d.spk_documentcode)"; docType = 'Customer document'; title = "$($d.spk_documentcode): $($d.spk_name)"
        url = (RecordUrl 'spk_customerdocument' $d.spk_customerdocumentid); sourceId = $d.spk_documentcode; content = $content
        customer = $cust.name; customerCode = $cust.spk_customercode; slaTier = (Label $cust 'spk_slatier'); contractType = (Label $cust 'spk_contracttype') })))
}
foreach ($r in ($runbooks | Sort-Object spk_runbookcode)) {
    $content = "Runbook $($r.spk_runbookcode): $($r.spk_name). Category: $(Show (Label $r 'spk_category')). Product: $(Show (Label $r 'spk_product')). " +
        "Last reviewed: $(When (Value $r 'spk_lastreviewedon')). When to use: $(Value $r 'spk_trigger') Steps: $(Value $r 'spk_steps') " +
        "Escalation path: $(Value $r 'spk_escalationpath') Related articles: $(Show (Value $r 'spk_relatedarticles'))"
    $docs.Add((New-Doc ([ordered]@{
        id = "rb-$($r.spk_runbookcode)"; docType = 'Runbook'; title = "$($r.spk_runbookcode): $($r.spk_name)"
        url = (RecordUrl 'spk_runbook' $r.spk_runbookid); sourceId = $r.spk_runbookcode; content = $content
        product = (Label $r 'spk_product'); category = (Label $r 'spk_category'); relatedArticles = (Value $r 'spk_relatedarticles') })))
}
$openStatuses = 'New', 'In Progress', 'Waiting on Customer'
$openTickets = @($tickets | Where-Object { (Label $_ 'spk_status') -in $openStatuses })
$snapshotTime = ($openTickets | Where-Object { Value $_ 'spk_slacalculatedon' } | Select-Object -First 1).spk_slacalculatedon
if (-not $snapshotTime) { $snapshotTime = $seed.anchor }
foreach ($c in ($customers | Sort-Object spk_customercode)) {
    $mine = @($openTickets | Where-Object { $_.spk_CustomerId.spk_customercode -eq $c.spk_customercode } | Sort-Object spk_openedon)
    $openText = if ($mine.Count) {
        "Open tickets as of $(When $snapshotTime) ($($mine.Count)): " + (($mine | ForEach-Object {
            "$($_.spk_ticketnumber) '$($_.spk_name)': $(Label $_ 'spk_status'), $(Show (Label $_ 'spk_priority')), $(Show (Label $_ 'spk_category'))." }) -join ' ')
    } else { "Open tickets as of $(When $snapshotTime): none." }
    $agreed = @($procedures | Where-Object { $_._spk_customerid_value -eq $c.accountid } | Sort-Object spk_procedurecode)
    $procText = if ($agreed.Count) {
        'Agreed procedures: ' + (($agreed | ForEach-Object { "[$($_.spk_procedurecode)] $($_.spk_name) ($(Label $_ 'spk_proceduretype')): $($_.spk_details)" }) -join ' ')
    } else { 'Agreed procedures: the standard Relecloud procedures apply.' }
    $content = "Customer $($c.name) ($($c.spk_customercode)). Industry: $(Show (Value $c 'spk_industry')). City: $(Show (Value $c 'address1_city')). " +
        "SLA tier: $(Show (Label $c 'spk_slatier')). Contract type: $(Show (Label $c 'spk_contracttype')). Managed seats: $(Show (Value $c 'spk_seatcount')). " +
        "Sites: $(Show (Value $c 'spk_sitecount')). Services in scope: $(Show (Value $c 'spk_servicesinscope')). Deployed versions: Relecloud Backup Agent " +
        "$(Show (Value $c 'spk_backupagentversion')); Remote Access client $(Show (Value $c 'spk_remoteaccessversion')); Secure Gateway firmware " +
        "$(Show (Value $c 'spk_gatewayfirmware')); Endpoint Agent $(Show (Value $c 'spk_endpointagentversion')). Account manager: $(Show (Value $c 'spk_accountmanager')). " +
        "Configuration notes: $(Show (Value $c 'spk_configurationnotes')) Profile: $(Value $c 'description') $procText $openText"
    $docs.Add((New-Doc ([ordered]@{
        id = "customer-$($c.spk_customercode)"; docType = 'Customer'; title = "Customer profile: $($c.name)"
        url = (RecordUrl 'account' $c.accountid); sourceId = $c.spk_customercode; content = $content; customer = $c.name
        customerCode = $c.spk_customercode; slaTier = (Label $c 'spk_slatier'); contractType = (Label $c 'spk_contracttype') })))
}
foreach ($t in ($tickets | Sort-Object spk_ticketnumber)) {
    $cust = $t.spk_CustomerId
    $sla = if ($null -ne (Value $t 'spk_slatargethours')) {
        "SLA: target $($t.spk_slatargethours) business hours, elapsed $($t.spk_slaelapsedhours), remaining $($t.spk_slaremaininghours), due $(When (Value $t 'spk_sladueon')), status $(Show (Label $t 'spk_slastatus')), as of $(When (Value $t 'spk_slacalculatedon'))."
    } else { 'SLA: not set (ticket not yet triaged).' }
    $escalation = if ($t.spk_isescalated) { "Escalated: yes, to $(Show (Label $t 'spk_escalationlevel')) on $(When (Value $t 'spk_escalatedon')). Reason: $(Value $t 'spk_escalationreason')" } else { 'Escalated: no.' }
    $content = "Ticket $($t.spk_ticketnumber): $($t.spk_name). Customer: $($cust.name) ($($cust.spk_customercode)), SLA tier $(Show (Label $cust 'spk_slatier')), " +
        "contract $(Show (Label $cust 'spk_contracttype')). Status: $(Show (Label $t 'spk_status')). Priority: $(Show (Label $t 'spk_priority')). " +
        "Category: $(Show (Label $t 'spk_category')). Subcategory: $(Show (Label $t 'spk_subcategory')). Product: $(Show (Label $t 'spk_product')) $(Value $t 'spk_productversion'). " +
        "Affected users: $(Show (Value $t 'spk_affectedusers')). Opened on: $(When (Value $t 'spk_openedon')). Resolved on: $(When (Value $t 'spk_resolvedon')). " +
        "Assigned technician: $(Show $t.spk_AssignedTechnicianId.spk_name). Related article: $(Show $t.spk_RelatedArticleId.spk_articlenumber). " +
        "Outcome: $(Show (Label $t 'spk_outcome')). Tags: $(Show (Value $t 'spk_tags')). Description: $(Value $t 'spk_description') " +
        "Resolution: $(Show (Value $t 'spk_resolutionsummary')) $escalation $sla"
    $docs.Add((New-Doc ([ordered]@{
        id = "ticket-$($t.spk_ticketnumber)"; docType = 'Ticket'; title = "$($t.spk_ticketnumber): $($t.spk_name)"
        url = (RecordUrl 'spk_ticket' $t.spk_ticketid); sourceId = $t.spk_ticketnumber; content = $content
        customer = $cust.name; customerCode = $cust.spk_customercode; slaTier = (Label $cust 'spk_slatier'); contractType = (Label $cust 'spk_contracttype')
        product = (Label $t 'spk_product'); productVersion = (Value $t 'spk_productversion'); category = (Label $t 'spk_category')
        subcategory = (Label $t 'spk_subcategory'); relatedArticles = $t.spk_RelatedArticleId.spk_articlenumber; tags = (Value $t 'spk_tags')
        priority = (Label $t 'spk_priority'); status = (Label $t 'spk_status'); outcome = (Label $t 'spk_outcome')
        openedOn = (Iso (Value $t 'spk_openedon')); resolvedOn = (Iso (Value $t 'spk_resolvedon')) })))
}
$ranked = @($openTickets | Where-Object { $null -ne (Value $_ 'spk_slaremaininghours') } | Sort-Object { [double]$_.spk_slaremaininghours })
$untriaged = @($openTickets | Where-Object { $null -eq (Value $_ 'spk_slaremaininghours') })
$rank = 0
$lines = foreach ($t in $ranked) {
    $rank++
    "$rank. $($t.spk_ticketnumber) ($($t.spk_CustomerId.name), $($t.spk_CustomerId.spk_customercode), SLA tier $(Label $t.spk_CustomerId 'spk_slatier')): " +
    "$(Label $t 'spk_priority'), target $($t.spk_slatargethours), elapsed $($t.spk_slaelapsedhours), remaining $($t.spk_slaremaininghours) business hours, " +
    "due $(When (Value $t 'spk_sladueon')), SLA status $(Label $t 'spk_slastatus'). '$($t.spk_name)'."
}
$untriagedText = if ($untriaged.Count) { ($untriaged | ForEach-Object { "$($_.spk_ticketnumber) ($($_.spk_CustomerId.name)) '$($_.spk_name)'" }) -join '; ' } else { 'none' }
$targets = ($policies | Group-Object spk_slatier | Sort-Object { [long]$_.Name } | ForEach-Object {
    "$(Label $_.Group[0] 'spk_slatier'): " + (($_.Group | Sort-Object spk_priority | ForEach-Object { "$(Label $_ 'spk_priority') $($_.spk_resolutionhours)" }) -join ', ')
}) -join '; '
$rules = $policies | ForEach-Object { "$($_.spk_description)" } | Where-Object { $_ -match 'Relecloud priority rules:' } | Select-Object -First 1
$rules = if ($rules) { $rules.Substring($rules.IndexOf('Relecloud priority rules:')) } else { '' }
$viewId = (Get-All "savedqueries?`$select=savedqueryid&`$filter=name eq 'Open Tickets by SLA Remaining' and returnedtypecode eq 'spk_ticket'" | Select-Object -First 1).savedqueryid
$slaUrl = if ($viewId) { "$dv/main.aspx?appname=$($config.Dataverse.AppUniqueName)&pagetype=entitylist&etn=spk_ticket&viewid=$viewId&viewType=1039" }
          else { "$dv/main.aspx?appname=$($config.Dataverse.AppUniqueName)&pagetype=entitylist&etn=spk_ticket" }
$snapshot = "SLA risk snapshot of every open ticket, as of $(When $snapshotTime). SLA figures are business hours (Monday to Friday, 08:00 to 18:00 UTC, no holidays); " +
    "elapsed plus remaining equals the target. Negative remaining hours mean the SLA is already breached. Ordered by remaining business hours, lowest first: " +
    ($lines -join ' ') + " Open tickets not yet triaged, so they have no priority and no SLA: $untriagedText. " +
    "SLA resolution targets in business hours by SLA tier and priority: $targets. $rules"
$docs.Add((New-Doc ([ordered]@{ id = 'sla-snapshot'; docType = 'SLA snapshot'; title = 'SLA risk snapshot: open tickets by remaining business hours, SLA targets and priority rules'
    url = $slaUrl; sourceId = 'SLA-SNAPSHOT'; content = $snapshot })))

# ==== Counts against the seed manifest
$typeKeys = [ordered]@{ 'Knowledge article' = 'knowledge_articles'; 'Customer document' = 'customer_documents'; 'Runbook' = 'runbooks'; 'Ticket' = 'tickets'; 'Customer' = 'customers'; 'SLA snapshot' = 'sla_snapshot' }
$counts = [ordered]@{}
$countsByKey = [ordered]@{}
foreach ($type in $typeKeys.Keys) {
    $n = @($docs | Where-Object { $_.docType -eq $type }).Count
    $counts[$type] = $n
    $countsByKey[$typeKeys[$type]] = $n
}
$expected = $seed.searchable_documents
$differences = @(foreach ($type in $typeKeys.Keys) {
    $key = $typeKeys[$type]
    if ($null -ne $expected[$key] -and [int]$expected[$key] -ne $counts[$type]) { "$type $($counts[$type]) (expected $($expected[$key]))" }
})
if ([int]$expected.total -ne $docs.Count) { $differences += "total $($docs.Count) (expected $($expected.total))" }
if ($differences.Count) { throw "The export does not match the seed manifest: $($differences -join ', '). Check the seed load (load-summary.json)." }
$ids = @($docs | ForEach-Object { $_.id })
if (@($ids | Select-Object -Unique).Count -ne $ids.Count) { throw 'Two exported documents have the same id.' }
$badIds = @($ids | Where-Object { $_ -notmatch '^[A-Za-z0-9][A-Za-z0-9_=-]*$' })
if ($badIds.Count) { throw "Document ids with characters a search key does not allow: $($badIds -join ', ')" }

# ==== Upload: one blob per document, then remove blobs that are not part of this export
Write-Step "Uploading $($docs.Count) documents to $account/$exportContainer"
$storageToken = Get-ManagedIdentityToken 'https://storage.azure.com/'
$payloads = foreach ($doc in $docs) { [pscustomobject]@{ Name = "$($doc.id).json"; Json = ($doc | ConvertTo-Json -Depth 4) } }
$failures = $payloads | ForEach-Object -ThrottleLimit 8 -Parallel {
    $item = $_
    $uri = "https://$($using:account).blob.core.windows.net/$($using:exportContainer)/$($item.Name)"
    $headers = @{ Authorization = "Bearer $($using:storageToken)"; 'x-ms-version' = '2023-11-03'; 'x-ms-blob-type' = 'BlockBlob'; 'x-ms-blob-content-type' = 'application/json' }
    $bytes = [Text.Encoding]::UTF8.GetBytes($item.Json)
    $ok = $false
    for ($i = 1; $i -le 5 -and -not $ok; $i++) {
        try { Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $bytes -ContentType 'application/json' -TimeoutSec 60 | Out-Null; $ok = $true }
        catch { Start-Sleep -Seconds (3 * $i) }
    }
    if (-not $ok) { $item.Name }
}
if (@($failures).Count) { throw "Uploading failed for $(@($failures).Count) documents, for example $(@($failures)[0])." }
$wanted = @($payloads.Name)
$stale = @(Get-BlobNames -Account $account -Container $exportContainer -Token $storageToken | Where-Object { $_ -notin $wanted })
foreach ($name in $stale) {
    $null = Invoke-LabRest -Method DELETE -Uri "https://$account.blob.core.windows.net/$exportContainer/$name" -Token $storageToken -Headers @{ 'x-ms-version' = '2023-11-03' } -AllowNotFound
}
$inContainer = @(Get-BlobNames -Account $account -Container $exportContainer -Token $storageToken).Count
if ($inContainer -ne $docs.Count) { throw "The export container holds $inContainer blobs; expected $($docs.Count)." }

# ==== Manifest (outside the indexed container) and the sample documents
$manifest = [ordered]@{
    goldenEnvironmentVersion = $config.GoldenEnvironmentVersion
    generatedOnUtc           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    source                   = $dv
    storageAccount           = $account
    container                = $exportContainer
    counts                   = $counts
    countsByKey              = $countsByKey
    total                    = $docs.Count
    expectedTotal            = [int]$expected.total
    seedDataVersion          = $seed.data_version
    notIndexed               = @($seed.not_indexed)
    newIncidentsExcluded     = $newIncidents
    staleBlobsRemoved        = $stale.Count
}
$manifestJson = $manifest | ConvertTo-Json -Depth 5
Set-BlobContent -Account $account -Container $metaContainer -Name 'export-manifest.json' -Text $manifestJson -Token $storageToken
New-Item -ItemType Directory -Path $SearchFolder -Force | Out-Null
Set-Content -Path (Join-Path $SearchFolder 'export-manifest.json') -Value $manifestJson -Encoding utf8NoBOM

$samplesFolder = Join-Path $SearchFolder 'sample-documents'
New-Item -ItemType Directory -Path $samplesFolder -Force | Out-Null
Get-ChildItem -Path $samplesFolder -Filter '*.json' -File | Remove-Item -Force
$preferred = @{ 'Knowledge article' = 'kb-KB0058'; 'Customer document' = 'cdoc-CDOC-007'; 'Runbook' = 'rb-RB-005'; 'Ticket' = 'ticket-TCK-10489'; 'Customer' = 'customer-CUST-007'; 'SLA snapshot' = 'sla-snapshot' }
$samples = foreach ($type in $typeKeys.Keys) {
    $pick = $docs | Where-Object { $_.id -eq $preferred[$type] } | Select-Object -First 1
    if (-not $pick) { $pick = $docs | Where-Object { $_.docType -eq $type } | Select-Object -First 1 }
    if ($pick) {
        Set-Content -Path (Join-Path $samplesFolder "$($pick.id).json") -Value ($pick | ConvertTo-Json -Depth 4) -Encoding utf8NoBOM
        $pick.id
    }
}

[pscustomobject]@{
    Documents = $docs.Count
    Counts    = $counts
    Container = "$account/$exportContainer"
    Manifest  = "$account/$metaContainer/export-manifest.json"
    Samples   = @($samples)
    Stale     = $stale.Count
}
