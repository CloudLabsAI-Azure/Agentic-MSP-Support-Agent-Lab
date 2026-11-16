#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the servicedesk-knowledge search index from the Service Desk export (Exercise 1, Task 2).

.DESCRIPTION
    Lab provisioning exported the Service Desk content (knowledge articles, customer documents,
    runbooks, tickets, customer profiles and one SLA snapshot) from Dataverse to the storage
    container servicedesk-export, one JSON file per record. This script turns that export into the
    index your agent grounds its answers on. It creates four objects on your Azure AI Search service
    and runs them:

      Index        servicedesk-knowledge, from C:\LabFiles\search\index-definition.json, the field
                   list you review first. Before it creates anything, the script checks that the
                   citation fields title, url and sourceId are retrievable and that content is
                   searchable, because the agent can only cite what the index returns.
      Data source  servicedesk-export-ds: the export container, read with the search service's own
                   managed identity. No key is stored anywhere.
      Skillset     servicedesk-embed-skills: one embedding of each document's content with
                   text-embedding-3-small on your Foundry resource. No chunking, so one record is
                   one search result and one citation.
      Indexer      servicedesk-export-indexer: reads each JSON file (parsing mode json), maps its id
                   to the key, embeds the content and writes the document. It runs on demand only.

    The script then waits for the indexer, shows its progress, and compares the index document count
    with the export manifest (C:\LabFiles\search\export-manifest.json). It also proves that the two
    new incidents are not in the index and that every document carries a vector.

    It uses your own Azure CLI sign-in. Run 'az login' first and sign in as the Senior Technician,
    who holds Search Service Contributor (create and run the objects) and Search Index Data Reader
    (count and query) on the search service.

    Safe to run again: a second run updates the four objects in place, resets the indexer and runs
    it again, so every document is processed once more. If an indexer run is already in progress,
    the script waits for it instead of starting another one.

.PARAMETER ReviewOnly
    Shows the field list with what each field is for, checks it, and stops. Creates nothing and needs
    no sign-in.

.PARAMETER RecreateIndex
    Deletes the index before creating it again. Use it only when the script tells you to: Azure AI
    Search can't change whether an existing field is searchable, filterable, sortable or facetable.

.PARAMETER TimeoutMinutes
    How long to wait for the indexer run. Default 30.

.EXAMPLE
    C:\LabFiles\tools\New-KnowledgeIndex.ps1 -ReviewOnly

.EXAMPLE
    C:\LabFiles\tools\New-KnowledgeIndex.ps1
#>
[CmdletBinding()]
param(
    [switch]$ReviewOnly,
    [switch]$RecreateIndex,
    [ValidateRange(5, 180)][int]$TimeoutMinutes = 30,
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$SearchFolder = 'C:\LabFiles\search',
    [string]$ExportManifestPath,
    # Pilot overrides; leave them empty in the lab.
    [string]$EmbeddingResourceUri,
    [string]$ApiVersion = '2026-04-01'
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

# ==== Output helpers
function Write-Section([string]$Text) { Write-Host ''; Write-Host "==== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "  $Text" }
function Write-Caution([string]$Text) { Write-Host "  [check] $Text" -ForegroundColor Yellow }
function Write-Problem([string]$Text) { Write-Host "  [problem] $Text" -ForegroundColor Red; $script:Failed = $true }
function Stop-Script([string]$Text) {
    Write-Host ''
    Write-Host "Stopped: $Text" -ForegroundColor Red
    exit 1
}

# ==== Settings and files
function Read-LabSettings([string]$Path, [string[]]$Required) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "The lab settings file $Path was not found. Lab provisioning writes it; contact CloudLabs support if it is missing."
    }
    try { $s = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "The lab settings file $Path is not valid JSON ($($_.Exception.Message)). Contact CloudLabs support." }
    $missing = @($Required | Where-Object { -not $s.PSObject.Properties[$_] -or [string]::IsNullOrWhiteSpace([string]$s.$_) })
    if ($missing.Count) { throw "The lab settings file $Path has no value for: $($missing -join ', '). Contact CloudLabs support." }
    return $s
}

function Read-JsonFile([string]$Path, [string]$What, [hashtable]$Tokens) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "$What was not found at $Path. It is part of the lab files; contact CloudLabs support." }
    $text = Get-Content -LiteralPath $Path -Raw
    if ($Tokens) {
        foreach ($key in $Tokens.Keys) { $text = $text.Replace("{{$key}}", [string]$Tokens[$key]) }
        $left = [regex]::Matches($text, '\{\{([A-Za-z]+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
        if ($left) { throw "$What ($Path) still holds placeholders the script can't fill: $($left -join ', ')." }
    }
    try { return ($text | ConvertFrom-Json) }
    catch { throw "$What ($Path) is not valid JSON: $($_.Exception.Message). If you edited it, check the commas and quotes around your change." }
}

function ConvertTo-Utc($Value) {
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Local) { return $Value.ToUniversalTime() }
        return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)
    }
    return ([datetimeoffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
}

function Get-NumberMap($Object) {
    # Turns {"Knowledge article": 120, ...} into a hashtable keyed by a normalized name.
    $map = @{}
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { return $map }
    foreach ($p in $Object.PSObject.Properties) {
        $n = 0
        if ([int]::TryParse([string]$p.Value, [ref]$n)) { $map[(Get-TypeKey $p.Name)] = $n }
    }
    return $map
}

function Get-TypeKey([string]$Name) {
    # 'Knowledge article', 'knowledge_articles' and 'KnowledgeArticles' all become 'knowledgearticle'.
    $k = ($Name.ToLowerInvariant() -replace '[^a-z]', '')
    if ($k.EndsWith('s') -and $k -ne 'status') { $k = $k.Substring(0, $k.Length - 1) }
    return $k
}

# ==== The field review
$FieldPurpose = [ordered]@{
    id              = 'Key: one search document per exported record, for example kb-KB0058. The indexer maps the file''s id to it.'
    docType         = 'Knowledge article, Customer document, Runbook, Ticket, Customer or SLA snapshot. Used to count and filter by type.'
    title           = 'Citation title the agent shows, and the semantic title field.'
    url             = 'Citation link that opens the record in the Service Desk app. Retrievable, nothing else.'
    sourceId        = 'The record''s own number (KB number, document code, runbook code, ticket number, customer code), so answers can name it.'
    content         = 'The text the agent reads and the embedding input. Searchable and retrievable, never filterable or sortable (long text).'
    customer        = 'Customer name, searchable for questions that name a customer.'
    customerCode    = 'Customer context that separates similar records (filter).'
    slaTier         = 'Platinum, Gold, Silver or Bronze: decides between tier-specific articles (filter).'
    contractType    = 'Fully Managed, Co-Managed or Break-Fix: decides between contract-specific articles (filter).'
    product         = 'Product the record is about (filter and search).'
    productVersion  = 'Version the record applies to: decides between version-specific articles.'
    category        = 'Triage category (filter and search).'
    subcategory     = 'Triage subcategory (filter and search).'
    articleStatus   = 'Published, Draft or Retired: the agent must never recommend a Retired article (filter).'
    relatedArticles = 'KB numbers of related articles, searchable.'
    tags            = 'Keywords, searchable.'
    priority        = 'Ticket priority (filter).'
    status          = 'Ticket status (filter).'
    outcome         = 'How a closed ticket ended (filter).'
    openedOn        = 'Opened time, ISO 8601 UTC text (filter and sort).'
    resolvedOn      = 'Resolved time, ISO 8601 UTC text (filter and sort).'
    contentVector   = 'Embedding of content (1536 numbers) for vector and hybrid queries. Not retrievable: the agent never needs the numbers.'
}
$ShouldFilter = 'docType', 'customerCode', 'slaTier', 'contractType', 'product', 'category', 'articleStatus'

function Get-FieldFlag($Field, [string]$Flag) {
    $p = $Field.PSObject.Properties[$Flag]
    if ($p -and $null -ne $p.Value) { return [bool]$p.Value }
    # Azure AI Search defaults when an attribute is left out: string fields are searchable,
    # filterable, sortable, facetable and retrievable; vector fields are searchable only.
    if ($Flag -eq 'key') { return $false }
    if ($Field.type -eq 'Collection(Edm.Single)') { return ($Flag -eq 'searchable') }
    return $true
}

function Test-IndexDefinition($Definition, [string]$ExpectedName) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($Definition.name -ne $ExpectedName) {
        $errors.Add("The index must be named $ExpectedName (the agent's search tool and the lab validation look for that name); the file says '$($Definition.name)'.")
    }
    $fields = @($Definition.fields)
    $byName = @{}
    foreach ($f in $fields) { $byName[[string]$f.name] = $f }
    $keys = @($fields | Where-Object { Get-FieldFlag $_ 'key' })
    if ($keys.Count -ne 1 -or $keys[0].name -ne 'id') {
        $errors.Add("Exactly one field, id, must be the key. The file has: $(if ($keys.Count) { ($keys.name -join ', ') } else { 'no key field' }).")
    }
    elseif ($keys[0].type -ne 'Edm.String' -or -not (Get-FieldFlag $keys[0] 'retrievable')) {
        $errors.Add('The key field id must be an Edm.String and retrievable.')
    }
    foreach ($name in 'title', 'url', 'sourceId') {
        $f = $byName[$name]
        if (-not $f) { $errors.Add("Field $name is missing. The agent needs it to cite a source; put it back as an Edm.String with ""retrievable"": true."); continue }
        if ($f.type -ne 'Edm.String') { $errors.Add("Field $name must be of type Edm.String.") }
        if (-not (Get-FieldFlag $f 'retrievable')) {
            $why = switch ($name) { 'title' { 'shows the source''s title' } 'url' { 'links the citation to the Service Desk record' } default { 'names the record (KB number, ticket number)' } }
            $errors.Add("Field $name must be retrievable: it is the field that $why. Set ""retrievable"": true for $name.")
        }
    }
    $content = $byName['content']
    if (-not $content) { $errors.Add('Field content is missing: it holds the text the agent reads.') }
    else {
        if (-not (Get-FieldFlag $content 'searchable')) { $errors.Add('Field content must be searchable, or no question will match it. Set "searchable": true for content.') }
        if (-not (Get-FieldFlag $content 'retrievable')) { $errors.Add('Field content must be retrievable, so the agent receives the text it cites. Set "retrievable": true for content.') }
        foreach ($flag in 'filterable', 'sortable', 'facetable') {
            if (Get-FieldFlag $content $flag) { $errors.Add("Field content must not be $flag (filterable, sortable and facetable text is limited to 32 KB, so long documents would fail). Set ""$flag"": false for content.") }
        }
    }
    $vector = $byName['contentVector']
    if (-not $vector) { $errors.Add('Field contentVector is missing: the embedding skill writes the vector there.') }
    else {
        if ($vector.type -ne 'Collection(Edm.Single)') { $errors.Add('Field contentVector must be of type Collection(Edm.Single).') }
        if ([int]$vector.dimensions -ne 1536) { $errors.Add('Field contentVector must have 1536 dimensions, the size of a text-embedding-3-small vector.') }
        $vectorProfile = @($Definition.vectorSearch.profiles) | Where-Object { $_.name -eq $vector.vectorSearchProfile } | Select-Object -First 1
        if (-not $vectorProfile) { $errors.Add("contentVector names the vector profile '$($vector.vectorSearchProfile)', which vectorSearch.profiles doesn't define.") }
        else {
            if (-not (@($Definition.vectorSearch.algorithms) | Where-Object { $_.name -eq $vectorProfile.algorithm })) {
                $errors.Add("Vector profile $($vectorProfile.name) uses the algorithm '$($vectorProfile.algorithm)', which vectorSearch.algorithms doesn't define.")
            }
            $vectorizer = @($Definition.vectorSearch.vectorizers) | Where-Object { $_.name -eq $vectorProfile.vectorizer } | Select-Object -First 1
            if (-not $vectorizer) { $errors.Add("Vector profile $($vectorProfile.name) needs a vectorizer, so questions can be turned into vectors at query time.") }
            elseif ($vectorizer.kind -ne 'azureOpenAI' -or $vectorizer.azureOpenAIParameters.modelName -ne 'text-embedding-3-small') {
                $errors.Add('The vectorizer must use kind azureOpenAI with modelName text-embedding-3-small, the same model the skillset uses for the documents.')
            }
        }
    }
    $semantic = @($Definition.semantic.configurations) | Select-Object -First 1
    if (-not $semantic) { $errors.Add('The semantic configuration is missing. It ranks results by meaning, with title and content.') }
    else {
        if ($semantic.prioritizedFields.titleField.fieldName -ne 'title') { $errors.Add('The semantic configuration must use title as its title field.') }
        if (@($semantic.prioritizedFields.prioritizedContentFields.fieldName) -notcontains 'content') { $errors.Add('The semantic configuration must list content as a content field.') }
    }
    $docType = $byName['docType']
    if (-not $docType) { $warnings.Add('Field docType is missing, so the per-type count is skipped.') }
    else {
        if (-not (Get-FieldFlag $docType 'retrievable')) { $warnings.Add('docType is not retrievable, so the agent can''t tell a ticket from an article in a result.') }
        if (-not (Get-FieldFlag $docType 'facetable')) { $warnings.Add('docType is not facetable, so the per-type count is skipped.') }
    }
    foreach ($name in $ShouldFilter) {
        $f = $byName[$name]
        if ($f -and -not (Get-FieldFlag $f 'filterable')) { $warnings.Add("$name is not filterable; filters such as ""$name eq '...'"" won't work.") }
        elseif (-not $f) { $warnings.Add("Field $name is missing; the exported value is ignored.") }
    }
    return [pscustomobject]@{ Errors = $errors; Warnings = $warnings; Fields = $fields }
}

function Show-FieldReview($Review) {
    $rows = foreach ($f in $Review.Fields) {
        [pscustomobject]@{
            Field       = $f.name
            Type        = ($f.type -replace '^Edm\.', '' -replace '^Collection\(Edm\.Single\)$', 'Vector')
            Key         = if (Get-FieldFlag $f 'key') { 'key' } else { '' }
            Retrievable = if (Get-FieldFlag $f 'retrievable') { 'yes' } else { '' }
            Searchable  = if (Get-FieldFlag $f 'searchable') { 'yes' } else { '' }
            Filterable  = if (Get-FieldFlag $f 'filterable') { 'yes' } else { '' }
            Purpose     = if ($FieldPurpose.Contains([string]$f.name)) { $FieldPurpose[[string]$f.name] } else { '(a field you added)' }
        }
    }
    $rows | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host
}

# ==== Azure CLI and the search REST API
function Get-AzCliToken([string]$Resource, [string]$TenantId) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found on this machine. Use the lab VM, where it is installed.' }
    $cliArgs = @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv')
    if ($TenantId) { $cliArgs += @('--tenant', $TenantId) }
    $token = & az @cliArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$token")) {
        throw "Azure CLI has no sign-in for your lab tenant. Run 'az login', sign in as the Senior Technician, and run this script again."
    }
    return ("$token").Trim()
}

function Invoke-Search {
    param([string]$Method, [string]$Path, $Body, [switch]$AllowNotFound)
    $uri = "$($script:SearchEndpoint)/$Path"
    $uri += if ($uri.Contains('?')) { "&api-version=$ApiVersion" } else { "?api-version=$ApiVersion" }
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $params = @{ Method = $Method; Uri = $uri; Headers = @{ Authorization = "Bearer $($script:SearchToken)" }
                     SkipHttpErrorCheck = $true; StatusCodeVariable = 'httpStatus'; ResponseHeadersVariable = 'httpHeaders'; TimeoutSec = 120 }
        if ($null -ne $Body) {
            $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 50 }
            $params.ContentType = 'application/json; charset=utf-8'
        }
        try { $result = Invoke-RestMethod @params }
        catch {
            if ($attempt -lt 4) { Start-Sleep -Seconds (5 * $attempt); continue }
            throw "The search service $($script:SearchEndpoint) could not be reached: $($_.Exception.Message)"
        }
        $code = [int]$httpStatus
        if ($code -in 429, 502, 503, 504 -and $attempt -lt 4) {
            $wait = 10 * $attempt
            $retryAfter = "$($httpHeaders['Retry-After'])"
            if ($retryAfter -match '^\d+$') { $wait = [Math]::Min([int]$retryAfter, 60) }
            Write-Note "The search service is busy (HTTP $code); trying again in $wait seconds."
            Start-Sleep -Seconds $wait
            continue
        }
        if ($code -eq 404 -and $AllowNotFound) { return [pscustomobject]@{ Status = 404; Body = $null } }
        if ($code -ge 400) {
            $detail = if ($result.error.message) { $result.error.message } elseif ($result) { ($result | Out-String).Trim() } else { '' }
            throw (New-SearchError -Code $code -Method $Method -Path $Path -Detail $detail)
        }
        return [pscustomobject]@{ Status = $code; Body = $result }
    }
}

function New-SearchError([int]$Code, [string]$Method, [string]$Path, [string]$Detail) {
    $what = "$Method $($Path.Split('?')[0])"
    switch ($Code) {
        401 { return "The search service did not accept your sign-in ($what, HTTP 401). Run 'az login' as the Senior Technician and run the script again." }
        403 {
            return "Your account may not do this on $($script:SearchServiceName) ($what, HTTP 403). You need Search Service Contributor (create and run objects) and " +
                   'Search Index Data Reader (count and query) on the search service; lab provisioning assigns both. A new role assignment can take 5 to 10 minutes to apply. ' +
                   'Wait a few minutes and run the script again; if it still fails, contact CloudLabs support.'
        }
        default {
            if ($Detail -match '(?i)semantic') {
                return "The search service refused the semantic configuration ($what, HTTP $Code): $Detail The service's semantic ranker plan may be off; contact CloudLabs support."
            }
            if ($Path -like 'indexes/*' -and $Method -eq 'PUT' -and $Detail -match '(?i)cannot be changed|existing field|can''t be changed|not allowed to update|cannot update') {
                return "Azure AI Search can't change these attributes on the existing index ($Detail). Run the script again with -RecreateIndex: it deletes the index and builds it again from your definition, and the indexer reloads every document."
            }
            return "The search service refused $what (HTTP $Code): $Detail"
        }
    }
}

function Get-IndexerRunHint([string]$Message) {
    if ($Message -match '(?i)AuthorizationPermissionMismatch|AuthorizationFailure|not authorized to perform|403.*blob|blob.*403|storage.*(denied|forbidden)') {
        return 'The search service''s managed identity could not read the export container. It needs Storage Blob Data Reader on the storage account, which provisioning assigns; managed identity role changes can take a while to apply. Contact CloudLabs support with this message.'
    }
    if ($Message -match '(?i)ContainerNotFound|container .* does not exist|The specified container does not exist') {
        return 'The export container is missing or empty. Lab provisioning creates it; contact CloudLabs support.'
    }
    if ($Message -match '(?i)429|rate limit|too many requests|throttl') {
        return 'The embedding deployment was rate limited. Wait 5 minutes, then run this script again; it resets and reruns the indexer.'
    }
    if ($Message -match '(?i)(401|403|Unauthorized|Forbidden|PermissionDenied).*(skill|embedding|openai|Web ?Api)|(skill|embedding|openai|Web ?Api).*(401|403|Unauthorized|Forbidden|PermissionDenied)') {
        return 'The search service''s managed identity could not call the embedding model. It needs Cognitive Services OpenAI User on the Foundry resource, which provisioning assigns. Contact CloudLabs support with this message.'
    }
    if ($Message -match '(?i)DeploymentNotFound|deployment .* not found|does not exist.*deployment') {
        return 'The embedding deployment named in lab-settings.json was not found on the Foundry resource. Contact CloudLabs support.'
    }
    if ($Message -match '(?i)parse|invalid json|could not read|malformed') {
        return 'An exported file could not be read as JSON. The export is created by provisioning; contact CloudLabs support with the document key above.'
    }
    return 'Read the message above. If it doesn''t point to something you changed, contact CloudLabs support with it.'
}

function Get-EmbeddingUri($Settings) {
    if ($EmbeddingResourceUri) { return $EmbeddingResourceUri.TrimEnd('/') }
    $sub = ''
    try { $sub = ([uri]$Settings.FoundryProjectEndpoint).Host.Split('.')[0] } catch { $sub = '' }
    if (-not $sub) { $sub = [string]$Settings.FoundryResource }
    return "https://$sub.openai.azure.com"
}

function Read-ExportManifest([string]$Path, $Settings) {
    if (Test-Path -LiteralPath $Path) {
        try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) }
        catch { Write-Caution "The export manifest $Path is not valid JSON: $($_.Exception.Message)" }
    }
    # Fallback: the copy in the storage account (you hold Storage Blob Data Reader on it).
    try {
        $token = Get-AzCliToken 'https://storage.azure.com/' $Settings.TenantId
        $uri = "https://$($Settings.StorageAccount).blob.core.windows.net/servicedesk-export-meta/export-manifest.json"
        $manifest = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token"; 'x-ms-version' = '2021-08-06' } -TimeoutSec 60
        if ($manifest -is [string]) { $manifest = $manifest | ConvertFrom-Json }
        Write-Note "Read the export manifest from the storage container servicedesk-export-meta (no local copy at $Path)."
        return $manifest
    }
    catch { return $null }
}

# ==== Main
try {
    Write-Host 'New-KnowledgeIndex: builds the servicedesk-knowledge index your agent grounds its answers on.' -ForegroundColor Cyan
    Write-Host 'It creates an index, a data source, a skillset and an indexer on your search service, runs the indexer,'
    Write-Host 'and checks the document count against the export. Nothing outside your search service changes.'

    $settings = Read-LabSettings $SettingsPath @('SubscriptionId', 'ResourceGroup', 'SearchService', 'SearchEndpoint', 'SearchIndex',
                                                 'StorageAccount', 'ExportContainer', 'FoundryProjectEndpoint', 'EmbeddingDeployment')
    $script:SearchEndpoint = ([string]$settings.SearchEndpoint).TrimEnd('/')
    $script:SearchServiceName = [string]$settings.SearchService
    if (-not $ExportManifestPath) { $ExportManifestPath = Join-Path $SearchFolder 'export-manifest.json' }

    $tokens = @{
        SubscriptionId       = $settings.SubscriptionId
        ResourceGroup        = $settings.ResourceGroup
        StorageAccount       = $settings.StorageAccount
        ExportContainer      = $settings.ExportContainer
        EmbeddingResourceUri = (Get-EmbeddingUri $settings)
        EmbeddingDeployment  = $settings.EmbeddingDeployment
        SearchIndex          = $settings.SearchIndex
    }
    foreach ($key in @($tokens.Keys)) {
        if ([string]$tokens[$key] -notmatch '^[A-Za-z0-9\-._:/()]+$') { throw "The lab setting behind $key has an unexpected value ('$($tokens[$key])'). Contact CloudLabs support." }
    }

    $index = Read-JsonFile (Join-Path $SearchFolder 'index-definition.json') 'The index definition' $tokens
    $dataSource = Read-JsonFile (Join-Path $SearchFolder 'servicedesk-export-ds.json') 'The data source definition' $tokens
    $skillset = Read-JsonFile (Join-Path $SearchFolder 'servicedesk-embed-skills.json') 'The skillset definition' $tokens
    $indexer = Read-JsonFile (Join-Path $SearchFolder 'servicedesk-export-indexer.json') 'The indexer definition' $tokens

    # ==== 1. Review the field list
    Write-Section "1. Review the field list in $(Join-Path $SearchFolder 'index-definition.json')"
    $review = Test-IndexDefinition $index ([string]$settings.SearchIndex)
    Show-FieldReview $review
    Write-Note 'The vectorizer''s resourceUri and deploymentId are filled in from lab-settings.json when the index is created.'
    $samples = Join-Path $SearchFolder 'sample-documents'
    if (Test-Path -LiteralPath $samples) {
        $exported = @(Get-ChildItem -LiteralPath $samples -Filter '*.json' -File | ForEach-Object {
            try { (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).PSObject.Properties.Name } catch { @() }
        } | Select-Object -Unique)
        $notIndexed = @($exported | Where-Object { $_ -notin @($review.Fields.name) })
        if ($notIndexed.Count) { Write-Caution "Exported fields with no index field (the indexer ignores them): $($notIndexed -join ', ')." }
        elseif ($exported.Count) { Write-Ok "Every field in the sample documents ($samples) has an index field." }
    }
    foreach ($w in $review.Warnings) { Write-Caution $w }
    if ($review.Errors.Count) {
        foreach ($e in $review.Errors) { Write-Problem $e }
        Stop-Script "Fix the index definition (each problem above names the field and the attribute), save the file and run the script again. Nothing was created."
    }
    Write-Ok 'Citation fields: title, url and sourceId are retrievable; content is searchable and retrievable; id is the key.'
    if ($ReviewOnly) {
        Write-Host ''
        Write-Host 'Review only: nothing was created. Run the script without -ReviewOnly to build the index.' -ForegroundColor Green
        exit 0
    }

    # ==== 2. Sign-in and reachability
    Write-Section "2. Connect to $($settings.SearchService)"
    $script:SearchToken = Get-AzCliToken 'https://search.azure.com' $settings.TenantId
    $who = (& az account show --query user.name --output tsv 2>$null)
    if ($who) { Write-Note "Signed in as $who." }
    $null = Invoke-Search GET 'indexes?$select=name'
    Write-Ok "Your account can manage objects on $($settings.SearchService)."

    $exportManifest = Read-ExportManifest $ExportManifestPath $settings
    $expectedTotal = $null
    if ($exportManifest -and $null -ne $exportManifest.total) { $expectedTotal = [int]$exportManifest.total }
    $seedManifest = $null
    if ($settings.SeedManifest -and (Test-Path -LiteralPath $settings.SeedManifest)) {
        try { $seedManifest = Get-Content -LiteralPath $settings.SeedManifest -Raw | ConvertFrom-Json } catch { $seedManifest = $null }
    }
    $seedTotal = if ($seedManifest -and $null -ne $seedManifest.searchable_documents.total) { [int]$seedManifest.searchable_documents.total } else { $null }
    if ($null -eq $expectedTotal -and $null -ne $seedTotal) { $expectedTotal = $seedTotal }
    if ($null -eq $expectedTotal) { Write-Caution 'No export manifest was found, so the document count can''t be checked. Contact CloudLabs support after the run.' }
    else { Write-Note "The export holds $expectedTotal documents." }
    if ($null -ne $seedTotal -and $null -ne $expectedTotal -and $seedTotal -ne $expectedTotal) {
        Write-Problem "The export manifest says $expectedTotal documents but the seed manifest expects $seedTotal. The export is prepared by provisioning; contact CloudLabs support."
    }

    # ==== 3. Is a run already in progress?
    $indexerName = [string]$indexer.name
    $status = Invoke-Search GET "indexers/$indexerName/status" -AllowNotFound
    $indexerExists = ($status.Status -ne 404)
    $runRequestedAt = $null
    $alreadyRunning = $indexerExists -and $status.Body.lastResult -and $status.Body.lastResult.status -eq 'inProgress'
    if ($alreadyRunning) {
        Write-Section '3. An indexer run is already in progress'
        Write-Note "It started at $((ConvertTo-Utc $status.Body.lastResult.startTime).ToString('HH:mm:ss')) UTC. The script waits for it instead of starting another run (two overlapping runs would process documents twice)."
        $runRequestedAt = (ConvertTo-Utc $status.Body.lastResult.startTime)
    }
    else {
        # ==== 3. Create or update the four objects
        Write-Section '3. Create or update the search objects'
        if ($RecreateIndex) {
            $null = Invoke-Search DELETE "indexes/$($index.name)" -AllowNotFound
            Write-Note "Deleted the index $($index.name) so it can be created again (-RecreateIndex)."
        }
        $r = Invoke-Search PUT "indexes/$($index.name)" $index
        Write-Ok "Index $($index.name) $(if ($r.Status -eq 201) { 'created' } else { 'updated' }) with $(@($index.fields).Count) fields."
        $r = Invoke-Search PUT "datasources/$($dataSource.name)" $dataSource
        Write-Ok "Data source $($dataSource.name) $(if ($r.Status -eq 201) { 'created' } else { 'updated' }): container $($settings.ExportContainer) on $($settings.StorageAccount), managed identity."
        $r = Invoke-Search PUT "skillsets/$($skillset.name)" $skillset
        Write-Ok "Skillset $($skillset.name) $(if ($r.Status -eq 201) { 'created' } else { 'updated' }): text-embedding-3-small through $($tokens.EmbeddingResourceUri), deployment $($settings.EmbeddingDeployment)."
        $runRequestedAt = [datetime]::UtcNow
        $r = Invoke-Search PUT "indexers/$indexerName" $indexer
        if ($r.Status -eq 201 -or -not $indexerExists) {
            Write-Ok "Indexer $indexerName created. A new indexer starts its first run by itself."
        }
        else {
            Write-Ok "Indexer $indexerName updated."
            $null = Invoke-Search POST "indexers/$indexerName/reset"
            Write-Note 'Reset the indexer, so the next run processes every document again (a run without a reset skips unchanged files).'
            $runRequestedAt = [datetime]::UtcNow
            try {
                $null = Invoke-Search POST "indexers/$indexerName/run"
                Write-Ok 'Started a new indexer run.'
            }
            catch {
                if ($_.Exception.Message -match 'HTTP 409') { Write-Note 'A run was already starting; the script waits for it.' }
                else { throw }
            }
        }
    }

    # ==== 4. Wait for the run
    Write-Section '4. Wait for the indexer'
    Write-Note 'The indexer reads each file, calls the embedding model and writes the document. Runs are queued by the service, so the first minute can show no progress.'
    Write-Note "You can watch the same run in the Azure portal: $($settings.SearchService) > Search management > Indexers > $indexerName."
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $last = $null
    $seen = $false
    while ($true) {
        $st = (Invoke-Search GET "indexers/$indexerName/status").Body
        $last = $st.lastResult
        $started = $null
        if ($last -and $last.startTime) { $started = ConvertTo-Utc $last.startTime }
        if ($started -and $started -ge $runRequestedAt.AddSeconds(-60)) { $seen = $true }
        if ($seen -and $last.status -ne 'inProgress' -and $last.status -ne 'reset') { break }
        $processed = if ($seen -and $last.itemsProcessed) { [int]$last.itemsProcessed } else { 0 }
        $failedItems = if ($seen -and $last.itemsFailed) { [int]$last.itemsFailed } else { 0 }
        $label = if (-not $seen) { 'Waiting for the run to start' } else { "Processed $processed$(if ($expectedTotal) { " of $expectedTotal" }) documents, $failedItems failed" }
        $percent = if ($expectedTotal -and $processed) { [Math]::Min(99, [int](100 * $processed / $expectedTotal)) } else { 0 }
        Write-Progress -Activity "Indexer $indexerName" -Status $label -PercentComplete $percent
        if ((Get-Date) -gt $deadline) {
            Write-Progress -Activity "Indexer $indexerName" -Completed
            Stop-Script "The indexer is still running after $TimeoutMinutes minutes ($label). It keeps running in the service. Run this script again later: it waits for the run in progress and then checks the result."
        }
        Start-Sleep -Seconds 10
    }
    Write-Progress -Activity "Indexer $indexerName" -Completed
    $ended = ConvertTo-Utc $last.endTime
    $duration = if ($started -and $ended) { [int]($ended - $started).TotalSeconds } else { $null }
    if ($last.status -ne 'success') {
        Write-Problem "The indexer run ended with status $($last.status) after $($last.itemsProcessed) documents ($($last.itemsFailed) failed)."
        if ($last.errorMessage) { Write-Note "Message: $($last.errorMessage)" }
        $allMessages = @("$($last.errorMessage)")
        foreach ($e in @($last.errors) | Select-Object -First 3) {
            Write-Note "Document $($e.key): $($e.errorMessage)"
            $allMessages += "$($e.errorMessage)"
        }
        Stop-Script (Get-IndexerRunHint ($allMessages -join ' '))
    }
    Write-Ok "The run succeeded: $($last.itemsProcessed) documents processed, $($last.itemsFailed) failed$(if ($null -ne $duration) { ", in $duration seconds" })."
    $warningCount = @($last.warnings).Count
    if ($warningCount) {
        Write-Caution "The run reported $warningCount warning(s), for example: $(@($last.warnings)[0].message)"
    }

    # ==== 5. Check the result
    Write-Section '5. Check the index'
    $count = $null
    $countDeadline = (Get-Date).AddSeconds(90)
    do {
        $raw = (Invoke-Search GET "indexes/$($index.name)/docs/`$count").Body
        $count = [int](("$raw").Trim([char]0xFEFF).Trim())
        if ($null -eq $expectedTotal -or $count -eq $expectedTotal) { break }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $countDeadline)

    if ($null -eq $expectedTotal) { Write-Caution "The index holds $count documents. No export manifest was found to compare with." }
    elseif ($count -eq $expectedTotal) { Write-Ok "The index holds $count documents, the same as the export manifest ($expectedTotal)." }
    else {
        Write-Problem "The index holds $count documents, but the export manifest says $expectedTotal."
        Write-Note 'Wait two minutes and check the count in Search explorer. If it still differs, run this script again; if that doesn''t help, contact CloudLabs support.'
    }

    $docTypeField = @($index.fields) | Where-Object { $_.name -eq 'docType' } | Select-Object -First 1
    if ($docTypeField -and (Get-FieldFlag $docTypeField 'facetable')) {
        $facets = (Invoke-Search POST "indexes/$($index.name)/docs/search" @{ search = '*'; facets = @('docType,count:50'); top = 0; count = $true }).Body
        $expectedByType = @{}
        foreach ($candidate in 'counts', 'documents', 'by_type', 'byType', 'document_types', 'documentTypes') {
            if ($exportManifest -and $exportManifest.$candidate -is [pscustomobject]) { $expectedByType = Get-NumberMap $exportManifest.$candidate; if ($expectedByType.Count) { break } }
        }
        $rows = foreach ($f in @($facets.'@search.facets'.docType)) {
            $exp = $expectedByType[(Get-TypeKey ([string]$f.value))]
            [pscustomobject]@{
                'Document type' = $f.value
                'In the index'  = $f.count
                'In the export' = if ($null -ne $exp) { $exp } else { '' }
                'Match'         = if ($null -eq $exp) { '' } elseif ($exp -eq $f.count) { 'yes' } else { 'NO' }
            }
        }
        $rows | Format-Table -AutoSize | Out-String | Write-Host
        if (@($rows | Where-Object { $_.Match -eq 'NO' }).Count) { Write-Problem 'At least one document type differs from the export manifest (rows marked NO).' }
    }

    $newIncidents = @()
    if ($seedManifest -and $seedManifest.new_incidents) { $newIncidents = @($seedManifest.new_incidents | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^[A-Za-z0-9-]+$' }) }
    if ($newIncidents.Count) {
        $filter = ($newIncidents | ForEach-Object { "sourceId eq '$_'" }) -join ' or '
        $hits = (Invoke-Search POST "indexes/$($index.name)/docs/search" @{ search = '*'; filter = $filter; top = 0; count = $true }).Body.'@odata.count'
        if ([int]$hits -eq 0) { Write-Ok "The new incidents $($newIncidents -join ' and ') are not in the index, as intended: the agent can only find them through the Service Desk tools." }
        else { Write-Problem "The index holds $hits document(s) for the new incidents $($newIncidents -join ', '). They should never be exported; contact CloudLabs support." }
    }

    $mappingHint = 'Lab staff: check outputFieldMappings in C:\LabFiles\search\servicedesk-export-indexer.json (/document/contentVector, or /document/contentVector/* as the embedding skill page shows), then run this script again.'
    # Index statistics lag the indexer by a minute or more, so a fresh index can report a vector size of 0
    # even though every document has its vector. Poll for up to 90 seconds before reporting a problem.
    $stats = $null; $vectorBytes = $null
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $stats = (Invoke-Search GET "indexes/$($index.name)/stats").Body
        $vectorBytes = if ($stats -and $stats.PSObject.Properties['vectorIndexSize']) { [long]$stats.vectorIndexSize } else { $null }
        if ($count -le 0 -or $null -eq $vectorBytes -or $vectorBytes -gt 0) { break }
        if ($attempt -eq 1) { Write-Host '  Waiting for the index statistics to catch up with the indexer (up to 90 seconds)...' }
        Start-Sleep -Seconds 10
    }
    if ($count -gt 0 -and $null -ne $vectorBytes -and $vectorBytes -le 0) {
        Write-Problem 'The documents have no vectors (vector index size 0). The skillset ran but its output did not reach contentVector.'
        Write-Note $mappingHint
    }
    else {
        if ($null -ne $vectorBytes) { Write-Ok "Vectors stored: vector index size $([Math]::Round($vectorBytes / 1KB)) KB, storage $([Math]::Round([long]$stats.storageSize / 1KB)) KB." }
        try {
            $probe = (Invoke-Search POST "indexes/$($index.name)/docs/search" @{
                count = $true; top = 1; select = 'id,title,docType'
                vectorQueries = @(@{ kind = 'text'; text = 'backup job fails because the cloud vault storage quota is full'; fields = 'contentVector'; k = 1 }) }).Body
            $hit = @($probe.value) | Select-Object -First 1
            if ($hit) { Write-Ok "A vector query works: the closest document to a sample question is '$($hit.title)' ($($hit.docType))." }
            elseif ($count -gt 0) { Write-Problem 'A vector query returned nothing, so the documents probably have no vectors.'; Write-Note $mappingHint }
        }
        catch { Write-Caution "A vector query failed, so the vectorizer could not embed the question: $($_.Exception.Message)" }
    }

    # ==== 6. What you built and where to see it
    Write-Section '6. What you built'
    @(
        [pscustomobject]@{ Object = 'Index'; Name = $index.name; 'What it is' = 'The searchable copy of the export: fields, vectors and the semantic configuration'; 'Where to see it' = "Azure portal > $($settings.SearchService) > Search management > Indexes" }
        [pscustomobject]@{ Object = 'Data source'; Name = $dataSource.name; 'What it is' = "The export container $($settings.ExportContainer), read with the search service's managed identity"; 'Where to see it' = "Azure portal > $($settings.SearchService), with the index's other objects" }
        [pscustomobject]@{ Object = 'Skillset'; Name = $skillset.name; 'What it is' = 'The embedding step: content to one 1536-number vector, text-embedding-3-small'; 'Where to see it' = "Azure portal > $($settings.SearchService) > Search management" }
        [pscustomobject]@{ Object = 'Indexer'; Name = $indexerName; 'What it is' = 'The job that reads, embeds and writes; parsing mode json, run on demand'; 'Where to see it' = "Azure portal > $($settings.SearchService) > Search management > Indexers (execution history)" }
    ) | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host
    Write-Note "Try it in Search explorer (Azure portal > $($settings.SearchService) > Search explorer > View > JSON view):"
    Write-Note '  {"search": "*", "count": true}                                         counts every document'
    Write-Note '  {"search": "*", "filter": "docType eq ''Knowledge article''", "count": true}   counts one document type'
    Write-Host ''
    if ($script:Failed) {
        Write-Host 'The index was built, but at least one check above needs attention (marked [problem]).' -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Done. Next, add the index $($index.name) to your agent as the guide shows. If the portal path differs, run C:\LabFiles\tools\Update-AgentDefinition.ps1." -ForegroundColor Green
    exit 0
}
catch {
    Write-Verbose ($_ | Out-String)
    Stop-Script $_.Exception.Message
}
