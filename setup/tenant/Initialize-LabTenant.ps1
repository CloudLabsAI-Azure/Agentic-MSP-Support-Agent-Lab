#Requires -Version 7.0
<#
.SYNOPSIS
    One-time preparation of the CloudLabs tenant for the Agentic MSP Support Agent lab.
    Run once per tenant by a tenant administrator, before the first team deployment.

.DESCRIPTION
    1. Creates the 'Relecloud Service Desk MCP Gateway' app registration. It holds no secret and
       no permissions; it only defines the token audience (api://<application id>) that every
       team's Foundry agent identity requests when it calls its team's API Management gateway.
       It exposes one application role, ServiceDesk.Tools.Invoke, for tenants that require role
       assignment (see -RequireRoleAssignment). Prints the application ID to put in
       deploy-01.parameters.json (mcpGatewayAppId).
    2. Checks the Power Platform tenant settings the lab depends on and prints what to change.

    Needs: Microsoft Graph PowerShell (Microsoft.Graph.Applications) with Application.ReadWrite.All,
    and Microsoft.PowerApps.Administration.PowerShell for the Power Platform checks (Windows
    PowerShell 5.1 runs that part).

.EXAMPLE
    .\Initialize-LabTenant.ps1 -TenantId <tenant id>
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$TenantId,
    [string]$DisplayName = 'Relecloud Service Desk MCP Gateway',
    [switch]$RequireRoleAssignment
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable Microsoft.Graph.Applications)) {
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Applications
Connect-MgGraph -TenantId $TenantId -Scopes 'Application.ReadWrite.All' -NoWelcome

$app = Get-MgApplication -Filter "displayName eq '$DisplayName'" -Top 1
if (-not $app) {
    if ($PSCmdlet.ShouldProcess($DisplayName, 'Create app registration')) {
        $roleId = [guid]::NewGuid()
        $app = New-MgApplication -DisplayName $DisplayName -SignInAudience 'AzureADMyOrg' -Api @{ RequestedAccessTokenVersion = 2 } `
            -AppRoles @(@{
                Id = $roleId; AllowedMemberTypes = @('Application'); IsEnabled = $true; Value = 'ServiceDesk.Tools.Invoke'
                DisplayName = 'Invoke Service Desk MCP tools'
                Description = 'Lets an agent identity call a team Service Desk MCP gateway.'
            }) -Notes 'Token audience for the Agentic MSP Support Agent lab. No secrets. Do not delete while labs are running.'
        Update-MgApplication -ApplicationId $app.Id -IdentifierUris @("api://$($app.AppId)")
        New-MgServicePrincipal -AppId $app.AppId -AppRoleAssignmentRequired:$RequireRoleAssignment.IsPresent | Out-Null
        $app = Get-MgApplication -ApplicationId $app.Id
    }
}
Write-Host ''
Write-Host "MCP gateway app registration: $($app.DisplayName)" -ForegroundColor Green
Write-Host "  Application (client) ID : $($app.AppId)"
Write-Host "  Audience (App ID URI)   : api://$($app.AppId)"
Write-Host "  Set deploy-01.parameters.json -> mcpGatewayAppId = $($app.AppId)" -ForegroundColor Yellow
if ($RequireRoleAssignment) {
    Write-Host '  Role assignment is required: every team agent identity must be granted ServiceDesk.Tools.Invoke.' -ForegroundColor Yellow
}

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
Required:
  - Developer environment creation must be allowed for lab users (value above False), or the
    lab users must be Power Platform administrators.
  - Lab users need the Microsoft Power Apps for Developer licence (POWERAPPS_DEV,
    5b631642-bd26-49fe-bd20-1daaa972ef80). Assign it through the CloudLabs template licence
    settings or group-based licensing.
  - No Conditional Access policy may block agent identities (Entra ID > Agent ID).
'@
