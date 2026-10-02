#Requires -Version 7.0
<#
.SYNOPSIS
    Security and audit configuration for a team's Service Desk environment: least-privileged
    roles, application users, the two technician identities, the regulated-accounts business
    unit and auditing.

.DESCRIPTION
    Safe by default. Every step is idempotent and resets the configuration to the documented
    baseline, so a re-run also undoes changes made during the exercises.

    1. Auditing on for the environment (30-day retention). Tables and columns are audited by
       the schema.
    2. Security roles from schema.json, with exactly the privileges listed there (plus those of
       the base role). Privilege names and IDs come from each table's metadata, so names such
       as prvReadNote (annotation) need no special cases. Reads and writes are separate roles:
         Service Desk Agent Read      read the Service Desk tables
         Service Desk Agent Write     update tickets and add ticket notes, nothing else
         Service Desk Senior Technician / Service Desk Tier 1 Technician   the people
    3. The MCP server's managed identity as an application user holding Agent Read, Agent
       Write and Delegate. Delegate (prvActOnBehalfOfAnotherUser) lets the server run each call
       on behalf of the signed-in user, so Dataverse applies the user's role as well as its own.
       System Administrator is removed if an earlier run assigned it.
    4. The VM's provisioning identity as an application user holding Agent Read, used by the
       readiness check and the validation scripts.
    5. The Senior Technician (the team user, who owns the environment) and the Tier 1
       Technician (read-only on tickets) with their roles. The Tier 1 user must already be in
       the environment (New-DeveloperEnvironment.ps1 adds them); this script waits for it.
    6. The business unit 'Relecloud Regulated Accounts' with its default team, which owns the
       regulated customer's records (assigned by the seed loader), and the team's role.
    7. The Service Desk app shared with the System Administrator and both technician roles.

.EXAMPLE
    .\Set-DataverseSecurity.ps1 -OrgUrl https://mspdesk123456.crm4.dynamics.com -McpIdentityClientId <guid> `
        -ReadinessIdentityClientId <guid> -SeniorUserName labuser@contoso.onmicrosoft.com -Tier1UserObjectId <guid>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OrgUrl,
    [Parameter(Mandatory)][string]$McpIdentityClientId,
    [string]$ReadinessIdentityClientId,
    [Parameter(Mandatory)][string]$SeniorUserName,
    [string]$Tier1UserObjectId,
    [string]$Tier1UserName,
    [int]$UserWaitMinutes = 15,
    [string]$SchemaPath = (Join-Path $PSScriptRoot 'schema.json')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json -AsHashtable
$OrgUrl = $OrgUrl.TrimEnd('/')
$api = "$OrgUrl/api/data/v9.2"
function DV { param([string]$Method, [string]$Path, $Body = $null, [switch]$AllowNotFound)
    Invoke-Dataverse -OrgUrl $OrgUrl -Method $Method -Path $Path -Body $Body -AllowNotFound:$AllowNotFound }
function Lit([string]$value) { return "'" + $value.Replace("'", "''") + "'" }

$rootBu = ((DV GET 'businessunits?$select=businessunitid&$filter=_parentbusinessunitid_value eq null').Body.value | Select-Object -First 1).businessunitid
function Get-RoleId([string]$name, [string]$businessUnitId = $rootBu) {
    $r = (DV GET "roles?`$select=roleid&`$filter=name eq $(Lit $name) and _businessunitid_value eq $businessUnitId").Body.value | Select-Object -First 1
    if ($r) { return $r.roleid }
    return $null
}
function Get-UserRoles([string]$userId) {
    return @((DV GET "systemusers($userId)/systemuserroles_association?`$select=roleid,name").Body.value)
}
function Grant-Role([string]$userId, [string]$roleName) {
    $roleId = Get-RoleId $roleName
    if (-not $roleId) { throw "Security role '$roleName' was not found." }
    if ((Get-UserRoles $userId).roleid -notcontains $roleId) {
        DV POST "systemusers($userId)/systemuserroles_association/`$ref" @{ '@odata.id' = "$api/roles($roleId)" } | Out-Null
    }
}
function Revoke-Role([string]$userId, [string]$roleName) {
    $roleId = Get-RoleId $roleName
    if ($roleId -and ((Get-UserRoles $userId).roleid -contains $roleId)) {
        DV DELETE "systemusers($userId)/systemuserroles_association($roleId)/`$ref" | Out-Null
        Write-Step "  removed '$roleName'"
    }
}
function Set-ExactRoles([string]$userId, [string[]]$roleNames, [string[]]$neverHold = @()) {
    foreach ($name in $roleNames) { Grant-Role $userId $name }
    foreach ($name in $neverHold) { Revoke-Role $userId $name }
}

# ================================================================== 1. environment auditing
Write-Step 'Environment auditing'
$org = (DV GET 'organizations?$select=organizationid,isauditenabled').Body.value | Select-Object -First 1
if (-not $org.isauditenabled) {
    DV PATCH "organizations($($org.organizationid))" @{ isauditenabled = $true; auditretentionperiodv2 = 30 } | Out-Null
}
Write-Step '  auditing is on (30-day retention)'

# ================================================================== 2. security roles
$privilegeCache = @{}
function Get-TablePrivileges([string]$table) {
    if (-not $privilegeCache.ContainsKey($table)) {
        $meta = (DV GET "EntityDefinitions(LogicalName='$table')?`$select=LogicalName,Privileges").Body
        $privilegeCache[$table] = @($meta.Privileges)
    }
    return $privilegeCache[$table]
}
$verbs = @{ create = 'Create'; read = 'Read'; write = 'Write'; append = 'Append'; appendTo = 'AppendTo' }

foreach ($roleDef in $schema.securityRoles) {
    Write-Step "Role '$($roleDef.name)'"
    $roleId = Get-RoleId $roleDef.name
    if (-not $roleId) {
        $r = DV POST 'roles' @{ name = $roleDef.name; description = $roleDef.description; 'businessunitid@odata.bind' = "/businessunits($rootBu)" }
        $roleId = Get-EntityIdFromHeader $r.Headers
    }
    $merged = @{}
    if ($roleDef.baseRole) {
        $baseId = Get-RoleId $roleDef.baseRole
        if (-not $baseId) { throw "Base role '$($roleDef.baseRole)' was not found." }
        foreach ($p in (DV GET "RetrieveRolePrivilegesRole(RoleId=$baseId)").Body.RolePrivileges) {
            $merged[$p.PrivilegeId] = @{ PrivilegeId = $p.PrivilegeId; Depth = $p.Depth; BusinessUnitId = $rootBu; PrivilegeName = $p.PrivilegeName }
        }
    }
    foreach ($entry in $roleDef.privileges) {
        $available = Get-TablePrivileges $entry.table
        foreach ($verb in $verbs.Keys) {
            if (-not $entry.ContainsKey($verb)) { continue }
            $priv = $available | Where-Object { $_.PrivilegeType -eq $verbs[$verb] } | Select-Object -First 1
            if (-not $priv) { throw "Table $($entry.table) has no $($verbs[$verb]) privilege." }
            $merged[$priv.PrivilegeId] = @{ PrivilegeId = $priv.PrivilegeId; Depth = $entry[$verb]; BusinessUnitId = $rootBu; PrivilegeName = $priv.Name }
        }
    }
    # Replace, not add: the role ends up with exactly this privilege set.
    DV POST "roles($roleId)/Microsoft.Dynamics.CRM.ReplacePrivilegesRole" @{ Privileges = @($merged.Values) } | Out-Null
    Write-Step "  $($merged.Count) privileges"
}

# Delegate holds prvActOnBehalfOfAnotherUser. It is a built-in role; create an equivalent if
# the environment lacks it.
$delegateName = 'Delegate'
if (-not (Get-RoleId $delegateName)) {
    $delegateName = 'Service Desk Delegate'
    if (-not (Get-RoleId $delegateName)) {
        $priv = (DV GET "privileges?`$select=privilegeid,name&`$filter=name eq 'prvActOnBehalfOfAnotherUser'").Body.value | Select-Object -First 1
        if (-not $priv) { throw 'Privilege prvActOnBehalfOfAnotherUser was not found.' }
        $r = DV POST 'roles' @{ name = $delegateName; description = 'Act on behalf of another user (impersonation).'
            'businessunitid@odata.bind' = "/businessunits($rootBu)" }
        $roleId = Get-EntityIdFromHeader $r.Headers
        DV POST "roles($roleId)/Microsoft.Dynamics.CRM.ReplacePrivilegesRole" @{ Privileges = @(@{
            PrivilegeId = $priv.privilegeid; Depth = 'Global'; BusinessUnitId = $rootBu; PrivilegeName = $priv.name }) } | Out-Null
    }
}
$assignments = $schema.roleAssignments
$mcpRoles = @($assignments.mcpApplicationUser | ForEach-Object { if ($_ -eq 'Delegate') { $delegateName } else { $_ } })

# ================================================================== 3 and 4. application users
function Get-ApplicationUser([string]$clientId, [string]$purpose) {
    $user = (DV GET "systemusers?`$select=systemuserid,fullname&`$filter=applicationid eq $clientId").Body.value | Select-Object -First 1
    if ($user) { return $user.systemuserid }
    try {
        $r = DV POST 'systemusers' @{ applicationid = $clientId; 'businessunitid@odata.bind' = "/businessunits($rootBu)" }
        return Get-EntityIdFromHeader $r.Headers
    }
    catch {
        throw ("Creating the application user for the $purpose failed: $($_.Exception.Message). Create it by hand: Power Platform " +
               "admin center, this environment, Settings, Users + permissions, Application users, New app user, Add an app, " +
               "enter $clientId, business unit = root.")
    }
}

Write-Step "Application user for the MCP server ($McpIdentityClientId)"
$appUserId = Get-ApplicationUser $McpIdentityClientId 'MCP server'
Set-ExactRoles $appUserId $mcpRoles @('System Administrator', 'System Customizer')
Write-Step "  $appUserId holds $($mcpRoles -join ', ')"

$readinessUserId = $null
if ($ReadinessIdentityClientId) {
    Write-Step "Application user for the readiness check ($ReadinessIdentityClientId)"
    $readinessUserId = Get-ApplicationUser $ReadinessIdentityClientId 'readiness check'
    Set-ExactRoles $readinessUserId @($assignments.readinessApplicationUser) @('System Administrator', 'Service Desk Agent Write')
    Write-Step "  $readinessUserId holds $($assignments.readinessApplicationUser -join ', ')"
}

# ================================================================== 5. the two technicians
function Find-HumanUser([string]$objectId, [string]$userName) {
    $filters = @()
    if ($objectId) { $filters += "azureactivedirectoryobjectid eq $objectId" }
    if ($userName) { $filters += "domainname eq $(Lit $userName)" }
    $deadline = (Get-Date).AddMinutes($UserWaitMinutes)
    do {
        foreach ($f in $filters) {
            $u = (DV GET "systemusers?`$select=systemuserid,fullname,isdisabled&`$filter=$f").Body.value | Select-Object -First 1
            if ($u -and -not $u.isdisabled) { return $u.systemuserid }
        }
        Write-Step "  waiting for $($userName ?? $objectId) to appear in the environment"
        Start-Sleep -Seconds 30
    } while ((Get-Date) -lt $deadline)
    return $null
}

Write-Step "Senior Technician ($SeniorUserName)"
$seniorId = Find-HumanUser '' $SeniorUserName
if (-not $seniorId) { throw "The team user $SeniorUserName is not a user of the environment." }
Set-ExactRoles $seniorId @($assignments.seniorTechnician)
Write-Step "  $seniorId holds $($assignments.seniorTechnician -join ', ') (and System Administrator as the environment owner)"

$tier1Id = $null
if ($Tier1UserObjectId -or $Tier1UserName) {
    Write-Step "Tier 1 Technician ($($Tier1UserName ?? $Tier1UserObjectId))"
    $tier1Id = Find-HumanUser $Tier1UserObjectId $Tier1UserName
    if (-not $tier1Id) { throw "The Tier 1 user did not appear in the environment within $UserWaitMinutes minutes." }
    Set-ExactRoles $tier1Id @($assignments.tier1Technician) @('System Administrator', 'System Customizer', 'Service Desk Senior Technician',
                                                            'Service Desk Agent Write', 'Environment Maker')
    Write-Step "  $tier1Id holds $($assignments.tier1Technician -join ', ') only"
}
else { Write-Step 'Tier 1 Technician: no user given; skipped (Exercise 5 Task 4 needs it).' }

# ================================================================== 6. regulated accounts business unit
$buIds = @{}
foreach ($bu in $schema.businessUnits) {
    Write-Step "Business unit '$($bu.name)'"
    $existing = (DV GET "businessunits?`$select=businessunitid&`$filter=name eq $(Lit $bu.name)").Body.value | Select-Object -First 1
    $buId = if ($existing) { $existing.businessunitid } else {
        $r = DV POST 'businessunits' @{ name = $bu.name; description = $bu.description
            'parentbusinessunitid@odata.bind' = "/businessunits($rootBu)" }
        Get-EntityIdFromHeader $r.Headers
    }
    $buIds[$bu.name] = $buId
    # Every business unit has a default team with its name; it owns the regulated records.
    $team = Invoke-WithRetry -What "default team of $($bu.name)" -DelaySeconds 10 -Action {
        $t = (DV GET "teams?`$select=teamid,name&`$filter=_businessunitid_value eq $buId and isdefault eq true").Body.value | Select-Object -First 1
        if (-not $t) { throw 'not created yet' }
        $t
    }
    # Owner teams need a security role to own records. Roles are copied into every business
    # unit, so use this business unit's copy.
    $teamRoleId = Invoke-WithRetry -What "role copy in $($bu.name)" -DelaySeconds 10 -Action {
        $id = Get-RoleId $bu.teamRole $buId
        if (-not $id) { throw 'not copied yet' }
        $id
    }
    $teamRoles = (DV GET "teams($($team.teamid))/teamroles_association?`$select=roleid").Body.value | ForEach-Object { $_.roleid }
    if ($teamRoles -notcontains $teamRoleId) {
        DV POST "teams($($team.teamid))/teamroles_association/`$ref" @{ '@odata.id' = "$api/roles($teamRoleId)" } | Out-Null
    }
    Write-Step "  team '$($team.name)' ($($team.teamid)) holds '$($bu.teamRole)'; owns the records of $($bu.customers -join ', ')"
}

# ================================================================== 7. app visibility
$appUnique = $schema.app.uniqueName
$app = (DV GET "appmodules?`$select=appmoduleid&`$filter=uniquename eq '$appUnique'").Body.value | Select-Object -First 1
if ($app) {
    $appRoles = (DV GET "appmodules($($app.appmoduleid))/appmoduleroles_association?`$select=roleid").Body.value | ForEach-Object { $_.roleid }
    foreach ($roleName in $assignments.appRoles) {
        $roleId = Get-RoleId $roleName
        if ($roleId -and $appRoles -notcontains $roleId) {
            DV POST "appmodules($($app.appmoduleid))/appmoduleroles_association/`$ref" @{ '@odata.id' = "$api/roles($roleId)" } | Out-Null
        }
    }
    Write-Step "  Service Desk app shared with $($assignments.appRoles -join ', ')"
}
else { Write-Step "  WARNING: app $appUnique not found; share it with the technician roles in the maker portal." }

[pscustomobject]@{
    ApplicationUserId = $appUserId; ReadinessUserId = $readinessUserId; SeniorUserId = $seniorId; Tier1UserId = $tier1Id
    RegulatedBusinessUnitId = ($buIds.Values | Select-Object -First 1)
}
