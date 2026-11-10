#Requires -Version 7.0
<#
.SYNOPSIS
    Dataverse security baseline of the Service Desk environment, from security.json: auditing,
    least-privileged roles, the MCP application user, both technicians, the regulated business unit,
    the Contact Phone Protection column security profile and the app's sharing.

.DESCRIPTION
    Runs as the provisioning identity (id-prov), which is System Administrator in the environment
    until the last provisioning step reduces it to Service Desk Agent Read. This script never changes
    id-prov's own roles. Every step is idempotent: a re-run restores the documented baseline for the
    objects it manages and leaves anything else (for example a column a participant secured in
    Exercise 6) as it is.

    1. Organization auditing on, with the retention in security.json (table and column auditing
       comes from the schema).
    2. Roles, each with exactly its privileges (its base role's privileges plus the listed ones):
         Service Desk Agent Read        read the Service Desk tables (MCP application user, readiness,
                                        and the regulated business unit's team)
         Service Desk Agent Write       ticket updates, ticket notes, agent action records
         Service Desk Senior Technician read and write on tickets and notes, audit history
         Service Desk Tier 1 Technician read only
         Service Desk Security Steward  edit roles and column security profiles (Senior add-on)
    3. The MCP server's managed identity (an application user) holds Agent Read, Agent Write and the
       predefined Delegate role, never System Administrator. Delegate lets it act on behalf of the
       signed-in user, so Dataverse applies that user's role as well.
    4. The Senior Technician holds Senior Technician and Security Steward; with
       -SeniorSystemAdministrator (pilot fallback) also System Administrator in this environment.
       The Tier 1 Technician holds only Tier 1 Technician. Users are added on first reference.
    5. Business unit Relecloud Regulated Accounts; its default team holds Agent Read so it can own
       the regulated customer's records (the seed loader assigns them).
    6. Column security: contact telephone1 and mobilephone are secured; the profile Contact Phone
       Protection grants read to the Senior Technician only.
    7. The Service Desk app is shared with the System Administrator and both technician roles.
    Returns the IDs and a summary.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OrgUrl,
    [Parameter(Mandatory)][string]$McpIdentityClientId,
    [Parameter(Mandatory)][string]$SeniorObjectId,
    [string]$Tier1ObjectId,
    [switch]$SeniorSystemAdministrator,
    [int]$UserWaitMinutes = 20,
    [string]$SecurityPath = (Join-Path $PSScriptRoot 'security.json'),
    [string]$AppUniqueName = 'spk_ServiceDesk'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$security = Get-Content $SecurityPath -Raw | ConvertFrom-Json -AsHashtable
$OrgUrl = $OrgUrl.TrimEnd('/')
$api = "$OrgUrl/api/data/v9.2"
$warnings = New-Object System.Collections.Generic.List[string]
function DV { param([string]$Method, [string]$Path, $Body = $null, [switch]$AllowNotFound, [hashtable]$Headers = @{})
    Invoke-Dataverse -OrgUrl $OrgUrl -Method $Method -Path $Path -Body $Body -Headers $Headers -AllowNotFound:$AllowNotFound }
function Lit([string]$value) { return "'" + $value.Replace("'", "''") + "'" }
function Warn([string]$text) { $warnings.Add($text); Write-Step "  WARNING: $text" }

$rootBu = ((DV GET 'businessunits?$select=businessunitid&$filter=_parentbusinessunitid_value eq null').Body.value | Select-Object -First 1).businessunitid
function Get-RoleId([string]$name, [string]$businessUnitId = $rootBu) {
    $r = (DV GET "roles?`$select=roleid&`$filter=name eq $(Lit $name) and _businessunitid_value eq $businessUnitId").Body.value | Select-Object -First 1
    if ($r) { return $r.roleid }
    return $null
}
function Get-UserRoles([string]$userId) { return @((DV GET "systemusers($userId)/systemuserroles_association?`$select=roleid,name").Body.value) }
function Grant-Role([string]$userId, [string]$roleName) {
    $roleId = Get-RoleId $roleName
    if (-not $roleId) { throw "Security role '$roleName' was not found." }
    if ((Get-UserRoles $userId).roleid -notcontains $roleId) {
        $null = DV POST "systemusers($userId)/systemuserroles_association/`$ref" @{ '@odata.id' = "$api/roles($roleId)" }
    }
}
function Revoke-Role([string]$userId, [string]$roleName) {
    $roleId = Get-RoleId $roleName
    if ($roleId -and ((Get-UserRoles $userId).roleid -contains $roleId)) {
        $null = DV DELETE "systemusers($userId)/systemuserroles_association($roleId)/`$ref"
        Write-Step "  removed '$roleName'"
    }
}
function Set-ExactRoles([string]$userId, [string[]]$roleNames, [string[]]$neverHold = @()) {
    foreach ($name in $roleNames) { Grant-Role $userId $name }
    foreach ($name in ($neverHold | Where-Object { $_ -notin $roleNames })) { Revoke-Role $userId $name }
    return @((Get-UserRoles $userId).name)
}

# ==== 1. Organization auditing
Write-Step 'Environment auditing'
$org = (DV GET 'organizations?$select=organizationid,isauditenabled,auditretentionperiodv2').Body.value | Select-Object -First 1
$retention = [int]$security.audit.retentionDays
if (-not $org.isauditenabled -or [int]$org.auditretentionperiodv2 -ne $retention) {
    $null = DV PATCH "organizations($($org.organizationid))" @{ isauditenabled = $true; auditretentionperiodv2 = $retention }
}
Write-Step "  auditing is on ($retention-day retention)"

# ==== 2. Roles
$privilegeCache = @{}
function Get-TablePrivileges([string]$table) {
    if (-not $privilegeCache.ContainsKey($table)) {
        $meta = DV GET "EntityDefinitions(LogicalName='$table')?`$select=LogicalName,Privileges" -AllowNotFound
        $privilegeCache[$table] = if ($meta) { @($meta.Body.Privileges) } else { $null }
    }
    return $privilegeCache[$table]
}
$verbs = [ordered]@{ create = 'Create'; read = 'Read'; write = 'Write'; append = 'Append'; appendTo = 'AppendTo' }

foreach ($roleDef in $security.roles) {
    Write-Step "Role '$($roleDef.name)'"
    $roleId = Get-RoleId $roleDef.name
    if (-not $roleId) {
        $r = DV POST 'roles' @{ name = $roleDef.name; description = $roleDef.description; 'businessunitid@odata.bind' = "/businessunits($rootBu)" }
        $roleId = Get-EntityIdFromHeader $r.Headers
    }
    $merged = @{}
    if ($roleDef.baseRole) {
        $baseName = $roleDef.baseRole
        $baseId = Get-RoleId $baseName
        if (-not $baseId -and $baseName -eq 'App Opener') { $baseName = 'Basic User'; $baseId = Get-RoleId $baseName; Warn "role App Opener not found; $($roleDef.name) is based on Basic User" }
        if (-not $baseId) { throw "Base role '$($roleDef.baseRole)' was not found." }
        foreach ($p in (DV GET "RetrieveRolePrivilegesRole(RoleId=$baseId)").Body.RolePrivileges) {
            $merged[$p.PrivilegeId] = @{ PrivilegeId = $p.PrivilegeId; Depth = $p.Depth; BusinessUnitId = $rootBu; PrivilegeName = $p.PrivilegeName }
        }
    }
    foreach ($entry in $roleDef.privileges) {
        $available = Get-TablePrivileges $entry.table
        if ($null -eq $available) {
            if ($entry.optional) { Warn "table $($entry.table) not found; skipped in $($roleDef.name)"; continue }
            throw "Table $($entry.table) does not exist; deploy the schema first."
        }
        foreach ($verb in $verbs.Keys) {
            if (-not $entry.ContainsKey($verb)) { continue }
            $priv = $available | Where-Object { $_.PrivilegeType -eq $verbs[$verb] } | Select-Object -First 1
            if (-not $priv) {
                if ($entry.optional) { Warn "table $($entry.table) has no $($verbs[$verb]) privilege"; continue }
                throw "Table $($entry.table) has no $($verbs[$verb]) privilege."
            }
            $merged[$priv.PrivilegeId] = @{ PrivilegeId = $priv.PrivilegeId; Depth = $entry[$verb]; BusinessUnitId = $rootBu; PrivilegeName = $priv.Name }
        }
    }
    foreach ($named in @($roleDef.privilegeNames)) {
        if (-not $named) { continue }
        $priv = (DV GET "privileges?`$select=privilegeid,name&`$filter=name eq $(Lit $named.name)").Body.value | Select-Object -First 1
        if (-not $priv) {
            if ($named.optional) { Warn "privilege $($named.name) not found; skipped in $($roleDef.name)"; continue }
            throw "Privilege $($named.name) was not found."
        }
        $merged[$priv.privilegeid] = @{ PrivilegeId = $priv.privilegeid; Depth = $named.depth; BusinessUnitId = $rootBu; PrivilegeName = $priv.name }
    }
    # Replace, not add: the role ends up with exactly this privilege set.
    $null = DV POST "roles($roleId)/Microsoft.Dynamics.CRM.ReplacePrivilegesRole" @{ Privileges = @($merged.Values) }
    Write-Step "  $($merged.Count) privileges"
}

# Delegate holds prvActOnBehalfOfAnotherUser. It is a predefined role: Dataverse refuses to add that
# privilege to a custom role (0x8004Ed43), so there is no fallback.
if (-not (Get-RoleId 'Delegate')) { throw 'The predefined Delegate role was not found in the environment.' }

# ==== 3. The MCP server's application user
Write-Step "Application user of the MCP server ($McpIdentityClientId)"
$mcpUser = Invoke-WithRetry -What 'MCP application user' -Attempts 10 -DelaySeconds 30 -Action {
    $u = (DV GET "systemusers?`$select=systemuserid,fullname,isdisabled&`$filter=applicationid eq $McpIdentityClientId").Body.value | Select-Object -First 1
    if (-not $u) { throw 'not in the environment yet (the environment step adds it)' }
    $u
}
$mcpRoles = Set-ExactRoles $mcpUser.systemuserid @($security.assignments.mcpApplicationUser) @($security.assignments.neverHold.mcpApplicationUser)
Write-Step "  $($mcpUser.systemuserid) holds $($mcpRoles -join ', ')"

# ==== 4. The two technicians (added to Dataverse on first reference; they need their licenses)
function Resolve-HumanUser([string]$objectId, [string]$label) {
    return Invoke-WithRetry -What "$label in Dataverse" -Attempts ([Math]::Max(1, [int]($UserWaitMinutes * 2))) -DelaySeconds 30 -Action {
        $u = (DV GET "systemusers(azureactivedirectoryobjectid=$objectId)?`$select=systemuserid,fullname,domainname,isdisabled").Body
        if (-not $u -or $u.isdisabled) { throw "$label is not an enabled user yet (license still syncing?)" }
        $u
    }
}
Write-Step 'Senior Technician'
$senior = Resolve-HumanUser $SeniorObjectId 'Senior Technician'
$seniorWanted = @($security.assignments.seniorTechnician)
$seniorNever = @($security.assignments.neverHold.seniorTechnician)
if ($SeniorSystemAdministrator) { $seniorWanted += 'System Administrator' } else { $seniorNever += 'System Administrator' }
try { $seniorRoles = Set-ExactRoles $senior.systemuserid $seniorWanted $seniorNever }
catch { throw "Setting the Senior Technician's roles failed: $($_.Exception.Message). If System Administrator cannot be removed from the environment's user, deploy with seniorDataverseSystemAdministrator true (pilot fallback)." }
Write-Step "  $($senior.domainname) holds $($seniorRoles -join ', ')"

$tier1 = $null
$tier1Roles = @()
if ($Tier1ObjectId) {
    Write-Step 'Tier 1 Technician'
    $tier1 = Resolve-HumanUser $Tier1ObjectId 'Tier 1 Technician'
    $tier1Roles = Set-ExactRoles $tier1.systemuserid @($security.assignments.tier1Technician) @($security.assignments.neverHold.tier1Technician)
    Write-Step "  $($tier1.domainname) holds $($tier1Roles -join ', ')"
}
else { Warn 'no Tier 1 Technician given; Exercise 5 Task 4 needs one' }

# ==== 5. Regulated accounts business unit
$buIds = @{}
foreach ($bu in $security.businessUnits) {
    Write-Step "Business unit '$($bu.name)'"
    $existing = (DV GET "businessunits?`$select=businessunitid&`$filter=name eq $(Lit $bu.name)").Body.value | Select-Object -First 1
    $buId = if ($existing) { $existing.businessunitid } else {
        $r = DV POST 'businessunits' @{ name = $bu.name; description = $bu.description; 'parentbusinessunitid@odata.bind' = "/businessunits($rootBu)" }
        Get-EntityIdFromHeader $r.Headers
    }
    $buIds[$bu.name] = $buId
    $team = Invoke-WithRetry -What "default team of $($bu.name)" -DelaySeconds 10 -Action {
        $t = (DV GET "teams?`$select=teamid,name&`$filter=_businessunitid_value eq $buId and isdefault eq true").Body.value | Select-Object -First 1
        if (-not $t) { throw 'not created yet' }
        $t
    }
    # Roles are copied into every business unit; owner teams need a role of their own business unit.
    $teamRoleId = Invoke-WithRetry -What "role copy in $($bu.name)" -DelaySeconds 10 -Action {
        $id = Get-RoleId $bu.teamRole $buId
        if (-not $id) { throw 'not copied yet' }
        $id
    }
    $teamRoles = @((DV GET "teams($($team.teamid))/teamroles_association?`$select=roleid").Body.value | ForEach-Object { $_.roleid })
    if ($teamRoles -notcontains $teamRoleId) {
        $null = DV POST "teams($($team.teamid))/teamroles_association/`$ref" @{ '@odata.id' = "$api/roles($teamRoleId)" }
    }
    Write-Step "  team '$($team.name)' holds '$($bu.teamRole)'; owns the records of $($bu.customers -join ', ')"
}

# ==== 6. Column security
$principalIds = @{ seniorTechnician = $senior.systemuserid; mcpApplicationUser = $mcpUser.systemuserid }
$provisioningUser = (DV GET "systemusers?`$select=systemuserid&`$filter=applicationid eq $(Get-ProvisioningClientId)").Body.value | Select-Object -First 1
if ($provisioningUser) { $principalIds.provisioningApplicationUser = $provisioningUser.systemuserid }
if ($tier1) { $principalIds.tier1Technician = $tier1.systemuserid }
$profiles = @()
foreach ($profileDef in $security.columnSecurityProfiles) {
    Write-Step "Column security profile '$($profileDef.name)'"
    $publish = @()
    foreach ($col in $profileDef.columns) {
        $path = "EntityDefinitions(LogicalName='$($col.table)')/Attributes(LogicalName='$($col.column)')"
        $attr = (DV GET "$path`?`$select=LogicalName,IsSecured,CanBeSecuredForRead,AttributeType").Body
        if (-not $attr.CanBeSecuredForRead) { throw "$($col.table).$($col.column) cannot be secured for read." }
        if (-not $attr.IsSecured) {
            $full = (DV GET "$path/Microsoft.Dynamics.CRM.StringAttributeMetadata").Body
            $full.PSObject.Properties.Remove('@odata.context')
            $full.IsSecured = $true
            $null = DV PUT $path $full -Headers @{ 'MSCRM.MergeLabels' = 'true' }
            $publish += $col.table
            Write-Step "  secured $($col.table).$($col.column)"
        }
    }
    foreach ($table in ($publish | Select-Object -Unique)) {
        $null = DV POST 'PublishXml' @{ ParameterXml = "<importexportxml><entities><entity>$table</entity></entities></importexportxml>" }
    }
    $profile = (DV GET "fieldsecurityprofiles?`$select=fieldsecurityprofileid,name&`$filter=name eq $(Lit $profileDef.name)").Body.value | Select-Object -First 1
    $profileId = if ($profile) { $profile.fieldsecurityprofileid } else {
        $r = DV POST 'fieldsecurityprofiles' @{ name = $profileDef.name; description = $profileDef.description }
        Get-EntityIdFromHeader $r.Headers
    }
    $existingPermissions = @((DV GET "fieldpermissions?`$select=fieldpermissionid,entityname,attributelogicalname,canread,cancreate,canupdate,canreadunmasked&`$filter=_fieldsecurityprofileid_value eq $profileId").Body.value)
    foreach ($col in $profileDef.columns) {
        $wanted = $profileDef.permissions
        $perm = $existingPermissions | Where-Object { $_.entityname -eq $col.table -and $_.attributelogicalname -eq $col.column } | Select-Object -First 1
        $values = @{ canread = [int]$wanted.canread; cancreate = [int]$wanted.cancreate; canupdate = [int]$wanted.canupdate; canreadunmasked = [int]$wanted.canreadunmasked }
        if (-not $perm) {
            $body = $values.Clone()
            $body.entityname = $col.table
            $body.attributelogicalname = $col.column
            $body['fieldsecurityprofileid@odata.bind'] = "/fieldsecurityprofiles($profileId)"
            $null = DV POST 'fieldpermissions' $body
        }
        elseif ($perm.canread -ne $values.canread -or $perm.cancreate -ne $values.cancreate -or $perm.canupdate -ne $values.canupdate) {
            $null = DV PATCH "fieldpermissions($($perm.fieldpermissionid))" $values
        }
    }
    $memberIds = @((DV GET "fieldsecurityprofiles($profileId)/systemuserprofiles_association?`$select=systemuserid").Body.value | ForEach-Object { $_.systemuserid })
    foreach ($member in $profileDef.members) {
        $id = $principalIds[$member]
        if ($id -and $memberIds -notcontains $id) {
            $null = DV POST "systemusers($id)/systemuserprofiles_association/`$ref" @{ '@odata.id' = "$api/fieldsecurityprofiles($profileId)" }
        }
    }
    foreach ($outsider in $profileDef.neverMembers) {
        $id = $principalIds[$outsider]
        if ($id -and $memberIds -contains $id) {
            $null = DV DELETE "systemusers($id)/systemuserprofiles_association($profileId)/`$ref"
            Write-Step "  removed $outsider from the profile"
        }
    }
    Write-Step "  $($profileDef.columns.Count) columns; members: $($profileDef.members -join ', ')"
    $profiles += [pscustomobject]@{ Name = $profileDef.name; Id = $profileId; Columns = @($profileDef.columns | ForEach-Object { "$($_.table).$($_.column)" }) }
}

# ==== 7. App sharing
$app = (DV GET "appmodules?`$select=appmoduleid&`$filter=uniquename eq '$AppUniqueName'").Body.value | Select-Object -First 1
if ($app) {
    $appRoles = @((DV GET "appmodules($($app.appmoduleid))/appmoduleroles_association?`$select=roleid").Body.value | ForEach-Object { $_.roleid })
    foreach ($roleName in $security.assignments.appRoles) {
        $roleId = Get-RoleId $roleName
        if ($roleId -and $appRoles -notcontains $roleId) {
            $null = DV POST "appmodules($($app.appmoduleid))/appmoduleroles_association/`$ref" @{ '@odata.id' = "$api/roles($roleId)" }
        }
    }
    Write-Step "  Service Desk app shared with $($security.assignments.appRoles -join ', ')"
}
else { throw "The app $AppUniqueName was not found; deploy the schema first." }

[pscustomobject]@{
    McpApplicationUserId    = $mcpUser.systemuserid
    McpRoles                = $mcpRoles
    SeniorUserId            = $senior.systemuserid
    SeniorRoles             = $seniorRoles
    Tier1UserId             = if ($tier1) { $tier1.systemuserid } else { $null }
    Tier1Roles              = $tier1Roles
    RegulatedBusinessUnitId = ($buIds.Values | Select-Object -First 1)
    ColumnSecurityProfiles  = $profiles
    Warnings                = @($warnings)
}
