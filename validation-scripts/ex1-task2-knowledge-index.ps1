# Validation: Exercise 1, Task 2 - Connect the agent to the knowledge base
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when:
#   1. index servicedesk-knowledge exists on srch-msp-<DID> and holds at least 561 documents
#      (50 knowledge articles + 12 runbooks + 474 tickets + 24 customers + 1 SLA snapshot), and
#   2. the Foundry project proj-msp-<DID> has an Azure AI Search (CognitiveSearch) connection
#      that targets that search service.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $expectedDocs = 561
        $search = Get-AzResource -ResourceType 'Microsoft.Search/searchServices' -Name "srch-msp-$DeploymentID" | Select-Object -First 1
        if (-not $search) { throw "Search service srch-msp-$DeploymentID was not found." }
        $keys = Invoke-AzRestMethod -Method POST -Path "$($search.ResourceId)/listAdminKeys?api-version=2023-11-01"
        $adminKey = ($keys.Content | ConvertFrom-Json).primaryKey
        $endpoint = "https://$($search.Name).search.windows.net"
        $count = $null
        try {
            $raw = Invoke-RestMethod -Uri "$endpoint/indexes/servicedesk-knowledge/docs/`$count?api-version=2024-07-01" -Headers @{ 'api-key' = $adminKey }
            $count = [int]("$raw".Trim([char]0xFEFF).Trim())
        }
        catch { $count = $null }
        $projectId = "/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/$($search.ResourceGroupName)" +
                     "/providers/Microsoft.CognitiveServices/accounts/aif-msp-$DeploymentID/projects/proj-msp-$DeploymentID"
        $connections = (Invoke-AzRestMethod -Method GET -Path "$projectId/connections?api-version=2025-06-01").Content | ConvertFrom-Json
        $searchConnection = $connections.value | Where-Object {
            $_.properties.category -eq 'CognitiveSearch' -and "$($_.properties.target)".TrimEnd('/') -eq $endpoint } | Select-Object -First 1
        if ($null -eq $count) {
            $message = "Index 'servicedesk-knowledge' was not found on $($search.Name). Create it with C:\LabFiles\search\index-definition.json."
        }
        elseif ($count -lt $expectedDocs) {
            $message = "Index 'servicedesk-knowledge' holds $count documents; expected $expectedDocs. Run C:\LabFiles\search\Load-SearchIndex.ps1 again."
        }
        elseif (-not $searchConnection) {
            $message = "The index is loaded ($count documents), but project proj-msp-$DeploymentID has no Azure AI Search connection to $endpoint."
        }
        else {
            $status = 'Succeeded'
            $message = "Index 'servicedesk-knowledge' holds $count documents and the project connection '$($searchConnection.name)' targets it."
            break
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
