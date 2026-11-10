#Requires -Version 7.0
<#
.SYNOPSIS
    Builds the MCP server release shipped in the lab files, deploys it to the Container App as the
    baseline revision, and prepares the participant's Git working copy.

.DESCRIPTION
    1. Checks the release in C:\LabFiles\provision\mcp-server (packed from the private repository's
       Git tag by setup/Build-LabFilesZip.ps1): its version must be the release in LabConfig.psd1.
    2. Working copy C:\LabFiles\mcp-server: a local Git repository of the same release on branch
       main, tag v<release>, remote origin set to the private repository URL for reference (no
       credentials on the VM; participants never pull or push). Kept as it is when it exists, so a
       participant's changes survive a re-run.
    3. Image: ACR Tasks builds <registry>/mcp-server:<release> from the release (no Docker on the VM),
       unless the tag already exists. Azure CLI runs as the provisioning identity in a profile of its
       own (C:\LabFiles\.azure-provisioning), so it never mixes with the participant's az login.
    4. Container App, in one update, so the baseline is a single revision named
       ca-mcp-<DeploymentID>--baseline-<time>: the image, target port 8000, /health probes, and the
       settings known only after provisioning (DATAVERSE_URL, AGENT_ID, PURVIEW_ENABLED,
       PURVIEW_CLIENT_ID, PURVIEW_RESTRICTED_LABELS). Skipped when the app already runs the release
       with those settings; refused when it runs another image (a participant's redeploy) unless
       -Force.
    5. Waits until /health reports the release, status ok and the gateway key read from Key Vault.
    6. Copies the release's participant tools (Deploy-McpServer.ps1, Invoke-McpTool.ps1,
       Show-McpServerLog.ps1) to C:\LabFiles\tools.
    Identity: id-prov (AcrPush and Container Registry Tasks Contributor on the registry, Container
    Apps Contributor on the app).
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$ReleasePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'mcp-server'),
    [string]$WorkingCopy = 'C:\LabFiles\mcp-server',
    [string]$PurviewClientId = '',
    [string]$RestrictedLabels = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$config = Get-LabConfig
$settings = Read-LabSettings -Path $SettingsPath
foreach ($key in 'SubscriptionId', 'ResourceGroup', 'ContainerApp', 'ContainerRegistry', 'ContainerRegistryLoginServer', 'McpServerUrl', 'DataverseUrl') {
    if (-not $settings[$key]) { throw "lab-settings.json has no $key." }
}
$release = $config.McpRelease
$tag = "v$release"
$image = "$($settings.ContainerRegistryLoginServer)/$($config.McpImageRepository):$release"
$appPath = "/subscriptions/$($settings.SubscriptionId)/resourceGroups/$($settings.ResourceGroup)/providers/Microsoft.App/containerApps/$($settings.ContainerApp)"
$appApi = '2026-07-01'

# ==== 1. The release in the lab files
$initFile = Join-Path $ReleasePath 'src\servicedesk_mcp\__init__.py'
if (-not (Test-Path (Join-Path $ReleasePath 'Dockerfile')) -or -not (Test-Path $initFile)) {
    throw "The MCP server release is missing from $ReleasePath. Rebuild msp-labfiles.zip with setup/Build-LabFilesZip.ps1."
}
$found = if ((Get-Content $initFile -Raw) -match '__version__\s*=\s*"([^"]+)"') { $Matches[1] } else { '' }
if ($found -ne $release) { throw "The release in the lab files is version '$found'; LabConfig.psd1 expects $release. Rebuild msp-labfiles.zip." }

# ==== 2. The participant's working copy
function Invoke-Git { & git @args; if ($LASTEXITCODE) { throw "git $($args -join ' ') failed ($LASTEXITCODE)" } }
$workingCopyState = 'kept'
if (-not (Test-Path (Join-Path $WorkingCopy '.git'))) {
    if (Test-Path $WorkingCopy) { Remove-Item $WorkingCopy -Recurse -Force }
    Copy-Item $ReleasePath $WorkingCopy -Recurse
    Invoke-Git -C $WorkingCopy init --quiet --initial-branch=main
    Invoke-Git -C $WorkingCopy add --all
    Invoke-Git -C $WorkingCopy -c 'user.name=Relecloud Lab Automation' -c 'user.email=lab-automation@relecloud.example' -c 'commit.gpgsign=false' `
        commit --quiet -m "Relecloud Service Desk MCP server $tag"
    Invoke-Git -C $WorkingCopy tag $tag
    $workingCopyState = 'created'
}
if (-not (@(& git -C $WorkingCopy remote) -contains 'origin')) { Invoke-Git -C $WorkingCopy remote add origin $config.McpRepositoryUrl }
# The folder belongs to SYSTEM at first boot; Git refuses it for the participant without this entry.
$gitPath = $WorkingCopy.Replace('\', '/')
if (@(& git config --system --get-all safe.directory 2>$null) -notcontains $gitPath) { Invoke-Git config --system --add safe.directory $gitPath }

# ==== 3. Image (Azure CLI as id-prov, in its own profile; the caller's profile setting is restored)
$savedConfigDir = $env:AZURE_CONFIG_DIR
$env:AZURE_CONFIG_DIR = 'C:\LabFiles\.azure-provisioning'
try {
    New-Item -ItemType Directory -Path $env:AZURE_CONFIG_DIR -Force | Out-Null
    $clientId = Get-ProvisioningClientId
    $null = Invoke-WithRetry -What 'az login --identity' -Attempts 10 -DelaySeconds 30 -Action {
        & az login --identity --client-id $clientId --allow-no-subscriptions --output none 2>$null
        if ($LASTEXITCODE) { & az login --identity --username $clientId --allow-no-subscriptions --output none }
        if ($LASTEXITCODE) { throw "az login --identity failed ($LASTEXITCODE)" }
        & az account set --subscription $settings.SubscriptionId --output none
        if ($LASTEXITCODE) { throw "the subscription is not visible to the provisioning identity yet" }
    }
    $tags = @(& az acr repository show-tags --name $settings.ContainerRegistry --repository $config.McpImageRepository --output tsv 2>$null)
    $build = 'existing image'
    if ($Force -or $tags -notcontains $release) {
        Write-Step "  building $image with ACR Tasks"
        $null = Invoke-WithRetry -What 'az acr build' -Attempts 3 -DelaySeconds 30 -Action {
            & az acr build --registry $settings.ContainerRegistry --image "$($config.McpImageRepository):$release" `
                --file (Join-Path $ReleasePath 'Dockerfile') $ReleasePath --output none
            if ($LASTEXITCODE) { throw "az acr build failed ($LASTEXITCODE)" }
        }
        $build = 'built'
    }
}
finally {
    if ($savedConfigDir) { $env:AZURE_CONFIG_DIR = $savedConfigDir } else { Remove-Item Env:\AZURE_CONFIG_DIR -ErrorAction SilentlyContinue }
}

# ==== 4. Container App: one update, one baseline revision
$app = (Invoke-Arm -Method GET -Path $appPath -ApiVersion $appApi).Body
$container = @($app.properties.template.containers)[0]
$wanted = [ordered]@{ DATAVERSE_URL = $settings.DataverseUrl; GOLDEN_ENVIRONMENT_VERSION = $config.GoldenEnvironmentVersion }
if ($settings.AgentId) { $wanted.AGENT_ID = $settings.AgentId }
if ($PurviewClientId -and $RestrictedLabels) {
    $wanted.PURVIEW_ENABLED = 'true'; $wanted.PURVIEW_CLIENT_ID = $PurviewClientId; $wanted.PURVIEW_RESTRICTED_LABELS = $RestrictedLabels
}
$appSettings = [ordered]@{}
foreach ($e in @($container.env)) { $appSettings[$e.name] = [string]$e.value }
$envChanged = @($wanted.Keys | Where-Object { $appSettings[$_] -ne $wanted[$_] }).Count -gt 0
foreach ($k in $wanted.Keys) { $appSettings[$k] = $wanted[$k] }
$portChanged = [int]$app.properties.configuration.ingress.targetPort -ne 8000
$revisionState = 'unchanged'
if ($container.image -ne $image -and $container.image -notlike 'mcr.microsoft.com/*' -and -not $Force) {
    Write-Step "  the app runs $($container.image), not the baseline image: left as it is (a participant's redeploy). Use -Force to restore the baseline."
    $revisionState = 'skipped (another image is running)'
}
elseif ($Force -or $container.image -ne $image -or $envChanged -or $portChanged) {
    $probe = { param($type) [ordered]@{ type = $type; httpGet = @{ path = '/health'; port = 8000; scheme = 'HTTP' }
                                        initialDelaySeconds = 5; periodSeconds = 15; timeoutSeconds = 5; failureThreshold = 8 } }
    $suffix = "$($config.McpBaselineRevisionPrefix)-$((Get-Date).ToUniversalTime().ToString('yyMMddHHmm'))"
    $template = $app.properties.template
    $newContainer = [ordered]@{
        name = $container.name; image = $image; resources = $container.resources
        env = @($appSettings.Keys | ForEach-Object { @{ name = $_; value = $appSettings[$_] } })
        probes = @((& $probe 'Startup'), (& $probe 'Liveness'), (& $probe 'Readiness'))
    }
    $body = @{ properties = @{
        configuration = @{ ingress = @{ external = $true; targetPort = 8000; transport = 'auto'; allowInsecure = $false } }
        template      = [ordered]@{ revisionSuffix = $suffix; containers = @($newContainer); scale = $template.scale }
    } }
    Write-Step "  updating $($settings.ContainerApp): $image, port 8000, revision suffix $suffix"
    $null = Invoke-Arm -Method PATCH -Path $appPath -ApiVersion $appApi -Body $body -Wait
    $revisionState = "$($settings.ContainerApp)--$suffix"
}

# ==== 5. Health
$deadline = (Get-Date).AddMinutes(15)
$health = $null
do {
    Start-Sleep -Seconds 15
    try { $health = Invoke-RestMethod -Uri "$($settings.McpServerUrl.TrimEnd('/'))/health" -TimeoutSec 15 } catch { $health = $null }
    $ready = $health -and $health.status -eq 'ok' -and $health.version -eq $release
} until ($ready -or (Get-Date) -gt $deadline)
if (-not $ready) { throw "The MCP server did not report version $release as healthy within 15 minutes. Check the revision in the Azure portal (Container App, Revisions) and Show-McpServerLog.ps1." }
if ("$($health.gateway_key_source)" -ne 'key vault') { throw "The MCP server did not read its gateway key from Key Vault (gateway_key_source: $($health.gateway_key_source))." }
$app = (Invoke-Arm -Method GET -Path $appPath -ApiVersion $appApi).Body
$activeRevision = [string]$app.properties.latestReadyRevisionName

# ==== 6. Participant tools from the release
New-Item -ItemType Directory -Path 'C:\LabFiles\tools' -Force | Out-Null
foreach ($script in $config.McpToolsFromRelease) {
    $source = Join-Path $ReleasePath "scripts\$script"
    if (-not (Test-Path $source)) { throw "The release has no scripts\$script." }
    Copy-Item $source (Join-Path 'C:\LabFiles\tools' $script) -Force
}

[pscustomobject]@{
    Image             = $image
    Build             = $build
    Revision          = $revisionState
    ActiveRevision    = $activeRevision
    Version           = [string]$health.version
    GatewayKeySource  = [string]$health.gateway_key_source
    UserImpersonation = $health.user_impersonation
    WorkingCopy       = "$WorkingCopy ($workingCopyState, tag $tag)"
}
