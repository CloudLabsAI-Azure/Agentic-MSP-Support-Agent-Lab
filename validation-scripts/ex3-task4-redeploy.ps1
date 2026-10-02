# Validation: Exercise 3, Task 4 - Change the server and redeploy it
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the Container App ca-mcp-<DID> runs an mcp-server image that the team built
# (any tag other than the provisioned 1.0.0), its latest revision is ready, and /health
# reports a version other than 1.0.0.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $app = Get-AzResource -ResourceType 'Microsoft.App/containerApps' -Name "ca-mcp-$DeploymentID" | Select-Object -First 1
        if (-not $app) { throw "Container App ca-mcp-$DeploymentID was not found." }
        $detail = (Invoke-AzRestMethod -Method GET -Path "$($app.ResourceId)?api-version=2024-03-01").Content | ConvertFrom-Json
        $image = $detail.properties.template.containers[0].image
        $latest = $detail.properties.latestRevisionName
        $ready = $detail.properties.latestReadyRevisionName
        $fqdn = $detail.properties.configuration.ingress.fqdn
        $health = $null
        try { $health = Invoke-RestMethod -Uri "https://$fqdn/health" -TimeoutSec 15 } catch { $health = $null }

        if ($image -notmatch '/mcp-server:') {
            $message = "The Container App runs '$image', not an mcp-server image from the team registry."
        }
        elseif ($image -match ':1\.0\.0$') {
            $message = "The Container App still runs the provisioned image ($image). Build and deploy your change with .\scripts\Deploy-McpServer.ps1."
        }
        elseif ($latest -ne $ready) {
            $message = "Revision $latest is not ready yet (latest ready: $ready). Wait for it to finish provisioning, then validate again."
        }
        elseif (-not $health -or $health.status -ne 'ok') {
            $message = "Revision $ready is deployed but https://$fqdn/health did not report status ok."
        }
        elseif ($health.version -eq '1.0.0') {
            $message = "The new image is running but /health still reports version 1.0.0. Change __version__ in src/servicedesk_mcp/__init__.py and redeploy."
        }
        else {
            $status = 'Succeeded'
            $message = "Revision $ready runs $image and reports version $($health.version)."
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
