#Requires -Version 7.0
<#
.SYNOPSIS
    Finishes a team environment after the ARM deployment. Called by psscript-01.ps1 on the lab
    VM; can be re-run by a facilitator.

.DESCRIPTION
    Steps, in order (each is idempotent and records its outcome in C:\LabFiles\provision-status.json):
      signin       Azure CLI sign-in: the VM's provisioning identity at first boot, or the existing
                   session when a facilitator re-runs a step
      settings     discover the team's resources and write C:\LabFiles\team-settings.json
      environment  create the team's Power Platform developer environment (Dataverse)
      schema       import the Service Desk solution if exported, then apply schema.json
      security     auditing, the MCP application user (System Administrator), reference role
      seed         generate and load the seed data (anchored to now)
      mcp          build the MCP server image in ACR from the release in the lab files, deploy it
                   to the Container App, and create the team's local Git copy in C:\LabFiles\mcp-server
      agent        create the Foundry agent (no knowledge, no tools) and read its agent identity
      gateway      allow that agent identity on the API Management MCP API
      files        render the search index definition and stage helper scripts
      smoketest    health check and one tool call through API Management

    Identities. Azure Resource Manager changes (image builds, Container App and API Management
    updates) run as the lab VM's user-assigned provisioning identity, which Azure's mandatory
    MFA for Resource Manager doesn't apply to. Dataverse and Power Platform calls run as the team
    user, who owns the developer environment; at first boot the team user's password arrives in
    the MSPLAB_SIGNIN_SECRET environment variable and tokens are requested in-process. When
    MSPLAB_SIGNIN_SECRET is not set (a facilitator re-run), every call uses the current Azure CLI
    session, so sign in first with 'az login' as the team user.

.EXAMPLE
    # Facilitator, in PowerShell 7 run as administrator on the team VM, after 'az login' as the team user:
    $s = Get-Content C:\LabFiles\team-settings.json -Raw | ConvertFrom-Json
    pwsh C:\LabFiles\provision\Provision-ServiceDesk.ps1 -DeploymentID $s.DeploymentID -ResourceGroupName $s.ResourceGroup `
        -AzureUserName $s.TeamUser -AzureTenantID $s.TenantId -AzureSubscriptionID $s.SubscriptionId `
        -McpGatewayAppId $s.McpGatewayAppId -ResetData
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DeploymentID,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$AzureUserName,
    [Parameter(Mandatory)][string]$AzureTenantID,
    [Parameter(Mandatory)][string]$AzureSubscriptionID,
    [Parameter(Mandatory)][string]$McpGatewayAppId,
    [string]$ProvisioningIdentityClientId,
    [string]$DataverseLocation = 'europe',
    [string]$DataverseUrlSuffix = 'crm4.dynamics.com',
    [string[]]$Steps = @('signin', 'settings', 'environment', 'schema', 'security', 'seed', 'mcp', 'agent', 'gateway', 'files', 'smoketest'),
    [switch]$ResetData
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$labFiles = 'C:\LabFiles'
Import-Module (Join-Path $root 'MspLab.Common.psm1') -Force
New-Item -ItemType Directory -Path 'C:\WindowsAzure\Logs' -Force | Out-Null
Start-Transcript -Path 'C:\WindowsAzure\Logs\MspProvisioning.txt' -Append | Out-Null

if ($ResetData) { $Steps = @('signin', 'settings', 'seed') }
$settingsPath = Join-Path $labFiles 'team-settings.json'

# First boot: Resource Manager calls go through the provisioning identity in a CLI profile of
# their own, so they never mix with the lab user's own 'az login'.
$provisioningMode = [bool]$env:MSPLAB_SIGNIN_SECRET
if ($provisioningMode) {
    $env:AZURE_CONFIG_DIR = Join-Path $labFiles '.azure-provisioning'
    New-Item -ItemType Directory -Path $env:AZURE_CONFIG_DIR -Force | Out-Null
}
Set-UserSignIn -UserName $AzureUserName -TenantId $AzureTenantID
$python = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $python -and (Test-Path 'C:\Python312\python.exe')) { $python = 'C:\Python312\python.exe' }

function Save-Settings($s) { $s | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsPath -Encoding utf8 }

function Run-Step([string]$name, [scriptblock]$body) {
    if ($Steps -notcontains $name) { return }
    Write-Step "=== $name ==="
    try {
        $detail = & $body
        Set-StepStatus -Step $name -State Succeeded -Detail ([string]$detail)
    }
    catch {
        Set-StepStatus -Step $name -State Failed -Detail $_.Exception.Message
        Write-Step "Step '$name' failed: $($_.Exception.Message)"
        throw
    }
}

try {
    Run-Step 'signin' {
        if (-not $provisioningMode) {
            # Facilitator re-runs: use the existing interactive Azure CLI session of the team user.
            $current = az account show --query user.name --output tsv 2>$null
            if ($current -ne $AzureUserName) {
                throw "MSPLAB_SIGNIN_SECRET is not set and the Azure CLI session is not $AzureUserName. Run 'az login' as the team user first."
            }
            az account set --subscription $AzureSubscriptionID
            return "reused the Azure CLI session of $current"
        }
        if (-not $ProvisioningIdentityClientId) { throw 'ProvisioningIdentityClientId is required for first-boot provisioning.' }
        # The identity's role assignments exist before the VM does, but can take minutes to apply;
        # until then the subscription is not visible to it.
        Invoke-WithRetry -What 'az login --identity' -Attempts 20 -DelaySeconds 30 -Action {
            az login --identity --client-id $ProvisioningIdentityClientId --allow-no-subscriptions --output none 2>$null
            if ($LASTEXITCODE) {
                # Azure CLI versions before 2.69 name the parameter --username.
                az login --identity --username $ProvisioningIdentityClientId --allow-no-subscriptions --output none
            }
            if ($LASTEXITCODE) { throw "az login --identity failed ($LASTEXITCODE)" }
            az account set --subscription $AzureSubscriptionID 2>$null
            if ($LASTEXITCODE) { throw "subscription $AzureSubscriptionID is not visible to the provisioning identity yet" }
        }
        "Azure CLI uses the provisioning identity $ProvisioningIdentityClientId; Dataverse calls run as $AzureUserName"
    }

    Run-Step 'settings' {
        $rg = $ResourceGroupName
        $required = 'Microsoft.ContainerRegistry/registries', 'Microsoft.App/containerApps', 'Microsoft.ApiManagement/service',
                    'Microsoft.CognitiveServices/accounts', 'Microsoft.Search/searchServices', 'Microsoft.ManagedIdentity/userAssignedIdentities'
        $resources = Invoke-WithRetry -What 'list the team resources' -Attempts 20 -DelaySeconds 30 -Action {
            $list = @(az resource list --resource-group $rg --query '[].{name:name, type:type}' --output json 2>$null | ConvertFrom-Json)
            $missing = @($required | Where-Object { $_ -notin $list.type })
            if ($missing) { throw "not visible yet: $($missing -join ', ')" }
            $list
        }
        function NameOf([string]$type) { ($resources | Where-Object { $_.type -eq $type } | Select-Object -First 1).name }
        $acr = NameOf 'Microsoft.ContainerRegistry/registries'
        $ca = NameOf 'Microsoft.App/containerApps'
        $apim = NameOf 'Microsoft.ApiManagement/service'
        $foundry = NameOf 'Microsoft.CognitiveServices/accounts'
        $project = "proj-msp-$DeploymentID"
        $fqdn = az containerapp show --name $ca --resource-group $rg --query 'properties.configuration.ingress.fqdn' --output tsv
        $mcpIdentity = "id-mcp-$DeploymentID"
        $existing = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
        $dvUrl = $existing['DataverseUrl'] ?? "https://mspdesk$DeploymentID.$DataverseUrlSuffix"
        $settings = [ordered]@{
            DeploymentID = $DeploymentID; SubscriptionId = $AzureSubscriptionID; TenantId = $AzureTenantID; ResourceGroup = $rg
            Region = (az group show --name $rg --query location --output tsv); TeamUser = $AzureUserName
            ContainerRegistry = $acr; ContainerRegistryLoginServer = "$acr.azurecr.io"; ContainerApp = $ca; McpServerUrl = "https://$fqdn"
            ApimName = $apim; McpGatewayUrl = "https://$apim.azure-api.net/servicedesk/mcp"
            McpDiagnosticsUrl = "https://$apim.azure-api.net/servicedesk-diag/mcp"; ApimDiagnosticsSubscription = 'team-diagnostics'
            McpGatewayAppId = $McpGatewayAppId; McpGatewayAudience = "api://$McpGatewayAppId"
            DataverseUrl = $dvUrl; ServiceDeskAppUrl = "$dvUrl/main.aspx?appname=msp_ServiceDesk"
            SearchService = (NameOf 'Microsoft.Search/searchServices'); SearchEndpoint = "https://$(NameOf 'Microsoft.Search/searchServices').search.windows.net"
            SearchIndex = 'servicedesk-knowledge'; FoundryResource = $foundry; FoundryProject = $project
            FoundryProjectEndpoint = "https://$foundry.services.ai.azure.com/api/projects/$project"
            ChatDeployment = 'gpt-5.4-mini'; EmbeddingDeployment = 'text-embedding-3-small'; AgentName = 'msp-support-agent'
            KeyVault = (NameOf 'Microsoft.KeyVault/vaults'); LogAnalyticsWorkspace = (NameOf 'Microsoft.OperationalInsights/workspaces')
            AppInsights = (NameOf 'Microsoft.Insights/components'); McpBackendIdentity = $mcpIdentity
            McpBackendIdentityClientId = (az identity show --name $mcpIdentity --resource-group $rg --query clientId --output tsv)
            AgentIdentityObjectId = $existing['AgentIdentityObjectId'] ?? ''; AgentIdentityClientId = $existing['AgentIdentityClientId'] ?? ''
            McpServerSource = (Join-Path $labFiles 'mcp-server')
        }
        Save-Settings $settings
        "settings written for $rg"
    }

    $settings = Read-TeamSettings $settingsPath

    Run-Step 'environment' {
        $out = Join-Path $root 'environment.json'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'powerplatform\New-DeveloperEnvironment.ps1') `
            -DeploymentID $DeploymentID -AzureUserName $AzureUserName -DomainName "mspdesk$DeploymentID" -Location $DataverseLocation -OutFile $out
        if ($LASTEXITCODE) { throw "New-DeveloperEnvironment.ps1 failed ($LASTEXITCODE)" }
        $envInfo = Get-Content $out -Raw | ConvertFrom-Json
        if ($envInfo.instanceUrl -ne $settings.DataverseUrl) {
            Write-Step "  Dataverse URL is $($envInfo.instanceUrl) (expected $($settings.DataverseUrl)); updating settings and the container app."
            $s = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
            $s.DataverseUrl = $envInfo.instanceUrl
            $s.ServiceDeskAppUrl = "$($envInfo.instanceUrl)/main.aspx?appname=msp_ServiceDesk"
            Save-Settings $s
            az containerapp update --name $settings.ContainerApp --resource-group $settings.ResourceGroup `
                --set-env-vars "DATAVERSE_URL=$($envInfo.instanceUrl)" --output none
            if ($LASTEXITCODE) { throw "az containerapp update --set-env-vars failed ($LASTEXITCODE)" }
        }
        $envInfo.instanceUrl
    }

    $settings = Read-TeamSettings $settingsPath
    $dv = $settings.DataverseUrl

    Run-Step 'schema' {
        $zip = Join-Path $root 'dataverse\solutions\RelecloudServiceDesk.zip'
        if (Test-Path $zip) {
            Write-Step '  importing the exported Service Desk solution'
            $r = Invoke-Dataverse -OrgUrl $dv -Method POST -Path 'ImportSolutionAsync' -Body @{
                OverwriteUnmanagedCustomizations = $true; PublishWorkflows = $false
                CustomizationFile = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip)) }
            $opId = $r.Body.AsyncOperationId
            $deadline = (Get-Date).AddMinutes(30)
            do {
                Start-Sleep -Seconds 20
                $op = (Invoke-Dataverse -OrgUrl $dv -Method GET -Path "asyncoperations($opId)?`$select=statuscode,friendlymessage").Body
            } until ($op.statuscode -in 30, 31, 32 -or (Get-Date) -gt $deadline)
            if ($op.statuscode -ne 30) { throw "Solution import did not succeed (status $($op.statuscode)): $($op.friendlymessage)" }
        }
        & (Join-Path $root 'dataverse\Deploy-ServiceDeskSchema.ps1') -OrgUrl $dv | Out-String | Write-Host
        'schema in place'
    }

    Run-Step 'security' {
        $result = & (Join-Path $root 'dataverse\Set-DataverseSecurity.ps1') -OrgUrl $dv -McpIdentityClientId $settings.McpBackendIdentityClientId
        "application user $($result.ApplicationUserId)"
    }

    Run-Step 'seed' {
        if (-not $python) { throw 'Python 3.12 is not installed.' }
        $seedDir = Join-Path $labFiles 'seed'
        $dataDir = Join-Path $seedDir 'data'
        & $python (Join-Path $seedDir 'generate_seed.py') --out $dataDir --anchor auto | Write-Host
        if ($LASTEXITCODE) { throw 'generate_seed.py failed' }
        $loadArgs = @((Join-Path $seedDir 'load_seed.py'), '--url', $dv, '--data', $dataDir)
        if ($ResetData) { $loadArgs += '--reset' }
        # First boot: the loader runs as the team user with a fresh token (valid for at least an
        # hour). Re-runs: the loader asks the Azure CLI session for tokens itself.
        if ($provisioningMode) { $env:MSPLAB_DATAVERSE_TOKEN = Get-DataverseToken -OrgUrl $dv -Fresh }
        try {
            & $python @loadArgs | Write-Host
            $loadExit = $LASTEXITCODE
        }
        finally { Remove-Item Env:\MSPLAB_DATAVERSE_TOKEN -ErrorAction SilentlyContinue }
        if ($loadExit) { throw 'load_seed.py reported errors; see C:\LabFiles\seed\data\load-summary.json' }
        (Get-Content (Join-Path $dataDir 'manifest.json') -Raw | ConvertFrom-Json).anchor
    }

    Run-Step 'mcp' {
        # The server's source repository is private, so the lab files archive carries the release
        # (provision\mcp-server, packed from its Git tag by Build-LabFilesZip.ps1) and the VM never
        # contacts GitHub. The image is built from that pristine copy. The team's working copy,
        # C:\LabFiles\mcp-server, is a local Git repository of the same release with no remote;
        # a re-run keeps it, so a team's changes survive.
        $release = Join-Path $root 'mcp-server'
        if (-not (Test-Path (Join-Path $release 'Dockerfile'))) { throw "The MCP server release is missing from $release; rebuild msp-labfiles.zip." }
        $expectedVersion = if ((Get-Content (Join-Path $release 'src\servicedesk_mcp\__init__.py') -Raw) -match '__version__\s*=\s*"([^"]+)"') { $Matches[1] }
                           else { throw 'The MCP server release has no __version__.' }
        $releaseTag = "v$expectedVersion"
        function Invoke-Git { git @args; if ($LASTEXITCODE) { throw "git $($args -join ' ') failed ($LASTEXITCODE)" } }
        $work = Join-Path $labFiles 'mcp-server'
        if (-not (Test-Path (Join-Path $work '.git'))) {
            if (Test-Path $work) { Remove-Item $work -Recurse -Force }
            Copy-Item $release $work -Recurse
            Invoke-Git -C $work init --quiet --initial-branch=main
            Invoke-Git -C $work add --all
            Invoke-Git -C $work -c 'user.name=Relecloud automation team' -c 'user.email=automation@relecloud.example' `
                commit --quiet -m "Relecloud Service Desk MCP server $releaseTag"
            Invoke-Git -C $work tag $releaseTag
        }
        # SYSTEM owns the folder, so Git would refuse it for the lab user without this entry.
        $gitPath = $work.Replace('\', '/')
        if (@(git config --system --get-all safe.directory 2>$null) -notcontains $gitPath) {
            Invoke-Git config --system --add safe.directory $gitPath
        }
        $tag = $expectedVersion
        Invoke-WithRetry -What 'az acr build' -DelaySeconds 30 -Attempts 3 -Action {
            az acr build --registry $settings.ContainerRegistry --image "mcp-server:$tag" --file (Join-Path $release 'Dockerfile') $release --output none
            if ($LASTEXITCODE) { throw "az acr build failed ($LASTEXITCODE)" }
        }
        az containerapp ingress update --name $settings.ContainerApp --resource-group $settings.ResourceGroup --target-port 8000 --output none
        if ($LASTEXITCODE) { throw "az containerapp ingress update failed ($LASTEXITCODE)" }
        # Revision suffixes are unique per app, so a re-run needs a new one.
        $suffix = 'v' + ($tag -replace '[^0-9a-z]', '-') + '-' + (Get-Date -Format 'MMddHHmm')
        az containerapp update --name $settings.ContainerApp --resource-group $settings.ResourceGroup `
            --image "$($settings.ContainerRegistryLoginServer)/mcp-server:$tag" --revision-suffix $suffix --output none
        if ($LASTEXITCODE) { throw "az containerapp update failed ($LASTEXITCODE)" }
        $deadline = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep -Seconds 15
            try { $health = Invoke-RestMethod -Uri "$($settings.McpServerUrl)/health" -TimeoutSec 10 } catch { $health = $null }
            $ready = $health -and $health.status -eq 'ok' -and (-not $expectedVersion -or $health.version -eq $expectedVersion)
        } until ($ready -or (Get-Date) -gt $deadline)
        if (-not $ready) { throw "MCP server did not report version $expectedVersion as healthy within 10 minutes." }
        New-Item -ItemType Directory -Path (Join-Path $labFiles 'tools') -Force | Out-Null
        Copy-Item (Join-Path $release 'scripts\Invoke-McpTool.ps1') (Join-Path $labFiles 'tools\Invoke-McpTool.ps1') -Force
        "mcp-server $($health.version) running; team source in $work at $releaseTag"
    }

    Run-Step 'agent' {
        $agent = & (Join-Path $root 'foundry\New-SupportAgent.ps1') -ProjectEndpoint $settings.FoundryProjectEndpoint `
            -AgentName $settings.AgentName -ModelDeployment $settings.ChatDeployment
        $s = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        $s.AgentIdentityObjectId = $agent.ObjectId
        $s.AgentIdentityClientId = $agent.ClientId
        Save-Settings $s
        "agent identity $($agent.ObjectId)"
    }

    $settings = Read-TeamSettings $settingsPath

    Run-Step 'gateway' {
        & (Join-Path $root 'apim\Set-GatewayAgentIdentity.ps1') -SubscriptionId $settings.SubscriptionId -ResourceGroup $settings.ResourceGroup `
            -ApimName $settings.ApimName -AgentClientId $settings.AgentIdentityClientId
        "gateway accepts $($settings.AgentIdentityClientId)"
    }

    Run-Step 'files' {
        $template = Get-Content (Join-Path $labFiles 'search\index-definition.template.json') -Raw
        $template.Replace('{{FOUNDRY_RESOURCE}}', $settings.FoundryResource) |
            Set-Content -Path (Join-Path $labFiles 'search\index-definition.json') -Encoding utf8
        'index definition rendered'
    }

    Run-Step 'smoketest' {
        $health = Invoke-RestMethod -Uri "$($settings.McpServerUrl)/health" -TimeoutSec 15
        if ($health.status -ne 'ok') { throw "MCP /health returned $($health | ConvertTo-Json -Compress)" }
        $response = Invoke-WithRetry -What 'tool call through API Management' -DelaySeconds 30 -Action {
            & (Join-Path $labFiles 'tools\Invoke-McpTool.ps1') -Tool get_ticket -Arguments @{ ticket_number = 'TCK-10489' } `
                -SettingsPath $settingsPath -Raw
        }
        $text = $response.result.content[0].text
        if ($response.result.isError -or $text -notmatch 'Claims team cannot open policy documents') {
            throw "Tool call through API Management did not return TCK-10489: $text"
        }
        'get_ticket through API Management returned TCK-10489'
    }
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
