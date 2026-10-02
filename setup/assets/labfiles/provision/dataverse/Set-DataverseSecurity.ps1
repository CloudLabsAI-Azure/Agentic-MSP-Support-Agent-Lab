#Requires -Version 7.0
<#
.SYNOPSIS
    Security and audit configuration for a team's Service Desk environment.

.DESCRIPTION
    1. Turns on auditing for the environment (tables and columns are audited by the schema).
    2. Creates the Dataverse application user for the MCP server's user-assigned managed
       identity and gives it System Administrator. This is DELIBERATELY over-privileged:
       Exercise 5 has teams find it, prove it holds more than the agent needs, and replace it
       with a least-privilege role.
    3. Associates the Service Desk app with the System Administrator role so the team user
       sees it.
    4. Creates the 'Service Desk Integration' reference role (Basic User privileges plus exactly
       what the MCP tools need). It is not assigned to anyone; teams copy it in Exercise 5.

.EXAMPLE
    .\Set-DataverseSecurity.ps1 -OrgUrl https://mspdesk123456.crm4.dynamics.com -McpIdentityClientId <guid>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OrgUrl,
    [Parameter(Mandatory)][string]$McpIdentityClientId,
    [string]$SchemaPath = (Join-Path $PSScriptRoot 'schema.json')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json -AsHashtable
$OrgUrl = $OrgUrl.TrimEnd('/')
function DV { param([string]$Method, [string]$Path, $Body = $null, [switch]$AllowNotFound)
    Invoke-Dataverse -OrgUrl $OrgUrl -Method $Method -Path $Path -Body $Body -AllowNotFound:$AllowNotFound }

$rootBu = ((DV GET 'businessunits?$select=businessunitid&$filter=_parentbusinessunitid_value eq null').Body.value | Select-Object -First 1).businessunitid
function Get-RoleId([string]$name) {
    $r = (DV GET "roles?`$select=roleid&`$filter=name eq '$name' and _businessunitid_value eq $rootBu").Body.value | Select-Object -First 1
    if ($r) { return $r.roleid }
    return $null
}
$sysAdminRole = Get-RoleId 'System Administrator'

# ------------------------------------------------------------------ 1. environment auditing
Write-Step 'Environment auditing'
$org = (DV GET 'organizations?$select=organizationid,isauditenabled').Body.value | Select-Object -First 1
if (-not $org.isauditenabled) {
    DV PATCH "organizations($($org.organizationid))" @{ isauditenabled = $true; auditretentionperiodv2 = 30 } | Out-Null
}
Write-Step '  auditing is on (30-day retention)'

# ------------------------------------------------------------------ 2. MCP application user
Write-Step "Application user for managed identity $McpIdentityClientId"
$appUser = (DV GET "systemusers?`$select=systemuserid,fullname&`$filter=applicationid eq $McpIdentityClientId").Body.value | Select-Object -First 1
if (-not $appUser) {
    try {
        $r = DV POST 'systemusers' @{ applicationid = $McpIdentityClientId; 'businessunitid@odata.bind' = "/businessunits($rootBu)" }
        $appUserId = Get-EntityIdFromHeader $r.Headers
    }
    catch {
        throw ("Creating the application user failed: $($_.Exception.Message). Create it by hand: Power Platform admin center > " +
               "Environments > this environment > Settings > Users + permissions > Application users > New app user > " +
               "Add an app > enter $McpIdentityClientId, business unit = root, role = System Administrator.")
    }
}
else { $appUserId = $appUser.systemuserid }
$assigned = (DV GET "systemusers($appUserId)/systemuserroles_association?`$select=roleid").Body.value | ForEach-Object { $_.roleid }
if ($assigned -notcontains $sysAdminRole) {
    DV POST "systemusers($appUserId)/systemuserroles_association/`$ref" @{ '@odata.id' = "$OrgUrl/api/data/v9.2/roles($sysAdminRole)" } | Out-Null
}
Write-Step "  application user $appUserId holds System Administrator (deliberately over-privileged)"

# ------------------------------------------------------------------ 3. app visibility
$appUnique = $schema.app.uniqueName
$app = (DV GET "appmodules?`$select=appmoduleid&`$filter=uniquename eq '$appUnique'").Body.value | Select-Object -First 1
if ($app) {
    $appRoles = (DV GET "appmodules($($app.appmoduleid))/appmoduleroles_association?`$select=roleid").Body.value | ForEach-Object { $_.roleid }
    if ($appRoles -notcontains $sysAdminRole) {
        DV POST "appmodules($($app.appmoduleid))/appmoduleroles_association/`$ref" @{ '@odata.id' = "$OrgUrl/api/data/v9.2/roles($sysAdminRole)" } | Out-Null
    }
    Write-Step '  Service Desk app shared with System Administrator'
}
else { Write-Step "  WARNING: app $appUnique not found; share it with System Administrator in the maker portal." }

# ------------------------------------------------------------------ 4. reference least-privilege role
foreach ($roleDef in $schema.securityRoles) {
    Write-Step "Reference role '$($roleDef.name)'"
    $roleId = Get-RoleId $roleDef.name
    if (-not $roleId) {
        $r = DV POST 'roles' @{ name = $roleDef.name; description = $roleDef.description; 'businessunitid@odata.bind' = "/businessunits($rootBu)" }
        $roleId = Get-EntityIdFromHeader $r.Headers
    }
    $merged = @{}
    $baseId = Get-RoleId $roleDef.baseRole
    if ($baseId) {
        $base = (DV GET "RetrieveRolePrivilegesRole(RoleId=$baseId)").Body.RolePrivileges
        foreach ($p in $base) { $merged[$p.PrivilegeId] = @{ PrivilegeId = $p.PrivilegeId; Depth = $p.Depth; BusinessUnitId = $rootBu; PrivilegeName = $p.PrivilegeName } }
    }
    $verbs = @{ read = 'Read'; write = 'Write'; create = 'Create'; append = 'Append'; appendTo = 'AppendTo' }
    foreach ($entry in $roleDef.privileges) {
        $schemaName = (DV GET "EntityDefinitions(LogicalName='$($entry.table)')?`$select=SchemaName").Body.SchemaName
        foreach ($verb in $verbs.Keys) {
            if (-not $entry.ContainsKey($verb)) { continue }
            $name = "prv$($verbs[$verb])$schemaName"
            $priv = (DV GET "privileges?`$select=privilegeid,name&`$filter=name eq '$name'").Body.value | Select-Object -First 1
            if (-not $priv) { Write-Step "  privilege $name not found; skipped"; continue }
            $merged[$priv.privilegeid] = @{ PrivilegeId = $priv.privilegeid; Depth = $entry[$verb]; BusinessUnitId = $rootBu; PrivilegeName = $name }
        }
    }
    $list = @($merged.Values)
    for ($i = 0; $i -lt $list.Count; $i += 100) {
        $chunk = $list[$i..([Math]::Min($i + 99, $list.Count - 1))]
        DV POST "roles($roleId)/Microsoft.Dynamics.CRM.AddPrivilegesRole" @{ Privileges = $chunk } | Out-Null
    }
    Write-Step "  $($list.Count) privileges on '$($roleDef.name)' (not assigned to anyone)"
}

[pscustomobject]@{ ApplicationUserId = $appUserId; SystemAdministratorRoleId = $sysAdminRole }
