#Requires -Version 7.0
<#
.SYNOPSIS
    One-time preparation of the CloudLabs tenant for the Agentic MSP Support Agent lab.
    Run once per tenant by a tenant administrator, before the first team deployment. Safe to
    re-run: it updates what exists.

.DESCRIPTION
    1. 'Relecloud Service Desk MCP Gateway' app registration. It defines the token audience
       api://<application id> and one delegated scope, ServiceDesk.Access, that every team's
       API Management gateway requires. It is also the OAuth client of each team's Foundry
       connection (OAuth identity passthrough), so it gets a client secret and the connection's
       redirect URL (-RedirectUri). The scope is admin-consented for the tenant, so technicians
       only see Foundry's own one-time authorization link.
    2. 'Relecloud Service Desk Purview Integration' app registration with the Microsoft Graph
       application permission Content.Process.All (admin-consented). Each team's MCP server
       uses it to send tool results to Microsoft Purview (processContent) for DLP decisions.
    3. Checks the Power Platform tenant settings and prints what else to set up by hand:
       the DLP policy, the sensitivity label and the licences (setup/README.md has the steps).

    Secrets are printed once, for the CloudLabs template's secure parameters
    (mcpOAuthClientSecret, purviewClientSecret). They are never written to disk.

    Needs: Microsoft Graph PowerShell (Microsoft.Graph.Applications) with Application.ReadWrite.All,
    DelegatedPermissionGrant.ReadWrite.All and AppRoleAssignment.ReadWrite.All, and
    Microsoft.PowerApps.Administration.PowerShell for the Power Platform checks (Windows
    PowerShell 5.1 runs that part).

.EXAMPLE
    .\Initialize-LabTenant.ps1 -TenantId <tenant id> -NewSecrets

.EXAMPLE
    .\Initialize-LabTenant.ps1 -TenantId <tenant id> -RedirectUri 'https://<redirect URL shown by Foundry>'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$TenantId,
    [string]$GatewayDisplayName = 'Relecloud Service Desk MCP Gateway',
    [string]$PurviewDisplayName = 'Relecloud Service Desk Purview Integration',
    # Redirect URL(s) of the Foundry OAuth connection. Foundry shows it when a connection is
    # created; add it here once (and again if a new region shows a different one).
    [string[]]$RedirectUri = @(),
    # Create new client secrets (print them once). Without it, existing secrets are kept.
    [switch]$NewSecrets,
    [int]$SecretMonths = 6
)

$ErrorActionPreference = 'Stop'

foreach ($module in 'Microsoft.Graph.Applications', 'Microsoft.Graph.Identity.SignIns') {
    if (-not (Get-Module -ListAvailable $module)) { Install-Module $module -Scope CurrentUser -Force }
    Import-Module $module
}
Connect-MgGraph -TenantId $TenantId -NoWelcome `
    -Scopes 'Application.ReadWrite.All', 'DelegatedPermissionGrant.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All'

function Get-OrCreateApp([string]$name, [hashtable]$properties) {
    $app = Get-MgApplication -Filter "displayName eq '$name'" -Top 1
    if (-not $app -and $PSCmdlet.ShouldProcess($name, 'Create app registration')) {
        $app = New-MgApplication -DisplayName $name -SignInAudience 'AzureADMyOrg' @properties
    }
    $sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -Top 1
    if (-not $sp) { $sp = New-MgServicePrincipal -AppId $app.AppId -AppRoleAssignmentRequired:$false }
    return @{ App = (Get-MgApplication -ApplicationId $app.Id); Sp = $sp }
}
function New-Secret($app, [string]$label) {
    $end = (Get-Date).AddMonths($SecretMonths)
    $secret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{ DisplayName = $label; EndDateTime = $end }
    return @{ Value = $secret.SecretText; Expires = $end }
}
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -Top 1

# ================================================================== 1. the MCP gateway app
$gateway = Get-OrCreateApp $GatewayDisplayName @{
    Notes = 'Token audience and OAuth client for the Agentic MSP Support Agent lab. Do not delete while labs are running.'
    Api   = @{ RequestedAccessTokenVersion = 2 }
}
$app = $gateway.App
$scope = $app.Api.Oauth2PermissionScopes | Where-Object { $_.Value -eq 'ServiceDesk.Access' } | Select-Object -First 1
$scopeId = if ($scope) { $scope.Id } else { [guid]::NewGuid().ToString() }
if (-not $scope) {
    $scopes = @($app.Api.Oauth2PermissionScopes) + @(@{
        Id = $scopeId; Type = 'Admin'; Value = 'ServiceDesk.Access'; IsEnabled = $true
        AdminConsentDisplayName = 'Use the Relecloud Service Desk tools as the signed-in technician'
        AdminConsentDescription = 'Lets the Service Desk agent call the Service Desk MCP gateway on behalf of the signed-in technician. Dataverse decides what each technician may do.'
        UserConsentDisplayName = 'Use the Service Desk tools as you'
        UserConsentDescription = 'Lets the Service Desk agent call the Service Desk tools on your behalf.'
    })
    Update-MgApplication -ApplicationId $app.Id -Api @{ RequestedAccessTokenVersion = 2; Oauth2PermissionScopes = $scopes }
}
$uris = @($app.Web.RedirectUris) + $RedirectUri | Where-Object { $_ } | Select-Object -Unique
Update-MgApplication -ApplicationId $app.Id -IdentifierUris @("api://$($app.AppId)") -Web @{ RedirectUris = @($uris) } `
    -RequiredResourceAccess @(
        @{ ResourceAppId = $app.AppId; ResourceAccess = @(@{ Id = $scopeId; Type = 'Scope' }) },
        @{ ResourceAppId = '00000003-0000-0000-c000-000000000000'; ResourceAccess = @(
            @{ Id = '37f7f235-527c-4136-accd-4a02d197296e'; Type = 'Scope' },   # openid
            @{ Id = '14dad69e-099b-42c9-810b-d002981feec1'; Type = 'Scope' },   # profile
            @{ Id = '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'; Type = 'Scope' }) }  # offline_access
    )
# Admin consent for every user: the gateway scope on the gateway itself, and sign-in scopes on Graph.
foreach ($grant in @(@{ Resource = $gateway.Sp.Id; Scope = 'ServiceDesk.Access' }, @{ Resource = $graphSp.Id; Scope = 'openid profile offline_access' })) {
    $existing = Get-MgOauth2PermissionGrant -Filter "clientId eq '$($gateway.Sp.Id)' and resourceId eq '$($grant.Resource)'" -Top 1
    if ($existing) { Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $existing.Id -Scope $grant.Scope }
    else { New-MgOauth2PermissionGrant -ClientId $gateway.Sp.Id -ConsentType 'AllPrincipals' -ResourceId $grant.Resource -Scope $grant.Scope | Out-Null }
}
$gatewaySecret = if ($NewSecrets -or -not $app.PasswordCredentials) { New-Secret $app 'Foundry MCP connection (OAuth identity passthrough)' }

# ================================================================== 2. the Purview app
$purview = Get-OrCreateApp $PurviewDisplayName @{
    Notes = 'Lets each team MCP server send tool results to Microsoft Purview processContent. Do not delete while labs are running.'
}
$processRole = $graphSp.AppRoles | Where-Object { $_.Value -eq 'Content.Process.All' } | Select-Object -First 1
if (-not $processRole) { throw 'Microsoft Graph has no Content.Process.All application permission in this tenant.' }
Update-MgApplication -ApplicationId $purview.App.Id -RequiredResourceAccess @(@{
    ResourceAppId = '00000003-0000-0000-c000-000000000000'; ResourceAccess = @(@{ Id = $processRole.Id; Type = 'Role' }) })
$assigned = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $purview.Sp.Id | Where-Object { $_.AppRoleId -eq $processRole.Id }
if (-not $assigned) {
    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $purview.Sp.Id -PrincipalId $purview.Sp.Id `
        -ResourceId $graphSp.Id -AppRoleId $processRole.Id | Out-Null
}
$purviewSecret = if ($NewSecrets -or -not $purview.App.PasswordCredentials) { New-Secret $purview.App 'Team MCP servers (Key Vault purview-client-secret)' }

# ================================================================== output for the CloudLabs template
Write-Host ''
Write-Host 'CloudLabs template parameters' -ForegroundColor Green
Write-Host "  mcpGatewayAppId      = $($app.AppId)   (audience api://$($app.AppId), scope ServiceDesk.Access)"
if ($gatewaySecret) { Write-Host "  mcpOAuthClientSecret = $($gatewaySecret.Value)   (expires $($gatewaySecret.Expires.ToString('yyyy-MM-dd')); set as a secure parameter, shown once)" -ForegroundColor Yellow }
else { Write-Host '  mcpOAuthClientSecret = unchanged (run with -NewSecrets to create a new one)' }
Write-Host "  purviewClientId      = $($purview.App.AppId)"
if ($purviewSecret) { Write-Host "  purviewClientSecret  = $($purviewSecret.Value)   (expires $($purviewSecret.Expires.ToString('yyyy-MM-dd')); secure parameter, shown once)" -ForegroundColor Yellow }
else { Write-Host '  purviewClientSecret  = unchanged (run with -NewSecrets to create a new one)' }
Write-Host "  Redirect URLs on the gateway app: $(if ($uris) { $uris -join ', ' } else { 'none yet: create one team connection, then re-run with -RedirectUri' })"

Write-Host ''
Write-Host 'Power Platform checks (Windows PowerShell 5.1):' -ForegroundColor Cyan
$check = @'
Import-Module Microsoft.PowerApps.Administration.PowerShell
Add-PowerAppsAccount | Out-Null
$t = Get-TenantSettings
"  Developer environment creation restricted to admins: $($t.powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers)"
"  Allowed consent plans: $((Get-AllowedConsentPlans) -join ', ')"
'@
powershell.exe -NoProfile -Command $check
Write-Host @'
Also required (setup/README.md, "Tenant preparation", has the steps):
  - Developer environment creation allowed for lab users (value above False), or the lab
    users are Power Platform administrators.
  - Both lab users of a team (Senior Technician and Tier 1 Technician) hold the Microsoft
    Power Apps for Developer licence (POWERAPPS_DEV) and Microsoft 365 E5 or E5 Compliance
    (Microsoft Purview DLP for AI interactions).
  - A sensitivity label for the customer configuration document (default name Confidential):
    its label ID is the template parameter sensitivityLabelId.
  - A Microsoft Purview DLP policy for the 'Relecloud Service Desk Purview Integration' app
    that blocks credit card numbers, with pay-as-you-go billing enabled for Purview.
  - No Conditional Access policy that blocks agent identities (Entra ID > Agent ID).
'@
