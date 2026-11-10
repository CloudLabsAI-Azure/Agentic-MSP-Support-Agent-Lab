#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 7: MCP modification and redeployment. A change is built, deployed and visible
    through the gateway the agent uses; the rollback succeeds.

.DESCRIPTION
    1. Records the serving revision, its image and the version the server reports.
    2. Copies C:\LabFiles\mcp-server to a temporary folder and sets the server version to -TestVersion
       (default 3.0.99) in src/servicedesk_mcp/__init__.py: a change that every MCP client sees in the
       initialize response.
    3. Builds the image with ACR Tasks (az acr build, no Docker on the VM) and deploys it as a new
       revision (az containerapp update), then waits for the revision to be ready.
    4. Confirms the new version through the API Management diagnostics endpoint (MCP initialize), else
       /health, else the server's startup log line.
    5. Rolls back to the previous image (a new revision from it, the lab's documented method) and
       confirms the previous version is served again.
    Each stage is timed. Run as the Senior Technician to prove a participant's rights are enough
    (registry push and Container Apps update through the lab's custom role).

    It changes the test environment's MCP server for a few minutes: never run it in a participant's
    environment. The test image tag stays in the registry.

.EXAMPLE
    .\Test-RedeployRollback.ps1 -EvidencePath C:\Acceptance\evidence
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$SourcePath = 'C:\LabFiles\mcp-server',
    [string]$VersionFile = 'src\servicedesk_mcp\__init__.py',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$TestVersion = '3.0.99',
    [ValidateSet('Senior', 'Current')][string]$Identity = 'Senior',
    [ValidateRange(5, 60)][int]$TimeoutMinutes = 20,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

function Get-AppState($Settings) {
    $app = & az containerapp show --name $Settings.ContainerApp --resource-group $Settings.ResourceGroup --output json 2>$null | ConvertFrom-Json
    if (-not $app) { throw "Could not read the Container App $($Settings.ContainerApp)." }
    return [pscustomobject]@{ Image = [string]$app.properties.template.containers[0].image; Latest = [string]$app.properties.latestRevisionName
        Ready = [string]$app.properties.latestReadyRevisionName; Fqdn = [string]$app.properties.configuration.ingress.fqdn }
}

function Get-ServerVersion($Settings, [string]$Revision) {
    # 1. MCP initialize through the diagnostics API (the same server the agent's gateway reaches).
    try {
        $apim = "/subscriptions/$($Settings.SubscriptionId)/resourceGroups/$($Settings.ResourceGroup)/providers/Microsoft.ApiManagement/service/$($Settings.ApimName)"
        $key = & az rest --method post --uri "https://management.azure.com$apim/subscriptions/$($Settings.ApimDiagnosticsSubscription)/listSecrets?api-version=2024-05-01" --query primaryKey --output tsv 2>$null
        if ($key) {
            $body = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ protocolVersion = '2025-11-25'; capabilities = @{}; clientInfo = @{ name = 'relecloud-acceptance'; version = '1.0' } } } | ConvertTo-Json -Depth 5
            $raw = Invoke-WebRequest -Method Post -Uri $Settings.McpDiagnosticsUrl -Body $body -ContentType 'application/json' -TimeoutSec 30 -SkipHttpErrorCheck `
                -Headers @{ Accept = 'application/json, text/event-stream'; 'MCP-Protocol-Version' = '2025-11-25'; 'Ocp-Apim-Subscription-Key' = $key }
            $text = [string]$raw.Content
            if ($text -match '(?m)^data:\s*(\{.*\})\s*$') { $text = $Matches[1] }
            $v = ($text | ConvertFrom-Json).result.serverInfo.version
            if ($v) { return [pscustomobject]@{ Version = [string]$v; Source = 'MCP initialize through the diagnostics API' } }
        }
    }
    catch { }
    # 2. /health on the app.
    foreach ($url in @($Settings.McpServerUrl) | Where-Object { $_ }) {
        try { $h = Invoke-RestMethod -Uri "$($url.TrimEnd('/'))/health" -TimeoutSec 15; if ($h.version) { return [pscustomobject]@{ Version = [string]$h.version; Source = '/health' } } } catch { }
    }
    # 3. The startup log line of the revision.
    if ($Revision) {
        $row = @(Invoke-LabLogQuery $Settings "ContainerAppConsoleLogs | where RevisionName == '$Revision' | where Log contains 'startup' | project TimeGenerated, Log | order by TimeGenerated desc | take 5" 'PT6H') | Select-Object -First 1
        if ($row) { try { $v = ($row.Log | ConvertFrom-Json).version; if ($v) { return [pscustomobject]@{ Version = [string]$v; Source = 'startup log line' } } } catch { } }
    }
    return $null
}

function Wait-Ready($Settings, [string]$Image, [int]$Minutes) {
    $deadline = (Get-Date).AddMinutes($Minutes)
    do {
        $s = Get-AppState $Settings
        if ($s.Image -eq $Image -and $s.Latest -eq $s.Ready) { return $s }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)
    throw "The revision with $Image was not ready after $Minutes minutes."
}

function Wait-Version($Settings, [string]$Expected, [string]$Revision) {
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $v = Get-ServerVersion $Settings $Revision
        if ($v -and $v.Version -eq $Expected) { return $v }
        Start-Sleep -Seconds 15
    } while ((Get-Date) -lt $deadline)
    return $v
}

$settings = Read-LabSettings $SettingsPath @('ResourceGroup', 'ContainerApp', 'ContainerRegistry', 'SubscriptionId', 'ApimName')
$report = New-AcceptanceReport 7 'MCP modification, redeployment and rollback' $settings
$work = $null
try {
    if (-not (Test-Path (Join-Path $SourcePath $VersionFile))) { throw "The MCP server source was not found at $SourcePath ($VersionFile)." }
    if (-not $PSCmdlet.ShouldProcess("$($settings.ContainerApp) in deployment $($settings.DeploymentID)", "Build and deploy version $TestVersion, then roll back")) { exit 0 }
    Use-LabIdentity $Identity $settings

    $start = Get-AppState $settings
    $baseline = Get-ServerVersion $settings $start.Ready
    Add-Note $report "Before: revision $($start.Ready), image $($start.Image), version $(if ($baseline) { "$($baseline.Version) ($($baseline.Source))" } else { 'unknown' })."
    if ($baseline -and $baseline.Version -eq $TestVersion) { throw "The server already reports $TestVersion; pass another -TestVersion." }

    # ==== Change and build
    $stamp = [datetime]::UtcNow.ToString('MMddHHmmss')
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "mcp-acceptance-$stamp"
    New-Item -ItemType Directory -Path $work | Out-Null
    Get-ChildItem -LiteralPath $SourcePath -Force | Where-Object { $_.Name -notin '.git', '.venv', 'venv', '__pycache__', '.pytest_cache' } | Copy-Item -Destination $work -Recurse -Force
    $vf = Join-Path $work $VersionFile
    $content = Get-Content -LiteralPath $vf -Raw
    if ($content -notmatch '__version__\s*=\s*["'']([^"'']+)["'']') { throw "No __version__ assignment in $VersionFile." }
    Set-Content -LiteralPath $vf -Value ([regex]::Replace($content, '__version__\s*=\s*["''][^"'']+["'']', "__version__ = `"$TestVersion`"")) -Encoding utf8 -NoNewline
    $loginServer = (& az acr show --name $settings.ContainerRegistry --query loginServer --output tsv 2>$null)
    if (-not $loginServer) { throw "Could not read the registry $($settings.ContainerRegistry)." }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    & az acr build --registry $settings.ContainerRegistry --image "mcp-server:$TestVersion" --file (Join-Path $work 'Dockerfile') $work --no-logs --output none
    $built = ($LASTEXITCODE -eq 0)
    $buildSeconds = [int]$timer.Elapsed.TotalSeconds
    Add-Check $report 'The changed server builds in the registry (ACR Tasks)' $built "mcp-server:$TestVersion in $buildSeconds s"
    if (-not $built) { throw "The build failed; list the registry's runs with: az acr task list-runs --registry $($settings.ContainerRegistry) --output table" }

    # ==== Deploy
    $newImage = "$loginServer/mcp-server:$TestVersion"
    $timer.Restart()
    & az containerapp update --name $settings.ContainerApp --resource-group $settings.ResourceGroup --image $newImage --revision-suffix "acc$stamp" --output none
    if ($LASTEXITCODE) { throw 'az containerapp update failed.' }
    $deployed = Wait-Ready $settings $newImage $TimeoutMinutes
    $deploySeconds = [int]$timer.Elapsed.TotalSeconds
    Add-Check $report 'The new revision is deployed and ready' ($deployed.Ready -ne $start.Ready) "revision $($deployed.Ready) ready in $deploySeconds s"
    $seen = Wait-Version $settings $TestVersion $deployed.Ready
    Add-Check $report 'The change is visible through the gateway' ($seen -and $seen.Version -eq $TestVersion) $(if ($seen) { "version $($seen.Version) from $($seen.Source)" } else { 'no version could be read' })

    # ==== Roll back
    $timer.Restart()
    & az containerapp update --name $settings.ContainerApp --resource-group $settings.ResourceGroup --image $start.Image --revision-suffix "rb$stamp" --output none
    if ($LASTEXITCODE) { throw 'The rollback (az containerapp update to the previous image) failed.' }
    $rolled = Wait-Ready $settings $start.Image $TimeoutMinutes
    $rollbackSeconds = [int]$timer.Elapsed.TotalSeconds
    $back = if ($baseline) { Wait-Version $settings $baseline.Version $rolled.Ready } else { Get-ServerVersion $settings $rolled.Ready }
    Add-Check $report 'The rollback serves the previous image and version' ($rolled.Image -eq $start.Image -and (-not $baseline -or ($back -and $back.Version -eq $baseline.Version))) "revision $($rolled.Ready), image $($rolled.Image), version $(if ($back) { $back.Version } else { 'unknown' }), in $rollbackSeconds s"
    $report.Evidence['timings'] = [pscustomobject]@{ BuildSeconds = $buildSeconds; DeploySeconds = $deploySeconds; RollbackSeconds = $rollbackSeconds }
    $report.Evidence['revisions'] = [pscustomobject]@{ Before = $start; Deployed = $deployed; RolledBack = $rolled }
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
finally {
    if ($work -and (Test-Path $work)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
exit (Complete-AcceptanceReport $report $EvidencePath)
