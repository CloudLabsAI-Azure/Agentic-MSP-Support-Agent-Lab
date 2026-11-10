#Requires -Version 7.0
<#
.SYNOPSIS
    Prepares one participant environment after the ARM deployment (Golden Environment v1.0). Runs
    on the lab VM at first boot, started by psscript-01.ps1; CloudLabs support can re-run steps.

.DESCRIPTION
    Every step is idempotent and records Running, Succeeded, Failed or Skipped, with the reason, in
    C:\LabFiles\provision-status.json. The transcript is C:\WindowsAzure\Logs\MspProvisioning.txt.
    A failed step skips only the steps that depend on it; finalize always runs at first boot,
    because the participant must never receive an environment in which they or the setup app still
    hold administrator rights.

      Step           Identity                                What it does
      prerequisites  id-prov (Resource Manager)              waits for the resources and roles; writes lab-settings.json
      bootstrap      bootstrap identity (see below)          creates or repairs the certificate-based setup app
      users          setup app (Graph); id-prov (ARM)        both technicians and their licenses; Tier 1 Foundry role on the project
      gateway        setup app (Graph); id-prov (APIM)       gateway app, ServiceDesk.Access, tenant-wide consent; named value mcp-gateway-app-id
      connections    setup app (Graph); id-prov (ARM)        OAuth connections servicedesk-read and servicedesk-write; redirect URLs
      purviewapp     setup app (Graph); id-prov (Key Vault)  Purview integration app; its secret as purview-client-secret
      purview        setup app (Security & Compliance)       label and publishing policy, DLP policy for the MCP server's app, role groups
      environment    setup app or CloudLabs SP (Power Platform)  managed developer environment, application users, technicians
      schema         id-prov (Dataverse)                     Service Desk tables, app, views (Deploy-ServiceDeskSchema.ps1, data author)
      security       id-prov (Dataverse)                     roles, business unit, column security, auditing (Set-DataverseSecurity.ps1)
      seed           id-prov (Dataverse)                     seed data anchored to now; the label on the configuration document
      export         id-prov (Dataverse, Blob)               search export, export manifest, sample documents
      incidents      id-prov (Dataverse)                     the two new incidents (after the export, so never indexed)
      agent          id-prov (Foundry, APIM)                 msp-support-agent with both MCP tools; named value agent-id
      mcp            id-prov (Container Registry, Container App)  image build, baseline revision, Git working copy, tools
      tracing        id-prov (Resource Manager)              the Application Insights project connection (agent tracing)
      readiness      id-prov                                 Test-LabReadiness.ps1 -Mode Provisioning; consistency report
      finalize       setup app; id-prov                      participant's directory roles removed, id-prov reduced, setup app stripped

    Bootstrap identity (-Bootstrap Auto picks the first that is available):
      ServicePrincipal  a per-tenant service principal supplied by CloudLabs (preferred); its secret
                        reaches the VM through Key Vault (setup-bootstrap-secret) and is deleted at the end
      Password          the ODL user, a Global Administrator during provisioning, with the password
                        passed by psscript-01.ps1 in MSPLAB_SIGNIN_SECRET (fails for a Temporary Access Pass)
      AzureCli          the current 'az login' session of a supplier Global Administrator (support re-runs)

    Support re-runs (PowerShell 7 as administrator on the lab VM, after 'az login --tenant <tenant>'
    as a supplier Global Administrator who is also Owner of the subscription), for example:
      .\Provision-ServiceDesk.ps1 -DeploymentID <id> -AzureUserName <ODL user> -AzureTenantID <tenant> `
          -AzureSubscriptionID <subscription> -Bootstrap AzureCli -Steps restore-roles,connections,finalize
    restore-roles (support only) gives id-prov back its provisioning-only roles; finalize removes them
    again. The bootstrap step is added automatically when a requested step needs the setup app.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DeploymentID,
    [Parameter(Mandatory)][string]$AzureUserName,
    [Parameter(Mandatory)][string]$AzureTenantID,
    [Parameter(Mandatory)][string]$AzureSubscriptionID,
    [string]$ProvisioningIdentityClientId,
    [ValidateSet('Auto', 'ServicePrincipal', 'Password', 'AzureCli')][string]$Bootstrap = 'Auto',
    [string[]]$Steps = @('prerequisites', 'bootstrap', 'users', 'gateway', 'connections', 'purviewapp', 'purview', 'environment', 'schema',
                         'security', 'seed', 'export', 'incidents', 'agent', 'mcp', 'tracing', 'readiness', 'finalize'),
    # Support: re-anchor the data to this week (seed with --reset, export, incidents, readiness), with
    # restore-roles, bootstrap and finalize around it. Needs -Bootstrap AzureCli and an Owner's az login.
    [switch]$ResetData
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$labFiles = 'C:\LabFiles'
if ($ProvisioningIdentityClientId) { $env:MSPLAB_PROVISIONING_CLIENT_ID = $ProvisioningIdentityClientId }
Import-Module (Join-Path $root 'MspLab.Common.psm1') -Force
Import-Module (Join-Path $root 'entra\MspLab.Entra.psm1') -Force
$config = Get-LabConfig
New-Item -ItemType Directory -Path 'C:\WindowsAzure\Logs' -Force | Out-Null
Start-Transcript -Path 'C:\WindowsAzure\Logs\MspProvisioning.txt' -Append | Out-Null
# Tools installed by psscript-01.ps1 in this boot are not on the inherited PATH yet.
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

$all = @('prerequisites', 'restore-roles', 'bootstrap', 'users', 'gateway', 'connections', 'purviewapp', 'purview', 'environment', 'schema',
         'security', 'seed', 'export', 'incidents', 'agent', 'mcp', 'tracing', 'readiness', 'finalize')
if ($ResetData) { $Steps = @('prerequisites', 'restore-roles', 'bootstrap', 'seed', 'export', 'incidents', 'readiness', 'finalize') }
$unknown = @($Steps | Where-Object { $_ -notin $all })
if ($unknown) { throw "Unknown step(s): $($unknown -join ', '). Steps: $($all -join ', ')" }
$needsSetupApp = 'users', 'gateway', 'connections', 'purviewapp', 'purview', 'environment', 'finalize'
$setupInfo = Get-SetupAppInfo
if (@($Steps | Where-Object { $_ -in $needsSetupApp }).Count -and $Steps -notcontains 'bootstrap' -and
    (-not $setupInfo -or $setupInfo.stripped -or -not (Get-SetupAppCertificate))) {
    Write-Step 'The setup app is not available (stripped at the end of the last run); the bootstrap step runs first.'
    $Steps = @('bootstrap') + $Steps
}
if ($Steps -notcontains 'prerequisites') { $Steps = @('prerequisites') + $Steps }
$selected = @($all | Where-Object { $_ -in $Steps })
$failed = New-Object System.Collections.Generic.List[string]
$exitCode = 1
$python = @((Get-Command python -ErrorAction SilentlyContinue).Source, 'C:\Program Files\Python312\python.exe', 'C:\Python312\python.exe') |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
$settingsPath = Join-Path $labFiles 'lab-settings.json'
$seedData = Join-Path $labFiles 'seed\data'
$tenantDomain = ($AzureUserName -split '@')[-1]

function Invoke-Step {
    param([Parameter(Mandatory)][string]$Name, [string[]]$DependsOn = @(), [Parameter(Mandatory)][scriptblock]$Body)
    if ($Name -notin $selected) { return }
    $blocked = @($DependsOn | Where-Object { $failed.Contains($_) })
    if ($blocked.Count) {
        Set-StepStatus -Step $Name -State Skipped -Detail "Not run: it needs $($blocked -join ', '), which did not succeed."
        Write-Step "=== $Name skipped: needs $($blocked -join ', ')"
        $failed.Add($Name)
        return
    }
    Write-Step "=== $Name"
    Set-StepStatus -Step $Name -State Running
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $detail = & $Body
        Set-StepStatus -Step $Name -State Succeeded -Detail ([string]($detail -join ' ')) -Seconds $watch.Elapsed.TotalSeconds
        Write-Step "=== $Name succeeded in $([math]::Round($watch.Elapsed.TotalMinutes, 1)) min: $(ConvertTo-SafeText ([string]($detail -join ' ')) 300)"
    }
    catch {
        $message = ConvertTo-SafeText $_.Exception.Message 800
        Set-StepStatus -Step $Name -State Failed -Detail $message -Seconds $watch.Elapsed.TotalSeconds
        Write-Step "=== $Name FAILED: $message"
        Write-Step ($_.ScriptStackTrace -split "`n" | Select-Object -First 3 | Out-String)
        $failed.Add($Name)
    }
}

function Get-Settings { Read-LabSettings -Path $settingsPath }
function Save-Settings([System.Collections.IDictionary]$Values) { $null = Update-LabSettings -Values $Values -Path $settingsPath }
function Get-GraphToken { Get-SetupAppToken -Resource 'https://graph.microsoft.com' }
function New-StableGuid([string]$Text) {
    $hash = [Security.Cryptography.MD5]::HashData([Text.Encoding]::UTF8.GetBytes($Text))
    return [guid]::new($hash).ToString()
}
function Get-RgPath { "/subscriptions/$AzureSubscriptionID/resourceGroups/$((Get-Settings).ResourceGroup)" }

function Set-ApimNamedValue([string]$Name, [string]$Value) {
    $s = Get-Settings
    $path = "$(Get-RgPath)/providers/Microsoft.ApiManagement/service/$($s.ApimName)/namedValues/$Name"
    $current = Invoke-Arm -Method GET -Path $path -ApiVersion $config.ApimApiVersion -AllowNotFound
    if ($current.Status -ne 404 -and [string]$current.Body.properties.value -eq $Value) { return 'unchanged' }
    $null = Invoke-Arm -Method PUT -Path $path -ApiVersion $config.ApimApiVersion -Wait -Body @{
        properties = @{ displayName = $Name; value = $Value; secret = $false; tags = @('set-by-provisioning') } }
    return 'set'
}

function Invoke-Seed([string[]]$Arguments) {
    if (-not $python) { throw 'Python 3.12 is not installed (psscript-01.ps1 installs it).' }
    $s = Get-Settings
    $env:MSPLAB_DATAVERSE_TOKEN = Get-DataverseToken -OrgUrl $s.DataverseUrl -Fresh
    try {
        & $python (Join-Path $labFiles 'seed\load_seed.py') --url $s.DataverseUrl --data $seedData @Arguments | ForEach-Object { Write-Host $_ }
        $code = $LASTEXITCODE
    }
    finally { Remove-Item Env:\MSPLAB_DATAVERSE_TOKEN -ErrorAction SilentlyContinue }
    if ($code) { throw "load_seed.py reported errors (exit $code); see $seedData\load-summary.json." }
}

function Get-ProvisioningPrincipalId {
    $s = Get-Settings
    if ($s.ProvisioningPrincipalId) { return $s.ProvisioningPrincipalId }
    $identity = (Invoke-Arm -Method GET -Path "$(Get-RgPath)/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-prov-$DeploymentID" -ApiVersion '2024-11-30').Body
    Save-Settings @{ ProvisioningPrincipalId = $identity.properties.principalId }
    return $identity.properties.principalId
}

function Get-ProvisioningOnlyScopes {
    # The provisioning-only role assignments of id-prov (roles.bicep): role definition ID and scope.
    $s = Get-Settings
    $rg = Get-RgPath
    return @(
        @{ Role = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'; Name = 'Storage Blob Data Contributor'; Scope = "$rg/providers/Microsoft.Storage/storageAccounts/$($s.StorageAccount)" },
        @{ Role = 'eadc314b-1a2d-4efa-be10-5d325db5065e'; Name = 'Foundry Project Manager'; Scope = "$rg/providers/Microsoft.CognitiveServices/accounts/$($s.FoundryResource)/projects/$($s.FoundryProject)" },
        @{ Role = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'; Name = 'Key Vault Secrets Officer'; Scope = "$rg/providers/Microsoft.KeyVault/vaults/$($s.KeyVault)" },
        @{ Role = '312a565d-c81f-4fd8-895a-4e21e48d571c'; Name = 'API Management Service Contributor'; Scope = "$rg/providers/Microsoft.ApiManagement/service/$($s.ApimName)" },
        @{ Role = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'; Name = 'Role Based Access Control Administrator (conditional)'; Scope = $rg }
    )
}

function Set-ProvisioningDataverseRoles([switch]$Elevate) {
    # As the setup app (System Administrator application user): id-prov holds System Administrator while
    # provisioning writes data (-Elevate), and afterwards exactly the roles in security.json
    # (assignments.provisioningApplicationUser: Service Desk Agent Read and Service Desk Readiness Read).
    $s = Get-Settings
    $dv = $s.DataverseUrl
    $security = Get-Content (Join-Path $root 'dataverse\security.json') -Raw | ConvertFrom-Json
    $wantedNames = if ($Elevate) { @('System Administrator') } else { @($security.assignments.provisioningApplicationUser) }
    $env:MSPLAB_DATAVERSE_TOKEN_SOURCE = 'SetupApp'
    try {
        $user = (Invoke-Dataverse -OrgUrl $dv -Method GET -Path "systemusers?`$select=systemuserid&`$filter=applicationid eq $($s.ProvisioningIdentityClientId)").Body.value | Select-Object -First 1
        $rootBu = ((Invoke-Dataverse -OrgUrl $dv -Method GET -Path 'businessunits?$select=businessunitid&$filter=_parentbusinessunitid_value eq null').Body.value | Select-Object -First 1).businessunitid
        if (-not $user) { throw 'the id-prov application user was not found' }
        $wanted = foreach ($name in $wantedNames) {
            $role = (Invoke-Dataverse -OrgUrl $dv -Method GET -Path "roles?`$select=roleid&`$filter=name eq '$name' and _businessunitid_value eq $rootBu").Body.value | Select-Object -First 1
            if (-not $role) { throw "the role '$name' was not found" }
            $role.roleid
        }
        $held = @((Invoke-Dataverse -OrgUrl $dv -Method GET -Path "systemusers($($user.systemuserid))/systemuserroles_association?`$select=roleid,name").Body.value)
        foreach ($roleId in $wanted) {
            if ($held.roleid -notcontains $roleId) {
                $null = Invoke-Dataverse -OrgUrl $dv -Method POST -Path "systemusers($($user.systemuserid))/systemuserroles_association/`$ref" -Body @{ '@odata.id' = "$dv/api/data/v9.2/roles($roleId)" }
            }
        }
        if (-not $Elevate) {
            foreach ($role in ($held | Where-Object { $_.roleid -notin $wanted })) {
                $null = Invoke-Dataverse -OrgUrl $dv -Method DELETE -Path "systemusers($($user.systemuserid))/systemuserroles_association($($role.roleid))/`$ref"
            }
        }
        return ($wantedNames -join ' and ')
    }
    finally { Remove-Item Env:\MSPLAB_DATAVERSE_TOKEN_SOURCE -ErrorAction SilentlyContinue }
}

function Get-SupportArmToken {
    # The support engineer's own Azure CLI session (restore-roles and the finalize fallback).
    $json = & az account get-access-token --resource 'https://management.azure.com/' --tenant $AzureTenantID --output json 2>$null
    if ($LASTEXITCODE -or -not $json) { return $null }
    return ($json | ConvertFrom-Json).accessToken
}

try {
    Write-Step "Provisioning $DeploymentID, steps: $($selected -join ', ')"

    # ==== prerequisites
    Invoke-Step 'prerequisites' @() {
        $meta = Get-VmMetadata
        $rg = $meta.resourceGroupName
        $clientId = Get-ProvisioningClientId
        $wantedTypes = 'Microsoft.CognitiveServices/accounts', 'Microsoft.Search/searchServices', 'Microsoft.Storage/storageAccounts',
            'Microsoft.ApiManagement/service', 'Microsoft.App/containerApps', 'Microsoft.App/managedEnvironments', 'Microsoft.ContainerRegistry/registries',
            'Microsoft.KeyVault/vaults', 'Microsoft.OperationalInsights/workspaces', 'Microsoft.Insights/components', 'Microsoft.ManagedIdentity/userAssignedIdentities'
        # Role assignments made by the template can take minutes to apply to id-prov.
        $resources = Invoke-WithRetry -What 'list the environment resources' -Attempts 30 -DelaySeconds 30 -Action {
            $list = @((Invoke-Arm -Method GET -Path "/subscriptions/$AzureSubscriptionID/resourceGroups/$rg/resources" -ApiVersion '2021-04-01').Body.value)
            $missing = @($wantedTypes | Where-Object { $_ -notin $list.type })
            if ($missing.Count) { throw "not visible yet: $($missing -join ', ')" }
            $list
        }
        function NameOf([string]$type, [string]$prefix = '') {
            ($resources | Where-Object { $_.type -eq $type -and $_.name -like "$prefix*" } | Select-Object -First 1).name
        }
        $rgPath = "/subscriptions/$AzureSubscriptionID/resourceGroups/$rg"
        $foundry = NameOf 'Microsoft.CognitiveServices/accounts' 'aif-msp-'
        $project = "proj-msp-$DeploymentID"
        $apim = NameOf 'Microsoft.ApiManagement/service'
        $app = NameOf 'Microsoft.App/containerApps'
        $acr = NameOf 'Microsoft.ContainerRegistry/registries'
        $kv = NameOf 'Microsoft.KeyVault/vaults'
        $search = NameOf 'Microsoft.Search/searchServices'
        $workspace = NameOf 'Microsoft.OperationalInsights/workspaces'
        $apimBody = (Invoke-Arm -Method GET -Path "$rgPath/providers/Microsoft.ApiManagement/service/$apim" -ApiVersion $config.ApimApiVersion).Body
        $gateway = ([string]$apimBody.properties.gatewayUrl).TrimEnd('/')
        $appBody = (Invoke-Arm -Method GET -Path "$rgPath/providers/Microsoft.App/containerApps/$app" -ApiVersion '2026-07-01').Body
        $acrBody = (Invoke-Arm -Method GET -Path "$rgPath/providers/Microsoft.ContainerRegistry/registries/$acr" -ApiVersion '2025-05-01-preview').Body
        $kvBody = (Invoke-Arm -Method GET -Path "$rgPath/providers/Microsoft.KeyVault/vaults/$kv" -ApiVersion '2026-02-01').Body
        $laBody = (Invoke-Arm -Method GET -Path "$rgPath/providers/Microsoft.OperationalInsights/workspaces/$workspace" -ApiVersion '2025-02-01').Body
        $mcpIdentity = (Invoke-Arm -Method GET -Path "$rgPath/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-mcp-$DeploymentID" -ApiVersion '2024-11-30').Body
        $provIdentity = (Invoke-Arm -Method GET -Path "$rgPath/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-prov-$DeploymentID" -ApiVersion '2024-11-30').Body
        $existing = Get-Settings
        $dataverseUrl = if ($existing.DataverseUrl) { $existing.DataverseUrl } else { Get-LabTag 'msplab-dataverse-url' "https://mspdesk$DeploymentID.crm3.dynamics.com" }
        $values = [ordered]@{
            DeploymentID = $DeploymentID; TenantId = $AzureTenantID; SubscriptionId = $AzureSubscriptionID; ResourceGroup = $rg; Region = $meta.location
            SeniorUser = $AzureUserName; SeniorUserObjectId = (Get-LabTag 'msplab-senior-oid' ([string]$existing.SeniorUserObjectId))
            Tier1User = (Get-LabTag 'msplab-tier1-upn' "tier1.technician@$tenantDomain"); Tier1UserObjectId = [string]$existing.Tier1UserObjectId
            FoundryResource = $foundry; FoundryProject = $project
            FoundryProjectEndpoint = "https://$foundry.services.ai.azure.com/api/projects/$project"
            ChatDeployment = $config.ChatDeployment; EmbeddingDeployment = $config.EmbeddingDeployment
            AgentName = $config.AgentName; AgentId = [string]$existing.AgentId; AgentIdentityObjectId = [string]$existing.AgentIdentityObjectId
            SearchService = $search; SearchEndpoint = "https://$search.search.windows.net"; SearchIndex = $config.SearchIndex
            StorageAccount = (NameOf 'Microsoft.Storage/storageAccounts' 'stmsp'); ExportContainer = $config.ExportContainer
            ExportMetaContainer = $config.ExportMetaContainer
            ApimName = $apim; McpReadGatewayUrl = "$gateway/$($config.ReadApi)/mcp"; McpWriteGatewayUrl = "$gateway/$($config.WriteApi)/mcp"
            McpDiagnosticsUrl = "$gateway/$($config.DiagApi)/mcp"; ApimDiagnosticsSubscription = $config.DiagSubscription
            ApimDiagnosticsKeySecret = 'apim-diagnostics-key'
            McpReadConnection = $config.ReadConnection; McpWriteConnection = $config.WriteConnection
            McpGatewayAppId = [string]$existing.McpGatewayAppId; McpGatewayAudience = "https://$tenantDomain/servicedesk-mcp"
            McpGatewayScope = $config.GatewayScope
            ContainerApp = $app; ContainerRegistry = $acr; ContainerRegistryLoginServer = [string]$acrBody.properties.loginServer
            McpServerUrl = "https://$($appBody.properties.configuration.ingress.fqdn)"; McpRelease = $config.McpRelease
            McpBackendIdentityName = "id-mcp-$DeploymentID"; McpBackendIdentityClientId = [string]$mcpIdentity.properties.clientId
            ProvisioningIdentityClientId = $clientId; ProvisioningPrincipalId = [string]$provIdentity.properties.principalId
            KeyVault = $kv; KeyVaultUrl = [string]$kvBody.properties.vaultUri
            LogAnalyticsWorkspace = $workspace; LogAnalyticsWorkspaceId = [string]$laBody.properties.customerId
            AppInsights = (NameOf 'Microsoft.Insights/components')
            DataverseUrl = $dataverseUrl; ServiceDeskAppUrl = "$dataverseUrl/main.aspx?appname=$($config.Dataverse.AppUniqueName)"
            SensitivityLabelId = [string]$existing.SensitivityLabelId; SensitivityLabelName = $config.Purview.LabelDisplayName
            Purview = $(if ($existing.Purview) { $existing.Purview } else { 'not configured yet' })
            GoldenEnvironmentVersion = $config.GoldenEnvironmentVersion
            McpServerSource = (Join-Path $labFiles 'mcp-server'); SeedManifest = (Join-Path $seedData 'manifest.json')
            ExportManifest = (Join-Path $labFiles 'search\export-manifest.json'); ReadinessReport = (Join-Path $labFiles 'readiness\consistency-report.json')
        }
        Save-Settings $values
        "lab-settings.json written for $rg ($(@($resources).Count) resources; MCP server $($values.McpServerUrl))"
    }

    # ==== restore-roles (support only: after finalize, before re-running steps that need them)
    Invoke-Step 'restore-roles' @('prerequisites') {
        $token = Get-SupportArmToken
        if (-not $token) { throw "No Azure CLI session. Run 'az login --tenant $AzureTenantID' as an Owner of the subscription first." }
        $principalId = Get-ProvisioningPrincipalId
        $restored = @()
        foreach ($item in (Get-ProvisioningOnlyScopes | Where-Object { $_.Role -ne 'f58310d9-a9f6-439a-9e8d-f62e7b41a168' })) {
            $id = New-StableGuid "$($item.Scope)|$principalId|$($item.Role)|restore"
            $r = Invoke-LabRest -Method PUT -Token $token -AllowStatus 409 `
                -Uri "https://management.azure.com$($item.Scope)/providers/Microsoft.Authorization/roleAssignments/$($id)?api-version=2022-04-01" `
                -Body @{ properties = @{ roleDefinitionId = "/subscriptions/$AzureSubscriptionID/providers/Microsoft.Authorization/roleDefinitions/$($item.Role)"
                                         principalId = $principalId; principalType = 'ServicePrincipal'
                                         description = 'id-prov (support re-run; removed again by finalize).' } }
            $restored += "$($item.Name)$(if ($r.Status -eq 409) { ' (existing)' })"
        }
        Write-Step '  role assignments take up to 10 minutes to apply; managed identity tokens issued before keep the old rights'
        "restored for id-prov: $($restored -join ', ')"
    }

    # ==== bootstrap
    Invoke-Step 'bootstrap' @('prerequisites') {
        $s = Get-Settings
        $context = Resolve-BootstrapContext -Mode $Bootstrap -TenantId $AzureTenantID -UserName $AzureUserName -VaultUri $s.KeyVaultUrl
        Write-Step "  bootstrap identity: $($context.Reason)"
        $result = Initialize-SetupApp -Context $context -DeploymentId $DeploymentID -ProvisioningClientId (Get-ProvisioningClientId)
        if ($result.PowerPlatform -ne 'registered') { Write-Step "  WARNING: the setup app is not registered with Power Platform: $($result.PowerPlatformNote)" }
        "setup app $($result.AppId) ($($context.Mode)); Exchange.ManageAsApp on $($result.Exchange); roles $($result.Roles); Power Platform $($result.PowerPlatform)"
    }

    # ==== users
    Invoke-Step 'users' @('bootstrap') {
        $s = Get-Settings
        $graph = Get-GraphToken
        $senior = Resolve-LabUser -Id $(if ($s.SeniorUserObjectId) { $s.SeniorUserObjectId } else { $AzureUserName }) -Token $graph -WaitMinutes 5
        $tier1 = Resolve-LabUser -Id $s.Tier1User -Token $graph -WaitMinutes $config.UserWaitMinutes
        foreach ($u in @($senior, $tier1)) {
            if (-not $u.Enabled) { throw "$($u.UserPrincipalName) is disabled." }
            $plans = @($u.ServicePlans)
            if (-not ($plans -match '^(CDS|DYN365_CDS|POWERAPPS)')) { Write-Step "  WARNING: $($u.UserPrincipalName) has no license that includes Dataverse yet (SKUs: $($u.Skus -join ', '))" }
        }
        Save-Settings @{ SeniorUser = $senior.UserPrincipalName; SeniorUserObjectId = $senior.Id; Tier1User = $tier1.UserPrincipalName; Tier1UserObjectId = $tier1.Id }
        # Tier 1 Foundry role at project scope, by id-prov (its conditional role assignment administrator role
        # allows only Foundry Agent Consumer or Foundry User, only for users).
        $roleName = Get-LabTag 'msplab-tier1-foundry-role' 'Foundry Agent Consumer'
        $roleId = if ($roleName -eq 'Foundry User') { '53ca6127-db72-4b80-b1b0-d745d6d5456d' } else { 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6' }
        $scope = "$(Get-RgPath)/providers/Microsoft.CognitiveServices/accounts/$($s.FoundryResource)/projects/$($s.FoundryProject)"
        $assignment = New-StableGuid "$scope|$($tier1.Id)|$roleId"
        $r = Invoke-WithRetry -What 'Tier 1 Foundry role' -Attempts 10 -DelaySeconds 30 -Action {
            Invoke-Arm -Method PUT -Path "$scope/providers/Microsoft.Authorization/roleAssignments/$assignment" -ApiVersion '2022-04-01' -AllowStatus 409 -Body @{
                properties = @{ roleDefinitionId = "/subscriptions/$AzureSubscriptionID/providers/Microsoft.Authorization/roleDefinitions/$roleId"
                                principalId = $tier1.Id; principalType = 'User'; description = 'Tier 1 Technician: chats with the agent (lab baseline).' } }
        }
        "Senior $($senior.UserPrincipalName) ($($senior.Skus -join ', ')); Tier 1 $($tier1.UserPrincipalName) ($($tier1.Skus -join ', ')), $roleName on the project$(if ($r.Status -eq 409) { ' (existing)' })"
    }

    # ==== gateway
    Invoke-Step 'gateway' @('bootstrap') {
        $s = Get-Settings
        $redirects = @((Get-LabTag 'msplab-oauth-redirect-uris') -split '[,; ]+' | Where-Object { $_ -match '^https://' })
        $gateway = Set-GatewayApp -Token (Get-GraphToken) -Audience $s.McpGatewayAudience -RedirectUris $redirects
        Save-Settings @{ McpGatewayAppId = $gateway.AppId; McpGatewayAppObjectId = $gateway.ObjectId }
        $state = Invoke-WithRetry -What 'API Management named value mcp-gateway-app-id' -Attempts 6 -DelaySeconds 30 -Action { Set-ApimNamedValue 'mcp-gateway-app-id' $gateway.AppId }
        "gateway app $($gateway.AppId), identifier URIs $($gateway.IdentifierUris -join ', '), scope $($config.GatewayScope) consented for the tenant; named value mcp-gateway-app-id $state"
    }

    # ==== connections
    Invoke-Step 'connections' @('gateway') {
        $s = Get-Settings
        $extra = @((Get-LabTag 'msplab-oauth-redirect-uris') -split '[,; ]+' | Where-Object { $_ -match '^https://' })
        $result = & (Join-Path $root 'foundry\New-McpConnections.ps1') -SubscriptionId $AzureSubscriptionID -ResourceGroup $s.ResourceGroup `
            -FoundryResource $s.FoundryResource -FoundryProject $s.FoundryProject -TenantId $AzureTenantID -GatewayAppId $s.McpGatewayAppId `
            -GatewayAppObjectId $s.McpGatewayAppObjectId -Audience $s.McpGatewayAudience -ReadGatewayUrl $s.McpReadGatewayUrl `
            -WriteGatewayUrl $s.McpWriteGatewayUrl -ExtraRedirectUris $extra
        Save-Settings @{ McpConnectionSecretExpires = $result.SecretExpires; McpConnectionRedirectUris = @($result.RedirectUris) }
        if (-not @($result.RedirectUris).Count) {
            throw ('Both connections exist, but no OAuth redirect URL was found in their responses and the template parameter oauthRedirectUris is empty, ' +
                   'so consent would fail with AADSTS50011. Register it as setup/tenant/RUNBOOK.md, Register the OAuth redirect URL, describes.')
        }
        "connections $(@($result.Connections.Name) -join ', ') (OAuth2, scopes $($result.Scopes)); secret expires $($result.SecretExpires); redirect URIs $(@($result.RedirectUris).Count)"
    }

    # ==== purviewapp
    Invoke-Step 'purviewapp' @('bootstrap') {
        $s = Get-Settings
        $graph = Get-GraphToken
        $app = Set-PurviewApp -Token $graph
        $secret = New-AppPassword -AppObjectId $app.ObjectId -DisplayName 'MCP server (Key Vault purview-client-secret)' -Token $graph -Days $config.SecretLifetimeDays
        Set-KeyVaultSecret -VaultUri $s.KeyVaultUrl -Name 'purview-client-secret' -Value $secret.Value -ContentType "Client secret of $($config.PurviewAppName)" `
            -ExpiresInDays $config.SecretLifetimeDays
        Save-Settings @{ PurviewAppId = $app.AppId }
        "Purview app $($app.AppId) ($($app.Permissions -join ', ')); secret in Key Vault as purview-client-secret"
    }

    # ==== purview
    Invoke-Step 'purview' @('purviewapp') {
        $s = Get-Settings
        $result = & (Join-Path $root 'purview\Set-PurviewProtection.ps1') -PurviewAppId $s.PurviewAppId -SeniorUserPrincipalName $s.SeniorUser
        $summary = "label $($result.LabelDisplayName) ($($result.LabelGuid)) published by '$($result.LabelPolicy)'; DLP policy '$($result.DlpPolicy)' ($($result.DlpMode)) " +
                   "with rule '$($result.DlpRule)'; role groups $($result.RoleGroups -join ', ')"
        Save-Settings @{ SensitivityLabelId = [string]$result.LabelGuid; SensitivityLabelName = $result.LabelDisplayName; Purview = $summary; PurviewDlpPolicy = $result.DlpPolicy }
        $summary
    }

    # ==== environment
    Invoke-Step 'environment' @('bootstrap', 'users') {
        $s = Get-Settings
        $info = Get-SetupAppInfo
        $result = & (Join-Path $root 'powerplatform\New-ManagedDeveloperEnvironment.ps1') -DeploymentId $DeploymentID -TenantId $AzureTenantID `
            -SeniorObjectId $s.SeniorUserObjectId -Location (Get-LabTag 'msplab-dataverse-location' 'canada') `
            -DomainName (Get-LabTag 'msplab-dataverse-domain' "mspdesk$DeploymentID") `
            -AppUserClientIds @($info.appId, $s.ProvisioningIdentityClientId, $s.McpBackendIdentityClientId) `
            -UserObjectIds @($s.SeniorUserObjectId, $s.Tier1UserObjectId) -WaitMinutes $config.Dataverse.WaitMinutes -UserWaitMinutes $config.UserWaitMinutes
        Save-Settings @{ DataverseUrl = $result.InstanceUrl; ServiceDeskAppUrl = "$($result.InstanceUrl)/main.aspx?appname=$($config.Dataverse.AppUniqueName)"
                         DataverseEnvironmentId = $result.EnvironmentId; DataverseEnvironmentSku = $result.Sku }
        "$($result.DisplayName): $($result.InstanceUrl) ($($result.Sku), protection $($result.ProtectionLevel), used by $($result.UsedBy)); $($result.TenantSetting)"
    }

    # ==== schema (the data author's script)
    Invoke-Step 'schema' @('environment') {
        $s = Get-Settings
        & (Join-Path $root 'dataverse\Deploy-ServiceDeskSchema.ps1') -OrgUrl $s.DataverseUrl | ForEach-Object { Write-Host $_ }
        'Service Desk schema, app and views in place'
    }

    # ==== security
    Invoke-Step 'security' @('schema', 'users') {
        $s = Get-Settings
        $result = & (Join-Path $root 'dataverse\Set-DataverseSecurity.ps1') -OrgUrl $s.DataverseUrl -McpIdentityClientId $s.McpBackendIdentityClientId `
            -SeniorObjectId $s.SeniorUserObjectId -Tier1ObjectId $s.Tier1UserObjectId `
            -SeniorSystemAdministrator:((Get-LabTag 'msplab-senior-dataverse-sysadmin' 'false') -eq 'true') -AppUniqueName $config.Dataverse.AppUniqueName
        $warnings = @($result.Warnings)
        "MCP app user: $($result.McpRoles -join ', '); Senior: $($result.SeniorRoles -join ', '); Tier 1: $($result.Tier1Roles -join ', ')" +
            $(if ($warnings.Count) { "; warnings: $($warnings -join ' | ')" } else { '' })
    }

    # ==== seed
    Invoke-Step 'seed' @('security') {
        if (-not $python) { throw 'Python 3.12 is not installed.' }
        if ($ResetData) { Write-Step "  id-prov in Dataverse: $(Set-ProvisioningDataverseRoles -Elevate) (until finalize)" }
        $s = Get-Settings
        & $python (Join-Path $labFiles 'seed\generate_seed.py') --out $seedData --anchor auto | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE) { throw "generate_seed.py failed ($LASTEXITCODE)" }
        $arguments = @()
        if ($ResetData) { $arguments += '--reset' }
        if ($s.SensitivityLabelId) { $arguments += @('--label-id', $s.SensitivityLabelId, '--label-name', $s.SensitivityLabelName, '--tenant-id', $AzureTenantID) }
        else { Write-Step '  WARNING: no sensitivity label yet (purview step); the configuration document is loaded without a label' }
        Invoke-Seed $arguments
        $manifest = Get-Content (Join-Path $seedData 'manifest.json') -Raw | ConvertFrom-Json
        "seed $($manifest.data_version) anchored at $($manifest.anchor): $($manifest.counts.tickets) tickets, $($manifest.counts.customerdocuments) customer documents$(if ($s.SensitivityLabelId) { ', configuration document labeled' } else { ', NO label' })"
    }

    # ==== export
    Invoke-Step 'export' @('seed') {
        $result = & (Join-Path $root 'export\Export-SearchContent.ps1') -SettingsPath $settingsPath -SeedManifestPath (Join-Path $seedData 'manifest.json')
        "exported $($result.Documents) documents to $($result.Container); manifest $($result.Manifest); samples $($result.Samples -join ', ')"
    }

    # ==== incidents
    Invoke-Step 'incidents' @('export') {
        Invoke-Seed @('--only', 'newincidents')
        'new incidents loaded: ' + ((Get-Content (Join-Path $seedData 'manifest.json') -Raw | ConvertFrom-Json).new_incidents -join ', ')
    }

    # ==== agent
    Invoke-Step 'agent' @('gateway') {
        $s = Get-Settings
        # The connections step may have failed only for the redirect URL; the agent needs the connections to exist.
        foreach ($name in $s.McpReadConnection, $s.McpWriteConnection) {
            $found = $false
            foreach ($apiVersion in $config.ConnectionApiVersions) {
                try { $found = (Invoke-Arm -Method GET -ApiVersion $apiVersion -AllowNotFound `
                        -Path "$(Get-RgPath)/providers/Microsoft.CognitiveServices/accounts/$($s.FoundryResource)/projects/$($s.FoundryProject)/connections/$name").Status -eq 200 }
                catch { $found = $false }
                if ($found) { break }
            }
            if (-not $found) { throw "The project connection $name does not exist; run the connections step first." }
        }
        $agent = & (Join-Path $root 'foundry\New-SupportAgent.ps1') -ProjectEndpoint $s.FoundryProjectEndpoint -AgentName $s.AgentName `
            -ModelDeployment $s.ChatDeployment -InstructionsPath (Join-Path $labFiles 'agent\instructions-baseline.md') `
            -ReadGatewayUrl $s.McpReadGatewayUrl -WriteGatewayUrl $s.McpWriteGatewayUrl -ReadConnection $s.McpReadConnection `
            -WriteConnection $s.McpWriteConnection -ReadTools $config.ReadTools -ReasoningEffort $config.ReasoningEffort
        Save-Settings @{ AgentId = $agent.ClientId; AgentIdentityObjectId = $agent.ObjectId; AgentVersion = [string]$agent.Version }
        $state = Invoke-WithRetry -What 'API Management named value agent-id' -Attempts 6 -DelaySeconds 30 -Action { Set-ApimNamedValue 'agent-id' $agent.ClientId }
        "agent $($agent.AgentName) version $($agent.Version) ($($agent.Action)); Entra Agent ID $($agent.ClientId); named value agent-id $state"
    }

    # ==== mcp
    Invoke-Step 'mcp' @('prerequisites') {
        $s = Get-Settings
        $labels = if ($s.SensitivityLabelId) { "$($s.SensitivityLabelId),$($s.SensitivityLabelName)" } else { '' }
        $result = & (Join-Path $root 'mcp\Deploy-McpBaseline.ps1') -SettingsPath $settingsPath -PurviewClientId ([string]$s.PurviewAppId) -RestrictedLabels $labels
        Save-Settings @{ McpBaselineRevision = $result.ActiveRevision; McpImage = $result.Image }
        "$($result.Image) ($($result.Build)); revision $($result.ActiveRevision); version $($result.Version); gateway key from $($result.GatewayKeySource); $($result.WorkingCopy)"
    }

    # ==== tracing
    Invoke-Step 'tracing' @('prerequisites') {
        $s = Get-Settings
        $path = "$(Get-RgPath)/providers/Microsoft.CognitiveServices/accounts/$($s.FoundryResource)/projects/$($s.FoundryProject)/connections/$($config.AppInsightsConnection)"
        $connection = $null
        foreach ($apiVersion in $config.ConnectionApiVersions) {
            $r = Invoke-Arm -Method GET -Path $path -ApiVersion $apiVersion -AllowNotFound -AllowStatus 400
            if ($r.Status -eq 200) { $connection = $r.Body; break }
        }
        if (-not $connection) { throw "The project connection '$($config.AppInsightsConnection)' is missing; agent tracing would not reach Application Insights. Redeploy the template." }
        if ($connection.properties.category -ne 'AppInsights' -or $connection.properties.target -notlike "*/components/$($s.AppInsights)") {
            throw "The project connection '$($config.AppInsightsConnection)' is $($connection.properties.category) to $($connection.properties.target), not Application Insights $($s.AppInsights)."
        }
        "agent traces go to $($s.AppInsights) through the project connection '$($config.AppInsightsConnection)'"
    }

    # ==== readiness
    Invoke-Step 'readiness' @('prerequisites') {
        $report = & (Join-Path $labFiles 'tools\Test-LabReadiness.ps1') -Mode Provisioning -SettingsPath $settingsPath -PassThru
        $s = Get-Settings
        try {
            Set-BlobContent -Account $s.StorageAccount -Container $config.ExportMetaContainer -Name "readiness/$DeploymentID-consistency-report.json" `
                -Text (Get-Content $report.ReportPath -Raw)
        }
        catch { Write-Step "  WARNING: the consistency report was not copied to Blob storage: $($_.Exception.Message)" }
        $notReady = @($report.Components | Where-Object { $_.Status -ne 'Ready' })
        if ($notReady.Count) { throw "Not ready: $(($notReady | ForEach-Object { "$($_.Component): $($_.Detail)" }) -join '; ')" }
        "every component ready (Golden Environment $($report.GoldenEnvironmentVersion), fingerprint $($report.ShortFingerprint))"
    }

    # ==== finalize (no dependencies: it runs even after a failure, so no administrator right is left behind)
    $bootstrapFailed = $failed.Contains('bootstrap')
    Invoke-Step 'finalize' @() {
        $s = Get-Settings
        $info = Get-SetupAppInfo
        if ($bootstrapFailed -or -not $info -or $info.stripped) { throw 'The setup app is not available, so the participant''s Global Administrator role could not be removed. Do not hand this environment out: re-run with -Bootstrap AzureCli or replace it with a spare.' }
        $notes = @()
        $notesFailed = @()
        $graph = Get-GraphToken

        # 1. id-prov in Dataverse: from System Administrator to Service Desk Agent Read (as the setup app)
        $environmentExists = $s.DataverseEnvironmentId -or (Get-StepStatus)['environment'].state -eq 'Succeeded'
        if ($s.DataverseUrl -and $environmentExists) {
            try { $notes += "id-prov in Dataverse: $(Set-ProvisioningDataverseRoles) only" }
            catch { $notesFailed += "id-prov Dataverse roles: $($_.Exception.Message)" }
        }

        # 2. The participant's directory roles (the setup app removes them: nobody can remove their own)
        try {
            $requireOther = (Get-LabTag 'msplab-require-supplier-ga' 'true') -eq 'true'
            $removal = Remove-ParticipantAdministratorRoles -UserObjectId $s.SeniorUserObjectId -Token $graph -RequireOtherGlobalAdministrator:$requireOther
            $notes += "participant directory roles removed: $(if (@($removal.Removed).Count) { $removal.Removed -join ', ' } else { 'none held' })"
        }
        catch { $notesFailed += "participant directory roles: $($_.Exception.Message)" }

        # 3. The bootstrap service principal secret (kept until now for the Power Platform fallback)
        try { if (Get-KeyVaultSecret -VaultUri $s.KeyVaultUrl -Name 'setup-bootstrap-secret') { $null = Remove-KeyVaultSecret -VaultUri $s.KeyVaultUrl -Name 'setup-bootstrap-secret'; $notes += 'bootstrap secret deleted from Key Vault' } }
        catch { $notesFailed += "bootstrap secret: $($_.Exception.Message)" }

        # 4. A copy of the step results for CloudLabs (before id-prov loses Blob write)
        try { Set-BlobContent -Account $s.StorageAccount -Container $config.ExportMetaContainer -Name "readiness/$DeploymentID-provision-status.json" -Text (Get-Content 'C:\LabFiles\provision-status.json' -Raw) }
        catch { Write-Step "  WARNING: provision-status.json not copied to Blob: $($_.Exception.Message)" }

        # 5. id-prov's provisioning-only Azure roles (its conditional RBAC administrator role allows exactly this), that role last
        $principalId = Get-ProvisioningPrincipalId
        $removedRoles = @()
        $supportToken = $null
        foreach ($item in (Get-ProvisioningOnlyScopes)) {
            $list = Invoke-Arm -Method GET -Path "$($item.Scope)/providers/Microsoft.Authorization/roleAssignments?`$filter=principalId eq '$principalId'" -ApiVersion '2022-04-01'
            foreach ($a in @($list.Body.value | Where-Object { $_.properties.roleDefinitionId -like "*/$($item.Role)" -and $_.properties.scope -eq $item.Scope })) {
                try { $null = Invoke-Arm -Method DELETE -Path $a.id -ApiVersion '2022-04-01' -AllowNotFound }
                catch {
                    if (-not $supportToken) { $supportToken = Get-SupportArmToken }
                    if (-not $supportToken) { throw }
                    $null = Invoke-LabRest -Method DELETE -Uri "https://management.azure.com$($a.id)?api-version=2022-04-01" -Token $supportToken -AllowNotFound
                }
                $removedRoles += $item.Name
            }
        }
        $notes += "id-prov provisioning-only roles removed: $(if ($removedRoles.Count) { $removedRoles -join ', ' } else { 'none left' })"

        # 6. The setup app strips itself (one token issued before), then its certificate is deleted
        $strip = Remove-SetupAppPrivileges -Token $graph
        $info.stripped = $true
        $info.strippedOn = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Save-SetupAppInfo -Info $info
        # The key was created through Windows PowerShell (CryptoAPI), so it is deleted there too, with the certificate.
        & powershell.exe -NoProfile -NonInteractive -Command "Get-ChildItem 'Cert:\LocalMachine\My' | Where-Object { `$_.Thumbprint -eq '$($info.thumbprint)' } | Remove-Item -DeleteKey -Force" | Out-Null
        if (Test-Path "Cert:\LocalMachine\My\$($info.thumbprint)") { $notesFailed += "the setup certificate $($info.thumbprint) is still in Cert:\LocalMachine\My" }
        $notes += "setup app stripped: key credentials, directory roles ($(@($strip.DirectoryRoles) -join ', ')), $($strip.AppRoleAssignments) application permissions; certificate deleted"

        # 7. Verify with id-prov's read-only Graph rights
        $graphRead = Get-ManagedIdentityToken 'https://graph.microsoft.com' -Fresh
        $left = @(Get-DirectoryRoleAssignments -PrincipalId $s.SeniorUserObjectId -Token $graphRead)
        if ($left.Count) { $notesFailed += "the participant still holds: $($left.Role -join ', ')" } else { $notes += 'verified: the participant holds no directory role' }
        $app = (Invoke-Graph -Method GET -Path "applications/$($info.objectId)?`$select=keyCredentials,passwordCredentials" -Token $graphRead).Body
        if (@($app.keyCredentials).Count -or @($app.passwordCredentials).Count) { $notesFailed += 'the setup app still has credentials' } else { $notes += 'verified: the setup app has no credentials' }
        Save-Settings @{ ProvisionedOn = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        if ($notesFailed.Count) { throw "$($notesFailed -join ' | ') (done: $($notes -join '; '))" }
        $notes -join '; '
    }

    $overall = if ($failed.Count) { 'Failed' } else { 'Succeeded' }
    Set-StepStatus -Step 'overall' -State $overall -Detail $(if ($failed.Count) { "Steps not succeeded: $($failed -join ', ')" } else { "All steps succeeded: $($selected -join ', ')" })
    Write-Step "Provisioning $overall$(if ($failed.Count) { ': ' + ($failed -join ', ') })"
    $exitCode = if ($failed.Count) { 1 } else { 0 }
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
exit $exitCode
