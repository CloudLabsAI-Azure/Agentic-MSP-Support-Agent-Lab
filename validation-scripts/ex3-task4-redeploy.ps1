# Validation: Exercise 3, Task 4: Redeploy Your Copy of the MCP Server
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID mapped to $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the Container App ca-mcp-<DID> runs a revision newer than the one provisioning created,
# from an mcp-server image whose tag is not the release tag, that revision is ready, and the server
# reports a version other than the release version. The participant builds and deploys it in Task 4
# with Deploy-McpServer.ps1 (for example tag 3.0.1).
#
# The version comes from GET https://<app>/health; when the app accepts traffic only from the gateway,
# from the server's startup log line for that revision (ContainerAppConsoleLogs, event "startup").
# The release tag and version come from the resource group tag lab-mcp-release, else $ReleaseVersion.
#
# Permissions for the CloudLabs service principal (all read only):
#   Azure RBAC Reader on the participant's resource group (part of its subscription role)
#       Required. Reads the Container App and its revisions, and the resource group tags.
#   Read access to the Log Analytics workspace log-msp-<DID> (part of its subscription role)
#       Optional. Reads the startup log line when /health can't be reached.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$ReleaseVersion = '3.0.0'       # The MCP server release that provisioning deploys (image tag and /health version).

function Get-LabFact([string]$ResourceGroupName, [string]$Tag) {
    try {
        $tags = (Get-AzResourceGroup -Name $ResourceGroupName).Tags
        if ($tags -and $tags[$Tag]) { return [string]$tags[$Tag] }
    }
    catch { }
    return ''
}

function Get-StartupVersion([string]$Revision) {
    $ws = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
    if (-not $ws) { return '' }
    $customerId = ((Invoke-AzRestMethod -Method GET -Path "$($ws.ResourceId)?api-version=2023-09-01").Content | ConvertFrom-Json).properties.customerId
    $query = "ContainerAppConsoleLogs | where TimeGenerated > ago(3d) | where ContainerAppName =~ 'ca-mcp-$DeploymentID' and RevisionName == '$Revision' | where Log contains 'startup' | project TimeGenerated, Log | order by TimeGenerated desc | take 20"
    $rows = @()
    if (Get-Command Invoke-AzOperationalInsightsQuery -ErrorAction SilentlyContinue) {
        $rows = @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query -Timespan (New-TimeSpan -Days 3)).Results)
    }
    else {
        $token = (Get-AzAccessToken -ResourceUrl 'https://api.loganalytics.io').Token
        if ($token -is [System.Security.SecureString]) { $token = [System.Net.NetworkCredential]::new('', $token).Password }
        $result = Invoke-RestMethod -Method Post -Uri "https://api.loganalytics.io/v1/workspaces/$customerId/query" -Headers @{ Authorization = "Bearer $token" } `
            -ContentType 'application/json' -Body (@{ query = $query; timespan = 'P3D' } | ConvertTo-Json)
        $rows = @($result.tables[0].rows | ForEach-Object { [pscustomobject]@{ TimeGenerated = $_[0]; Log = $_[1] } })
    }
    foreach ($row in $rows) {
        try { $entry = $row.Log | ConvertFrom-Json } catch { continue }
        if ($entry.event -eq 'startup' -and $entry.version) { return [string]$entry.version }
    }
    return ''
}

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $app = Get-AzResource -ResourceType 'Microsoft.App/containerApps' -Name "ca-mcp-$DeploymentID" | Select-Object -First 1
        if (-not $app) { throw "The Container App ca-mcp-$DeploymentID was not found in this subscription." }
        $release = Get-LabFact $app.ResourceGroupName 'lab-mcp-release'
        if (-not $release) { $release = $ReleaseVersion }
        $release = $release.TrimStart('v')

        $detail = (Invoke-AzRestMethod -Method GET -Path "$($app.ResourceId)?api-version=2024-03-01").Content | ConvertFrom-Json
        $image = [string]$detail.properties.template.containers[0].image
        $tag = if ($image -match ':([^:/]+)$') { $Matches[1] } else { '' }
        $latest = [string]$detail.properties.latestRevisionName
        $ready = [string]$detail.properties.latestReadyRevisionName
        $fqdn = [string]$detail.properties.configuration.ingress.fqdn
        $revisions = @(((Invoke-AzRestMethod -Method GET -Path "$($app.ResourceId)/revisions?api-version=2024-03-01").Content | ConvertFrom-Json).value)
        $first = $revisions | Sort-Object { [datetime]$_.properties.createdTime } | Select-Object -First 1

        if ($image -notmatch '/mcp-server:') {
            $message = "The Container App runs '$image', which is not an mcp-server image from your registry. Deploy your change with Deploy-McpServer.ps1 as Task 4 shows."
        }
        elseif ($tag.TrimStart('v') -eq $release) {
            $message = "The Container App still runs the release image (tag $tag). Change the server, then build and deploy it with a new tag (for example 3.0.1) as Task 4 shows."
        }
        elseif ($latest -ne $ready) {
            $message = "Revision $latest is not ready yet (the app still serves $ready). Wait a minute for it to start, then validate again."
        }
        elseif ($first -and $first.name -eq $ready) {
            $message = "The app still serves its first revision ($ready). Deploy your change as Task 4 shows, then validate again."
        }
        else {
            $version = ''
            $where = ''
            if ($fqdn) {
                try { $version = [string](Invoke-RestMethod -Uri "https://$fqdn/health" -TimeoutSec 15).version; $where = '/health' } catch { $version = '' }
            }
            if (-not $version) { $version = Get-StartupVersion $ready; $where = 'the startup log line' }
            if (-not $version) {
                $message = "Revision $ready runs $image, but its version could not be read yet (neither /health nor its startup log line). Startup logs take a few minutes to arrive; validate again shortly."
            }
            elseif ($version.TrimStart('v') -eq $release) {
                $message = "Revision $ready runs the image tag $tag, but the server still reports version $version. Change the version in the server source as Task 4 shows, then build and deploy again."
            }
            else {
                $status = 'Succeeded'
                $message = "Revision $ready runs $image and reports version $version (read from $where); provisioning deployed $release."
                break
            }
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
