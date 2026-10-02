#Requires -Version 7.0
<#
.SYNOPSIS
    Loads the Service Desk knowledge content into your Azure AI Search index and checks the
    document count against the seeded data.

.DESCRIPTION
    The content comes from C:\LabFiles\search\export, which lab provisioning exported from
    your Dataverse environment before it loaded the two new incidents, so the index is the
    knowledge and history the agent should draw on and the new incidents are not in it.

    What is indexed, and what is deliberately left out:
      Knowledge articles  title, symptom, cause, resolution, applicability, status
      Runbooks            trigger, steps, escalation path, related articles
      Customers           profile, SLA tier, contract type, deployed product versions, the
                          procedures agreed with the customer, and a list of open tickets
      Tickets             title, description, customer context, resolution, escalation, SLA
      SLA snapshot        one document ranking every open ticket by remaining business hours,
                          with the SLA resolution targets and the Relecloud priority rules
      NOT indexed         ticket notes (internal notes must never reach an answer), contact
                          details (personal data the agent doesn't need for grounding) and
                          customer documents (protected by their sensitivity label)
    The customer open-ticket lists and the SLA snapshot exist because a search index returns
    the few most relevant documents for a question, not a sorted or complete list.
    Each document gets an embedding from your text-embedding-3-small deployment, so the agent
    can use vector and hybrid search. The url field links every result back to its record in
    the Service Desk app, which is what makes a citation checkable.

    -Export (lab provisioning only) builds the export from Dataverse.
    Uses your own Azure CLI sign-in. Run 'az login' first.

.EXAMPLE
    C:\LabFiles\search\Load-SearchIndex.ps1
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\team-settings.json',
    [string]$IndexName = 'servicedesk-knowledge',
    [int]$EmbeddingBatch = 16,
    [string]$OpenAIEndpoint,
    [switch]$Export,
    [string]$ExportPath,
    [string]$SeedManifestPath = 'C:\LabFiles\seed\data\manifest.json'
)

$ErrorActionPreference = 'Stop'
$settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
if (-not $ExportPath) { $ExportPath = $settings.SearchExport ?? 'C:\LabFiles\search\export' }
$documentsFile = Join-Path $ExportPath 'documents.json'
$manifestFile = Join-Path $ExportPath 'export-manifest.json'
$tokens = @{}
function Token([string]$resource) {
    if (-not $tokens[$resource]) {
        $tokens[$resource] = az account get-access-token --resource $resource --query accessToken --output tsv
        if (-not $tokens[$resource]) { throw "No token for $resource. Run 'az login' first." }
    }
    return $tokens[$resource]
}

function Export-Documents {
    $dv = $settings.DataverseUrl.TrimEnd('/')
    function Get-All([string]$path) {
        $rows = @()
        $uri = "$dv/api/data/v9.2/$path"
        $headers = @{ Authorization = "Bearer $(Token $dv)"; Accept = 'application/json'
                      Prefer = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue",odata.maxpagesize=500' }
        while ($uri) {
            $page = Invoke-RestMethod -Uri $uri -Headers $headers
            $rows += $page.value
            $uri = $page.'@odata.nextLink'
        }
        return $rows
    }
    function Label($row, [string]$column) { return $row."$column@OData.Community.Display.V1.FormattedValue" }
    function When($value) {
        # Dates in the indexed text are written as unambiguous UTC, for example 2026-10-07 14:00 UTC.
        if ($null -eq $value -or "$value" -eq '') { return 'not set' }
        $format = "yyyy-MM-dd HH:mm 'UTC'"
        $culture = [Globalization.CultureInfo]::InvariantCulture
        if ($value -is [datetimeoffset]) { return $value.UtcDateTime.ToString($format, $culture) }
        if ($value -is [datetime]) {
            $utc = if ($value.Kind -eq [DateTimeKind]::Local) { $value.ToUniversalTime() } else { $value }
            return $utc.ToString($format, $culture)
        }
        return [string]$value
    }
    function RecordUrl([string]$table, [string]$id) {
        return "$dv/main.aspx?appname=spk_ServiceDesk&pagetype=entityrecord&etn=$table&id=$id"
    }

    # The two new incidents are never indexed, even when the export is re-run after they are loaded.
    $newIncidents = if (Test-Path $SeedManifestPath) { @((Get-Content $SeedManifestPath -Raw | ConvertFrom-Json).new_incidents) } else { @() }

    Write-Host 'Reading Dataverse...' -ForegroundColor Cyan
    $articles = Get-All 'spk_knowledgearticles?$select=spk_knowledgearticleid,spk_articlenumber,spk_name,spk_category,spk_product,spk_symptom,spk_cause,spk_resolution,spk_appliesto,spk_appliestoversions,spk_appliestotiers,spk_appliestocontracts,spk_kbstatus,spk_lastreviewedon,spk_keywords'
    $runbooks = Get-All 'spk_runbooks?$select=spk_runbookid,spk_runbookcode,spk_name,spk_category,spk_product,spk_trigger,spk_steps,spk_escalationpath,spk_relatedarticles,spk_lastreviewedon'
    $customers = Get-All 'accounts?$select=accountid,name,spk_customercode,spk_industry,address1_city,spk_slatier,spk_contracttype,spk_seatcount,spk_sitecount,spk_backupagentversion,spk_remoteaccessversion,spk_gatewayfirmware,spk_endpointagentversion,spk_accountmanager,description&$filter=spk_customercode ne null'
    $procedures = Get-All 'spk_customerprocedures?$select=spk_procedurecode,spk_name,spk_proceduretype,spk_details,spk_appliesto,_spk_customerid_value'
    $tickets = @(Get-All ('spk_tickets?$select=spk_ticketid,spk_ticketnumber,spk_name,spk_description,spk_category,spk_priority,spk_status,spk_product,spk_productversion,spk_affectedusers,spk_openedon,spk_resolvedon,spk_resolutionsummary,spk_slatargethours,spk_slaelapsedhours,spk_slaremaininghours,spk_sladueon,spk_slastatus,spk_slacalculatedon,spk_isescalated,spk_escalationlevel,spk_escalatedon,spk_escalationreason' +
        '&$expand=spk_CustomerId($select=name,spk_customercode,spk_slatier,spk_contracttype),spk_AssignedTechnicianId($select=spk_name),spk_RelatedArticleId($select=spk_articlenumber)') |
        Where-Object { $_.spk_ticketnumber -notin $newIncidents })
    $policies = Get-All 'spk_slapolicies?$select=spk_slatier,spk_priority,spk_responsehours,spk_resolutionhours,spk_description'
    Write-Host ("  {0} knowledge articles, {1} runbooks, {2} tickets, {3} customers, {4} procedures, {5} SLA policies" -f
        $articles.Count, $runbooks.Count, $tickets.Count, $customers.Count, $procedures.Count, $policies.Count)

    $openStatuses = 'New', 'In Progress', 'Waiting on Customer'
    $openTickets = @($tickets | Where-Object { (Label $_ 'spk_status') -in $openStatuses })
    $snapshotTime = ($openTickets | Where-Object { $_.spk_slacalculatedon } | Select-Object -First 1).spk_slacalculatedon
    function OpenTicketLine($t) {
        $priority = (Label $t 'spk_priority') ?? 'priority not set'
        $category = (Label $t 'spk_category') ?? 'category not set'
        $sla = if ($null -ne $t.spk_slatargethours) {
            "SLA remaining $($t.spk_slaremaininghours) of $($t.spk_slatargethours) business hours ($(Label $t 'spk_slastatus'))"
        } else { 'SLA not set (not yet triaged)' }
        return "$($t.spk_ticketnumber) '$($t.spk_name)': $(Label $t 'spk_status'), $priority, $category, opened $(When $t.spk_openedon), $sla."
    }
    $viewId = (Get-All "savedqueries?`$select=savedqueryid&`$filter=name eq 'Open Tickets by SLA Remaining' and returnedtypecode eq 'spk_ticket'" |
        Select-Object -First 1).savedqueryid
    $slaViewUrl = if ($viewId) { "$dv/main.aspx?appname=spk_ServiceDesk&pagetype=entitylist&etn=spk_ticket&viewid=$viewId&viewType=1039" }
                  else { "$dv/main.aspx?appname=spk_ServiceDesk&pagetype=entitylist&etn=spk_ticket" }

    $docs = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($a in $articles) {
        $content = "Knowledge article $($a.spk_articlenumber): $($a.spk_name). Status: $(Label $a 'spk_kbstatus'). " +
            "Last reviewed: $(When $a.spk_lastreviewedon). Product: $(Label $a 'spk_product'). Applies to: $($a.spk_appliesto) " +
            "Symptom: $($a.spk_symptom) Cause: $($a.spk_cause) Resolution: $($a.spk_resolution) Keywords: $($a.spk_keywords)"
        $docs.Add(@{ id = "kb-$($a.spk_articlenumber)"; docType = 'Knowledge article'; title = "$($a.spk_articlenumber): $($a.spk_name)"
            url = (RecordUrl 'spk_knowledgearticle' $a.spk_knowledgearticleid); sourceId = $a.spk_articlenumber; content = $content
            product = (Label $a 'spk_product'); productVersion = $a.spk_appliestoversions; category = (Label $a 'spk_category')
            slaTier = $a.spk_appliestotiers; contractType = $a.spk_appliestocontracts; articleStatus = (Label $a 'spk_kbstatus') })
    }
    foreach ($r in $runbooks) {
        $content = "Runbook $($r.spk_runbookcode): $($r.spk_name). Category: $(Label $r 'spk_category'). Product: $(Label $r 'spk_product'). " +
            "Last reviewed: $(When $r.spk_lastreviewedon). When to use: $($r.spk_trigger) Steps: $($r.spk_steps) " +
            "Escalation path: $($r.spk_escalationpath) Related articles: $($r.spk_relatedarticles)"
        $docs.Add(@{ id = "runbook-$($r.spk_runbookcode)"; docType = 'Runbook'; title = "$($r.spk_runbookcode): $($r.spk_name)"
            url = (RecordUrl 'spk_runbook' $r.spk_runbookid); sourceId = $r.spk_runbookcode; content = $content
            product = (Label $r 'spk_product'); category = (Label $r 'spk_category'); relatedArticle = $r.spk_relatedarticles })
    }
    foreach ($c in $customers) {
        $mine = @($openTickets | Where-Object { $_.spk_CustomerId.spk_customercode -eq $c.spk_customercode } | Sort-Object spk_openedon)
        $openText = if ($mine.Count) {
            "Open tickets as of $(When $snapshotTime) ($($mine.Count)): " + (($mine | ForEach-Object { OpenTicketLine $_ }) -join ' ')
        } else { "Open tickets as of $(When $snapshotTime): none." }
        $agreed = @($procedures | Where-Object { $_._spk_customerid_value -eq $c.accountid } | Sort-Object spk_procedurecode)
        $procText = if ($agreed.Count) {
            'Agreed procedures: ' + (($agreed | ForEach-Object {
                "[$($_.spk_procedurecode)] $($_.spk_name) ($(Label $_ 'spk_proceduretype'); applies to $($_.spk_appliesto)): $($_.spk_details)" }) -join ' ')
        } else { 'Agreed procedures: the standard Relecloud procedures apply.' }
        $content = "Customer $($c.name) ($($c.spk_customercode)). Industry: $($c.spk_industry). City: $($c.address1_city). " +
            "SLA tier: $(Label $c 'spk_slatier'). Contract type: $(Label $c 'spk_contracttype'). Managed seats: $($c.spk_seatcount). Sites: $($c.spk_sitecount). " +
            "Deployed versions: Relecloud Backup Agent $($c.spk_backupagentversion); Remote Access client $($c.spk_remoteaccessversion); " +
            "Secure Gateway firmware $($c.spk_gatewayfirmware); Endpoint Agent $($c.spk_endpointagentversion). " +
            "Account manager: $($c.spk_accountmanager). Profile: $($c.description) $procText $openText"
        $docs.Add(@{ id = "customer-$($c.spk_customercode)"; docType = 'Customer'; title = "Customer profile: $($c.name)"
            url = (RecordUrl 'account' $c.accountid); sourceId = $c.spk_customercode; content = $content; customer = $c.name
            customerCode = $c.spk_customercode; slaTier = (Label $c 'spk_slatier'); contractType = (Label $c 'spk_contracttype') })
    }
    foreach ($t in $tickets) {
        $cust = $t.spk_CustomerId
        $sla = if ($null -ne $t.spk_slatargethours) {
            "SLA: target $($t.spk_slatargethours) business hours, elapsed $($t.spk_slaelapsedhours), remaining $($t.spk_slaremaininghours), " +
            "due $(When $t.spk_sladueon), status $(Label $t 'spk_slastatus'), as of $(When $t.spk_slacalculatedon)."
        } else { 'SLA: not set (ticket not yet triaged).' }
        $escalation = if ($t.spk_isescalated) {
            "Escalated: yes, to $(Label $t 'spk_escalationlevel') on $(When $t.spk_escalatedon). Reason: $($t.spk_escalationreason)"
        } else { 'Escalated: no.' }
        $content = "Ticket $($t.spk_ticketnumber): $($t.spk_name). Customer: $($cust.name) ($($cust.spk_customercode)), SLA tier $(Label $cust 'spk_slatier'), " +
            "contract $(Label $cust 'spk_contracttype'). Status: $(Label $t 'spk_status'). Priority: $((Label $t 'spk_priority') ?? 'not set'). " +
            "Category: $((Label $t 'spk_category') ?? 'not set'). Product: $(Label $t 'spk_product') $($t.spk_productversion). " +
            "Affected users: $($t.spk_affectedusers). Opened on: $(When $t.spk_openedon). Resolved on: $(When $t.spk_resolvedon). " +
            "Assigned technician: $($t.spk_AssignedTechnicianId.spk_name). Related article: $($t.spk_RelatedArticleId.spk_articlenumber). " +
            "Description: $($t.spk_description) Resolution: $($t.spk_resolutionsummary) $escalation $sla"
        $docs.Add(@{ id = "ticket-$($t.spk_ticketnumber)"; docType = 'Ticket'; title = "$($t.spk_ticketnumber): $($t.spk_name)"
            url = (RecordUrl 'spk_ticket' $t.spk_ticketid); sourceId = $t.spk_ticketnumber; content = $content
            customer = $cust.name; customerCode = $cust.spk_customercode; slaTier = (Label $cust 'spk_slatier')
            contractType = (Label $cust 'spk_contracttype'); product = (Label $t 'spk_product'); productVersion = $t.spk_productversion
            category = (Label $t 'spk_category'); priority = (Label $t 'spk_priority'); status = (Label $t 'spk_status')
            relatedArticle = $t.spk_RelatedArticleId.spk_articlenumber; openedOn = $t.spk_openedon; resolvedOn = $t.spk_resolvedon
            slaTargetHours = $t.spk_slatargethours; slaElapsedHours = $t.spk_slaelapsedhours; slaRemainingHours = $t.spk_slaremaininghours
            slaDueOn = $t.spk_sladueon; slaStatus = (Label $t 'spk_slastatus'); slaCalculatedOn = $t.spk_slacalculatedon })
    }

    $ranked = @($openTickets | Where-Object { $null -ne $_.spk_slaremaininghours } | Sort-Object { [double]$_.spk_slaremaininghours })
    $untriaged = @($openTickets | Where-Object { $null -eq $_.spk_slaremaininghours })
    $rank = 0
    $lines = foreach ($t in $ranked) {
        $rank++
        "$rank. $($t.spk_ticketnumber) ($($t.spk_CustomerId.name), $($t.spk_CustomerId.spk_customercode), SLA tier $(Label $t.spk_CustomerId 'spk_slatier')): " +
        "$(Label $t 'spk_priority'), target $($t.spk_slatargethours), elapsed $($t.spk_slaelapsedhours), remaining $($t.spk_slaremaininghours) business hours, " +
        "due $(When $t.spk_sladueon), SLA status $(Label $t 'spk_slastatus'). '$($t.spk_name)'."
    }
    $untriagedText = if ($untriaged.Count) {
        ($untriaged | ForEach-Object { "$($_.spk_ticketnumber) ($($_.spk_CustomerId.name)) '$($_.spk_name)'" }) -join '; '
    } else { 'none' }
    $targets = ($policies | Group-Object spk_slatier | Sort-Object { [long]$_.Name } | ForEach-Object {
        "$(Label $_.Group[0] 'spk_slatier'): " + (($_.Group | Sort-Object spk_priority |
            ForEach-Object { "$(Label $_ 'spk_priority') $($_.spk_resolutionhours)" }) -join ', ')
    }) -join '; '
    $rules = $policies | ForEach-Object { "$($_.spk_description)" } | Where-Object { $_ -match 'Relecloud priority rules:' } | Select-Object -First 1
    $rules = if ($rules) { $rules.Substring($rules.IndexOf('Relecloud priority rules:')) } else { '' }
    $snapshotContent = "SLA risk snapshot of every open ticket, as of $(When $snapshotTime). SLA figures are business hours " +
        "(Monday to Friday, 08:00 to 18:00 UTC, no holidays); elapsed plus remaining equals the target. " +
        "Negative remaining hours mean the SLA is already breached. Ordered by remaining business hours, lowest first: " +
        ($lines -join ' ') + " Open tickets not yet triaged, so they have no priority and no SLA: $untriagedText. " +
        "SLA resolution targets in business hours by SLA tier and priority: $targets. $rules"
    $docs.Add(@{ id = 'sla-snapshot'; docType = 'SLA snapshot'; title = 'SLA risk snapshot: open tickets by remaining business hours, SLA targets and priority rules'
        url = $slaViewUrl; sourceId = 'SLA-SNAPSHOT'; content = $snapshotContent; slaCalculatedOn = $snapshotTime })

    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    $docs | ConvertTo-Json -Depth 6 | Set-Content -Path $documentsFile -Encoding utf8
    $manifest = [ordered]@{
        exported_on = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); source = $dv
        knowledge_articles = $articles.Count; runbooks = $runbooks.Count; tickets = $tickets.Count; customers = $customers.Count
        sla_snapshot = 1; total = $docs.Count; not_indexed = @('ticket notes', 'contact details', 'customer documents') + @($newIncidents)
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestFile -Encoding utf8
    Write-Host "Exported $($docs.Count) documents to $ExportPath." -ForegroundColor Green
    return [pscustomobject]@{ Documents = $docs.Count; Path = $ExportPath }
}

if ($Export) { return Export-Documents }

# ================================================================== load the export into the index
if (-not (Test-Path $documentsFile)) { throw "The export $documentsFile is missing. Contact support: lab provisioning creates it." }
$docs = @(Get-Content $documentsFile -Raw | ConvertFrom-Json -AsHashtable)
$manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
$search = $settings.SearchEndpoint.TrimEnd('/')
if (-not $OpenAIEndpoint) { $OpenAIEndpoint = "https://$($settings.FoundryResource).openai.azure.com" }
$embeddingUri = "$($OpenAIEndpoint.TrimEnd('/'))/openai/deployments/$($settings.EmbeddingDeployment)/embeddings?api-version=2024-10-21"

function Invoke-Embedding([string[]]$inputs) {
    # The team's embedding deployment allows about 30,000 tokens a minute, so a full load is
    # rate limited for a while. Honor Retry-After instead of failing.
    $body = @{ input = @($inputs) } | ConvertTo-Json -Depth 5
    for ($attempt = 1; $attempt -le 15; $attempt++) {
        try {
            return Invoke-RestMethod -Method Post -Uri $embeddingUri -Body $body -ContentType 'application/json' `
                -Headers @{ Authorization = "Bearer $(Token 'https://cognitiveservices.azure.com')" }
        }
        catch {
            $status = [int]($_.Exception.Response.StatusCode)
            if ($status -ne 429 -and $status -lt 500) { throw }
            $wait = 10
            $retryAfter = $_.Exception.Response.Headers.RetryAfter
            if ($retryAfter -and $retryAfter.Delta) { $wait = [int][Math]::Ceiling($retryAfter.Delta.TotalSeconds) }
            $wait = [Math]::Min([Math]::Max($wait, 2), 60)
            Write-Host "  The embedding deployment is rate limiting; waiting $wait seconds (attempt $attempt)." -ForegroundColor DarkYellow
            Start-Sleep -Seconds $wait
        }
    }
    throw 'The embedding deployment kept refusing requests. Wait a minute and run the script again.'
}

$searchHeaders = @{ Authorization = "Bearer $(Token 'https://search.azure.com')" }
try { Invoke-RestMethod -Uri "$search/indexes/$($IndexName)?api-version=2024-07-01" -Headers $searchHeaders | Out-Null }
catch { throw "Index '$IndexName' was not found on $search. Create it first (Exercise 1, Task 2)." }

Write-Host "Embedding $($docs.Count) documents with $($settings.EmbeddingDeployment)..." -ForegroundColor Cyan
for ($i = 0; $i -lt $docs.Count; $i += $EmbeddingBatch) {
    $batch = $docs[$i..([Math]::Min($i + $EmbeddingBatch - 1, $docs.Count - 1))]
    $result = Invoke-Embedding @($batch | ForEach-Object { $_.content })
    for ($j = 0; $j -lt $batch.Count; $j++) { $batch[$j].contentVector = $result.data[$j].embedding }
    Write-Progress -Activity 'Embedding' -PercentComplete ([int](100 * ($i + $batch.Count) / $docs.Count))
}
Write-Progress -Activity 'Embedding' -Completed

Write-Host "Uploading to index '$IndexName'..." -ForegroundColor Cyan
for ($i = 0; $i -lt $docs.Count; $i += 100) {
    $batch = $docs[$i..([Math]::Min($i + 99, $docs.Count - 1))]
    $payload = @{ value = @($batch | ForEach-Object {
        $d = @{ '@search.action' = 'mergeOrUpload' }
        foreach ($k in $_.Keys) { if ($null -ne $_[$k] -and $_[$k] -ne '') { $d[$k] = $_[$k] } }
        $d }) } | ConvertTo-Json -Depth 6 -Compress
    Invoke-RestMethod -Method Post -Uri "$search/indexes/$IndexName/docs/index?api-version=2024-07-01" -Headers $searchHeaders `
        -Body $payload -ContentType 'application/json' | Out-Null
}

$expected = [int]$manifest.total
$deadline = (Get-Date).AddMinutes(2)
do {
    Start-Sleep -Seconds 5
    $raw = Invoke-RestMethod -Uri "$search/indexes/$IndexName/docs/`$count?api-version=2024-07-01" -Headers $searchHeaders
    $count = [int]("$raw".Trim([char]0xFEFF).Trim())
} until ($count -ge $expected -or (Get-Date) -gt $deadline)

[pscustomobject]@{ Source = 'Knowledge articles'; Count = $manifest.knowledge_articles },
[pscustomobject]@{ Source = 'Runbooks'; Count = $manifest.runbooks },
[pscustomobject]@{ Source = 'Tickets'; Count = $manifest.tickets },
[pscustomobject]@{ Source = 'Customers'; Count = $manifest.customers },
[pscustomobject]@{ Source = 'SLA snapshot'; Count = 1 },
[pscustomobject]@{ Source = 'Expected index documents'; Count = $expected },
[pscustomobject]@{ Source = "Index '$IndexName' documents"; Count = $count } | Format-Table -AutoSize
if ($count -eq $expected) { Write-Host 'Document count matches the seeded data.' -ForegroundColor Green }
else { Write-Warning "Index holds $count documents; expected $expected. Run the script again." }
