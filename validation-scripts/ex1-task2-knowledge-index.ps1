# Validation: Exercise 1, Task 2: Connect the Agent to the Knowledge Base
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID mapped to $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the index servicedesk-knowledge exists on srch-msp-<DID>, its document count equals the
# seed manifest's searchable_documents.total, and the last run of the indexer servicedesk-export-indexer
# succeeded. The participant builds both in Task 2 with: C:\LabFiles\tools\New-KnowledgeIndex.ps1
#
# Expected document count, first found wins: the resource group tag lab-searchable-documents (written
# by provisioning from the seed manifest); $ExpectedDocuments below (set it from the seed manifest at
# release); the number of documents the indexer's last complete run read from the export.
#
# Permissions for the CloudLabs service principal (all read only):
#   Azure RBAC Reader on the participant's resource group (part of its subscription role)
#       Required. Finds srch-msp-<DID> and reads the resource group tags.
#   Azure AI Search, role-based access (the lab's setting): its subscription role reads the index
#       statistics and the indexer status (GET /indexes/{name}/stats, GET /indexers/{name}/status).
#       Search Index Data Reader on srch-msp-<DID> is needed only for the fallback count
#       (GET /indexes/{name}/docs/$count) when the statistics call is refused.
#   Microsoft.Search/searchServices/listAdminKeys/action (Contributor or Owner)
#       Optional. Used only when the service also accepts API keys and the role-based calls fail.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$ExpectedDocuments = 753        # Seed manifest searchable_documents.total (data version 3.0); 0 = not set.
$indexName = 'servicedesk-knowledge'
$indexerName = 'servicedesk-export-indexer'
$apiVersion = '2024-07-01'

function Get-SearchHeaders([string]$ResourceId) {
    # Role-based access first (Microsoft Entra token); an admin key only when the service accepts keys.
    $token = (Get-AzAccessToken -ResourceUrl 'https://search.azure.com').Token
    if ($token -is [System.Security.SecureString]) { $token = [System.Net.NetworkCredential]::new('', $token).Password }
    $headers = @(@{ Authorization = "Bearer $token" })
    try {
        $keys = (Invoke-AzRestMethod -Method POST -Path "$ResourceId/listAdminKeys?api-version=2023-11-01").Content | ConvertFrom-Json
        if ($keys.primaryKey) { $headers += @{ 'api-key' = $keys.primaryKey } }
    }
    catch { }
    return $headers
}

function Invoke-SearchGet([string]$Endpoint, [string]$Path, $HeaderSets) {
    $lastError = $null
    foreach ($h in $HeaderSets) {
        try { return Invoke-RestMethod -Method Get -Uri "$Endpoint/$Path" -Headers $h -TimeoutSec 60 }
        catch {
            $code = 0
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            if ($code -eq 404) { throw 'NOT_FOUND' }
            $lastError = "HTTP $code $($_.Exception.Message)"
        }
    }
    throw "ACCESS: $lastError"
}

function Get-LabFact([string]$ResourceGroupName, [string]$Tag) {
    try {
        $tags = (Get-AzResourceGroup -Name $ResourceGroupName).Tags
        if ($tags -and $tags[$Tag]) { return [string]$tags[$Tag] }
    }
    catch { }
    return ''
}

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $search = Get-AzResource -ResourceType 'Microsoft.Search/searchServices' -Name "srch-msp-$DeploymentID" | Select-Object -First 1
        if (-not $search) { throw "The search service srch-msp-$DeploymentID was not found in this subscription." }
        $endpoint = "https://$($search.Name).search.windows.net"
        $headerSets = Get-SearchHeaders $search.ResourceId

        $stats = $null
        try { $stats = Invoke-SearchGet $endpoint "indexes/$indexName/stats?api-version=$apiVersion" $headerSets }
        catch {
            if ("$($_.Exception.Message)" -eq 'NOT_FOUND') {
                $message = "The index $indexName does not exist on $($search.Name) yet. In Task 2, review C:\LabFiles\search\index-definition.json and run C:\LabFiles\tools\New-KnowledgeIndex.ps1."
                throw 'CHECKED'
            }
            # Statistics refused: count the documents instead (needs Search Index Data Reader).
            $raw = Invoke-SearchGet $endpoint "indexes/$indexName/docs/`$count?api-version=$apiVersion" $headerSets
            $stats = [pscustomobject]@{ documentCount = [int](("$raw").Trim([char]0xFEFF).Trim()) }
        }
        $count = [int]$stats.documentCount

        $indexerStatus = $null
        try { $indexerStatus = Invoke-SearchGet $endpoint "indexers/$indexerName/status?api-version=$apiVersion" $headerSets }
        catch {
            if ("$($_.Exception.Message)" -eq 'NOT_FOUND') {
                $message = "The index $indexName exists ($count documents) but the indexer $indexerName does not. Run C:\LabFiles\tools\New-KnowledgeIndex.ps1, which creates the data source, skillset and indexer and loads the export."
                throw 'CHECKED'
            }
            throw
        }
        $last = $indexerStatus.lastResult

        $expected = 0
        $source = ''
        $tag = Get-LabFact $search.ResourceGroupName 'lab-searchable-documents'
        if ($tag -match '^\d+$') { $expected = [int]$tag; $source = 'the seed manifest' }
        elseif ($ExpectedDocuments -gt 0) { $expected = $ExpectedDocuments; $source = 'the seed manifest' }
        else {
            $full = @($indexerStatus.executionHistory) | Where-Object { $_.status -eq 'success' -and [int]$_.itemsProcessed -gt 0 -and [int]$_.itemsFailed -eq 0 } | Select-Object -First 1
            if ($full) { $expected = [int]$full.itemsProcessed; $source = 'the documents the indexer read from the export' }
        }

        if (-not $last) {
            $message = "The indexer $indexerName has not run yet. Run C:\LabFiles\tools\New-KnowledgeIndex.ps1 again and wait for it to finish."
        }
        elseif ($last.status -eq 'inProgress') {
            $message = "The indexer $indexerName is still running ($($last.itemsProcessed) documents so far). Wait until New-KnowledgeIndex.ps1 reports the result, then validate again."
        }
        elseif ($last.status -ne 'success') {
            $message = "The last run of $indexerName ended with status $($last.status): $($last.errorMessage) Run C:\LabFiles\tools\New-KnowledgeIndex.ps1 again; it explains the error."
        }
        elseif ($expected -le 0) {
            $message = "The index holds $count documents, but the expected count is unknown (no lab-searchable-documents tag and no complete indexer run). Run C:\LabFiles\tools\New-KnowledgeIndex.ps1 again, then validate."
        }
        elseif ($count -ne $expected) {
            $message = "The index $indexName holds $count documents; $source says $expected. Run C:\LabFiles\tools\New-KnowledgeIndex.ps1 again (it resets and reruns the indexer), wait for it to finish, then validate."
        }
        else {
            $status = 'Succeeded'
            $message = "The index $indexName holds $count documents, the same as $source, and the last run of $indexerName succeeded."
            break
        }
    }
    catch {
        if ("$($_.Exception.Message)" -like 'ACCESS:*') {
            $message = "Validation could not read the search service srch-msp-$DeploymentID ($($_.Exception.Message.Substring(8))). Lab staff: see validation-scripts/README.md, What the validation service principal needs."
        }
        elseif ("$($_.Exception.Message)" -ne 'CHECKED') { $message = "Validation could not complete: $($_.Exception.Message)" }
    }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
