#Requires -Version 7.0
<#
.SYNOPSIS
    Finishes a team environment after the ARM deployment. Called by psscript-01.ps1 on the lab
    VM; Spektra support can re-run it.

.DESCRIPTION
    Steps, in order (each is idempotent and records its outcome in C:\LabFiles\provision-status.json):
      signin       Azure CLI sign-in: the VM's provisioning identity at first boot, or the existing
                   session when support re-runs a step
      settings     discover the team's resources and write C:\LabFiles\team-settings.json
      environment  create the team's Power Platform developer environment (Dataverse) and add
                   the Tier 1 Technician to it
      schema       import the Service Desk solution if exported, then apply schema.json
      security     auditing, least-privileged roles, application users, the two technicians,
                   the regulated accounts business unit (Set-DataverseSecurity.ps1)
      seed         generate and load the seed data (anchored to now), with the sensitivity label
                   on the customer configuration document
      export       export the searchable Service Desk content to C:\LabFiles\search\export, the
                   source Exercise 1 loads into Azure AI Search
      incidents    load the two new incidents (after the export, so they are never indexed)
      mcp          build the MCP server image in ACR from the release in the lab files, deploy it
                   to the Container App, and create the team's local Git copy in C:\LabFiles\mcp-server
      agent        create the Foundry agent with the baseline instructions and the Service Desk MCP
                   tool (no knowledge source), and record its Entra Agent ID on the MCP server
      files        render the search index definition and stage the helper scripts
      readiness    run the readiness check the participants run first (Test-LabReadiness.ps1)

    Identities. Azure Resource Manager changes (image builds, Container App updates) run as the
    lab VM's user-assigned provisioning identity, which Azure's mandatory MFA for Resource
    Manager doesn't apply to; it is also a Dataverse application user with read access, used for
    the export and the readiness check. Dataverse and Power Platform changes run as the team
    user, who owns the developer environment; at first boot the team user's password arrives in
    the MSPLAB_SIGNIN_SECRET environment variable and tokens are requested in-process. When
    MSPLAB_SIGNIN_SECRET is not set (a support re-run), every call uses the current Azure CLI
    session, so sign in first with 'az login' as the team user.

    Per-team settings that are not secrets (Tier 1 user, sensitivity label, MCP connection name)
    come from the lab VM's tags (deploy-01.json), read through the Instance Metadata Service.

.EXAMPLE
    # Support, in PowerShell 7 run as administrator on the team VM, after 'az login' as the team user:
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
    [string[]]$Steps = @('signin', 'settings', 'environment', 'schema', 'security', 'seed', 'export', 'incidents', 'mcp', 'agent',
                         'files', 'readiness'),
    [switch]$ResetData
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$labFiles = 'C:\LabFiles'
Import-Module (Join-Path $root 'MspLab.Common.psm1') -Force
New-Item -ItemType Directory -Path 'C:\WindowsAzure\Logs' -Force | Out-Null
Start-Transcript -Path 'C:\WindowsAzure\Logs\MspProvisioning.txt' -Append | Out-Null

if ($ResetData) { $Steps = @('signin', 'settings', 'seed', 'export', 'incidents') }
$settingsPath = Join-Path $labFiles 'team-settings.json'
$readTools = @('search_tickets', 'get_open_tickets', 'get_ticket', 'get_ticket_notes', 'get_customer', 'get_customer_contacts',
               'get_customer_document', 'get_knowledge_article', 'list_technicians')

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
$tags = Get-VmTags
function Tag([string]$name, [string]$default = '') {
    $value = $tags[$name]
    if ([string]::IsNullOrWhiteSpace($value) -or $value -like 'REPLACE-WITH-*') { return $default }
    return $value
}

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

function Invoke-Seed([string[]]$extraArgs) {
    $seedDir = Join-Path $labFiles 'seed'
    $dataDir = Join-Path $seedDir 'data'
    $loadArgs = @((Join-Path $seedDir 'load_seed.py'), '--url', $settings.DataverseUrl, '--data', $dataDir) + $extraArgs
    # First boot: the loader runs as the team user with a fresh token (valid for at least an
    # hour). Re-runs: the loader asks the Azure CLI session for tokens itself.
    if ($provisioningMode) { $env:MSPLAB_DATAVERSE_TOKEN = Get-DataverseToken -OrgUrl $settings.DataverseUrl -Fresh }
    try {
        & $python @loadArgs | Write-Host
        $loadExit = $LASTEXITCODE
    }
    finally { Remove-Item Env:\MSPLAB_DATAVERSE_TOKEN -ErrorAction SilentlyContinue }
    if ($loadExit) { throw 'load_seed.py reported errors; see C:\LabFiles\seed\data\load-summary.json' }
}

function Wait-McpHealth([string]$expectedVersion, [string]$expectedAgentId = '') {
    $deadline = (Get-Date).AddMinutes(10)
    do {
        Start-Sleep -Seconds 15
        try { $health = Invoke-RestMethod -Uri "$($settings.McpServerUrl)/health" -TimeoutSec 10 } catch { $health = $null }
        $ready = $health -and $health.status -eq 'ok' -and (-not $expectedVersion -or $health.version -eq $expectedVersion) -and
                 (-not $expectedAgentId -or $health.agent.id -eq $expectedAgentId)
    } until ($ready -or (Get-Date) -gt $deadline)
    if (-not $ready) { throw "MCP server did not report version $expectedVersion as healthy within 10 minutes." }
    return $health
}

try {
    Run-Step 'signin' {
        if (-not $provisioningMode) {
            # Support re-runs: use the existing interactive Azure CLI session of the team user.
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
        "Azure CLI uses the provisioning identity $ProvisioningIdentityClientId; Dataverse changes run as $AzureUserName"
    }

    Run-Step 'settings' {
        $rg = $ResourceGroupName
        $required = 'Microsoft.ContainerRegistry/registries', 'Microsoft.App/containerApps', 'Microsoft.ApiManagement/service',
                    'Microsoft.CognitiveServices/accounts', 'Microsoft.Search/searchServices', 'Microsoft.ManagedIdentity/userAssignedIdentities',
                    'Microsoft.KeyVault/vaults'
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
        $kv = NameOf 'Microsoft.KeyVault/vaults'
        $project = "proj-msp-$DeploymentID"
        $fqdn = az containerapp show --name $ca --resource-group $rg --query 'properties.configuration.ingress.fqdn' --output tsv
        $mcpIdentity = "id-mcp-$DeploymentID"
        $existing = if (Test-Path $settingsPath) { Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }
        $dvUrl = $existing['DataverseUrl'] ?? "https://mspdesk$DeploymentID.$DataverseUrlSuffix"
        $settings = [ordered]@{
            DeploymentID = $DeploymentID; SubscriptionId = $AzureSubscriptionID; TenantId = $AzureTenantID; ResourceGroup = $rg
            Region = (az group show --name $rg --query location --output tsv); TeamUser = $AzureUserName
            Tier1User = (Tag 'msplab-tier1-user'); Tier1UserObjectId = (Tag 'msplab-tier1-oid')
            ContainerRegistry = $acr; ContainerRegistryLoginServer = "$acr.azurecr.io"; ContainerApp = $ca; McpServerUrl = "https://$fqdn"
            ApimName = $apim; McpGatewayUrl = "https://$apim.azure-api.net/servicedesk/mcp"
            McpDiagnosticsUrl = "https://$apim.azure-api.net/servicedesk-diag/mcp"; ApimDiagnosticsSubscription = 'team-diagnostics'
            McpGatewayAppId = $McpGatewayAppId; McpGatewayAudience = "api://$McpGatewayAppId"; McpGatewayScope = 'ServiceDesk.Access'
            McpConnectionName = (Tag 'msplab-mcp-connection' 'servicedesk-mcp'); McpReadTools = $readTools
            DataverseUrl = $dvUrl; ServiceDeskAppUrl = "$dvUrl/main.aspx?appname=spk_ServiceDesk"
            SearchService = (NameOf 'Microsoft.Search/searchServices'); SearchEndpoint = "https://$(NameOf 'Microsoft.Search/searchServices').search.windows.net"
            SearchIndex = 'servicedesk-knowledge'; SearchExport = (Join-Path $labFiles 'search\export')
            FoundryResource = $foundry; FoundryProject = $project
            FoundryProjectEndpoint = "https://$foundry.services.ai.azure.com/api/projects/$project"
            ChatDeployment = 'gpt-5.4-mini'; EmbeddingDeployment = 'text-embedding-3-small'; AgentName = 'msp-support-agent'
            KeyVault = $kv; KeyVaultUrl = "https://$kv.vault.azure.net/"
            LogAnalyticsWorkspace = (NameOf 'Microsoft.OperationalInsights/workspaces')
            AppInsights = (NameOf 'Microsoft.Insights/components'); McpBackendIdentity = $mcpIdentity
            McpBackendIdentityClientId = (az identity show --name $mcpIdentity --resource-group $rg --query clientId --output tsv)
            ProvisioningIdentityClientId = $(if ($ProvisioningIdentityClientId) { $ProvisioningIdentityClientId } else { $existing['ProvisioningIdentityClientId'] ?? '' })
            SensitivityLabelId = (Tag 'msplab-label-id'); SensitivityLabelName = (Tag 'msplab-label-name' 'Confidential')
            Purview = (Tag 'msplab-purview' 'not configured')
            AgentId = $existing['AgentId'] ?? ''
            AgentIdentityObjectId = $existing['AgentIdentityObjectId'] ?? ''; AgentIdentityClientId = $existing['AgentIdentityClientId'] ?? ''
            McpServerSource = (Join-Path $labFiles 'mcp-server')
        }
        Save-Settings $settings
        "settings written for $rg"
    }

    $settings = Read-TeamSettings $settingsPath

    Run-Step 'environment' {
        $out = Join-Path $root 'environment.json'
        $extra = @()
        if ($settings.Tier1UserObjectId) { $extra = @('-AdditionalUserObjectIds', $settings.Tier1UserObjectId) }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'powerplatform\New-DeveloperEnvironment.ps1') `
            -DeploymentID $DeploymentID -AzureUserName $AzureUserName -DomainName "mspdesk$DeploymentID" -Location $DataverseLocation `
            -OutFile $out @extra
        if ($LASTEXITCODE) { throw "New-DeveloperEnvironment.ps1 failed ($LASTEXITCODE)" }
        $envInfo = Get-Content $out -Raw | ConvertFrom-Json
        if ($envInfo.instanceUrl -ne $settings.DataverseUrl) {
            Write-Step "  Dataverse URL is $($envInfo.instanceUrl) (expected $($settings.DataverseUrl)); updating settings and the container app."
            $s = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
            $s.DataverseUrl = $envInfo.instanceUrl
            $s.ServiceDeskAppUrl = "$($envInfo.instanceUrl)/main.aspx?appname=spk_ServiceDesk"
            Save-Settings $s
            az containerapp update --name $settings.ContainerApp --resource-group $settings.ResourceGroup `
                --set-env-vars "DATAVERSE_URL=$($envInfo.instanceUrl)" --output none
            if ($LASTEXITCODE) { throw "az containerapp update --set-env-vars failed ($LASTEXITCODE)" }
        }
        "$($envInfo.instanceUrl); added users: $(@($envInfo.addedUsers).Count)"
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
        $securityArgs = @{ OrgUrl = $dv; McpIdentityClientId = $settings.McpBackendIdentityClientId; SeniorUserName = $AzureUserName }
        if ($settings.ProvisioningIdentityClientId) { $securityArgs.ReadinessIdentityClientId = $settings.ProvisioningIdentityClientId }
        if ($settings.Tier1UserObjectId) { $securityArgs.Tier1UserObjectId = $settings.Tier1UserObjectId }
        if ($settings.Tier1User) { $securityArgs.Tier1UserName = $settings.Tier1User }
        $result = & (Join-Path $root 'dataverse\Set-DataverseSecurity.ps1') @securityArgs
        "MCP application user $($result.ApplicationUserId); Tier 1 user $($result.Tier1UserId ?? 'not configured')"
    }

    Run-Step 'seed' {
        if (-not $python) { throw 'Python 3.12 is not installed.' }
        $dataDir = Join-Path $labFiles 'seed\data'
        & $python (Join-Path $labFiles 'seed\generate_seed.py') --out $dataDir --anchor auto | Write-Host
        if ($LASTEXITCODE) { throw 'generate_seed.py failed' }
        $extra = @()
        if ($ResetData) { $extra += '--reset' }
        if ($settings.SensitivityLabelId) {
            $extra += @('--label-id', $settings.SensitivityLabelId, '--label-name', $settings.SensitivityLabelName, '--tenant-id', $AzureTenantID)
        }
        Invoke-Seed $extra
        (Get-Content (Join-Path $dataDir 'manifest.json') -Raw | ConvertFrom-Json).anchor
    }

    Run-Step 'export' {
        # Runs as the provisioning identity (Dataverse application user, read only). The two
        # new incidents are not loaded yet, so the export matches the seeded history exactly.
        $result = & (Join-Path $labFiles 'search\Load-SearchIndex.ps1') -Export -SettingsPath $settingsPath
        "exported $($result.Documents) documents to $($settings.SearchExport)"
    }

    Run-Step 'incidents' {
        Invoke-Seed @('--only', 'newincidents')
        'new incidents loaded: ' + ((Get-Content (Join-Path $labFiles 'seed\data\manifest.json') -Raw | ConvertFrom-Json).new_incidents -join ', ')
    }

    Run-Step 'mcp' {
        # The server's source repository is private, so the lab files archive carries the release
        # (provision\mcp-server, packed from its Git tag by Build-LabFilesZip.ps1) and the VM never
        # contacts GitHub. The image is built from that pristine copy. The team's working copy,
        # C:\LabFiles\mcp-server, is a local Git repository of the same release with no remote,
        # already in place when the lab starts; a re-run keeps it, so a team's changes survive.
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
        $health = Wait-McpHealth $expectedVersion
        if ($health.gateway_key_source -ne 'key vault') { throw "The MCP server did not read its gateway key from Key Vault: $($health.gateway_key_source)" }
        New-Item -ItemType Directory -Path (Join-Path $labFiles 'tools') -Force | Out-Null
        foreach ($script in 'Invoke-McpTool.ps1', 'Show-McpServerLog.ps1') {
            Copy-Item (Join-Path $release "scripts\$script") (Join-Path $labFiles "tools\$script") -Force
        }
        "mcp-server $($health.version) running (gateway key from Key Vault); team source in $work at $releaseTag"
    }

    Run-Step 'agent' {
        $agent = & (Join-Path $root 'foundry\New-SupportAgent.ps1') -ProjectEndpoint $settings.FoundryProjectEndpoint `
            -AgentName $settings.AgentName -ModelDeployment $settings.ChatDeployment `
            -InstructionsPath (Join-Path $labFiles 'agent\instructions-baseline.md') `
            -McpServerUrl $settings.McpGatewayUrl -McpConnectionName $settings.McpConnectionName -ReadTools $readTools
        $s = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
        $s.AgentId = $agent.AgentId
        $s.AgentIdentityObjectId = $agent.ObjectId
        $s.AgentIdentityClientId = $agent.ClientId
        Save-Settings $s
        # The MCP server writes the agent's Entra Agent ID into every log line and sends it to Purview.
        az containerapp update --name $settings.ContainerApp --resource-group $settings.ResourceGroup `
            --set-env-vars "AGENT_ID=$($agent.ClientId)" --output none
        if ($LASTEXITCODE) { throw "az containerapp update --set-env-vars AGENT_ID failed ($LASTEXITCODE)" }
        Wait-McpHealth '' $agent.ClientId | Out-Null
        "agent $($agent.AgentName) with the Service Desk MCP tool; Entra Agent ID $($agent.ClientId)"
    }

    $settings = Read-TeamSettings $settingsPath

    Run-Step 'files' {
        $template = Get-Content (Join-Path $labFiles 'search\index-definition.template.json') -Raw
        $template.Replace('{{FOUNDRY_RESOURCE}}', $settings.FoundryResource) |
            Set-Content -Path (Join-Path $labFiles 'search\index-definition.json') -Encoding utf8
        'index definition rendered'
    }

    Run-Step 'readiness' {
        $report = & (Join-Path $labFiles 'tools\Test-LabReadiness.ps1') -SettingsPath $settingsPath -AsProvisioning -PassThru
        $failed = @($report | Where-Object { $_.Status -eq 'Not ready' })
        if ($failed) { throw "Readiness check failed: $(($failed | ForEach-Object { "$($_.Component): $($_.Detail)" }) -join '; ')" }
        $notConfigured = @($report | Where-Object { $_.Status -eq 'Not configured' } | ForEach-Object Component)
        "$(@($report | Where-Object Status -eq 'Ready').Count) components ready" + $(if ($notConfigured) { "; not configured: $($notConfigured -join ', ')" } else { '' })
    }
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
