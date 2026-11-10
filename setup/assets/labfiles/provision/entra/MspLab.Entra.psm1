#Requires -Version 7.0
<#
    Microsoft Entra work for one participant tenant: the bootstrap of the certificate-based setup
    app, the gateway and Purview app registrations, directory role changes, and the final stripping
    of the setup app's privileges. Every call is Microsoft Graph REST; no Graph PowerShell module.

    Bootstrap identities (used once, only to create the setup app and grant it its rights):
      ServicePrincipal  a per-tenant service principal supplied by CloudLabs (preferred). Its secret
                        reaches the VM through Key Vault, never through userData, and the last
                        provisioning step deletes it. Needs Application.ReadWrite.All,
                        AppRoleAssignment.ReadWrite.All and RoleManagement.ReadWrite.Directory
                        (application), or the Global Administrator role.
      Password          the ODL user (a Global Administrator during provisioning) through the
                        resource owner password grant of the Azure CLI public client. Works only with
                        a real password and no MFA requirement on the account; a Temporary Access
                        Pass cannot be used this way.
      AzureCli          the current 'az login' session of a Global Administrator (support re-runs).
    Registering the setup app with Power Platform needs a user sign-in (Password or AzureCli, or the
    ODL password beside a service principal bootstrap). When none works, a CloudLabs service principal
    that CloudLabs registered with Power Platform is used for the Power Platform calls instead.
#>

$script:GraphAppId = '00000003-0000-0000-c000-000000000000'
$script:ExchangeOnlineAppId = '00000002-0000-0ff1-ce00-000000000000'
$script:ExchangeProtectionAppId = '00000007-0000-0ff1-ce00-000000000000'
$script:AzureCliClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'
$script:GlobalAdministratorTemplateId = '62e90394-69f5-4237-9190-012177145e10'
$script:BootstrapCache = @{}

# ==== Bootstrap tokens

function ConvertTo-TokenScope {
    param([Parameter(Mandatory)][string]$Resource)
    if ($Resource -match '/\.default$') { return $Resource }
    if ($Resource -eq 'https://service.powerapps.com/') { return 'https://service.powerapps.com//.default' }
    return $Resource.TrimEnd('/') + '/.default'
}

function Get-BootstrapToken {
    <# Token of the bootstrap identity for a resource. $Context comes from Resolve-BootstrapContext. #>
    param([Parameter(Mandatory)][hashtable]$Context, [Parameter(Mandatory)][string]$Resource)
    $scope = ConvertTo-TokenScope $Resource
    $key = "$($Context.Mode)|$scope"
    $cached = $script:BootstrapCache[$key]
    if ($cached -and $cached.Expires -gt (Get-Date).AddMinutes(5)) { return $cached.Token }
    $tokenUri = "https://login.microsoftonline.com/$($Context.TenantId)/oauth2/v2.0/token"
    switch ($Context.Mode) {
        'ServicePrincipal' {
            $body = @{ client_id = $Context.AppId; scope = $scope; grant_type = 'client_credentials'
                       client_secret = [Net.NetworkCredential]::new('', $Context.AppSecret).Password }
            $r = Invoke-RestMethod -Method Post -Uri $tokenUri -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec 60
            $token = $r.access_token; $expires = (Get-Date).AddSeconds([int]$r.expires_in)
        }
        'Password' {
            if (-not $env:MSPLAB_SIGNIN_SECRET) { throw 'MSPLAB_SIGNIN_SECRET is not set; the Password bootstrap runs only at first boot.' }
            $body = @{ client_id = $script:AzureCliClientId; scope = $scope; grant_type = 'password'
                       username = $Context.UserName; password = $env:MSPLAB_SIGNIN_SECRET }
            try {
                $r = Invoke-RestMethod -Method Post -Uri $tokenUri -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec 60
            }
            catch {
                $detail = $_.ErrorDetails.Message
                $code = if ($detail -match '(AADSTS\d+)') { $Matches[1] } else { 'no AADSTS code' }
                throw ("The ODL credential cannot sign in without interaction ($code). It may be a Temporary Access Pass, or MFA or " +
                       'Conditional Access applies to the account. Supply a bootstrap service principal (bootstrapAppId and ' +
                       'bootstrapAppSecret), or bootstrap interactively: setup/tenant/RUNBOOK.md, Bootstrap by hand.')
            }
            $token = $r.access_token; $expires = (Get-Date).AddSeconds([int]$r.expires_in)
        }
        'AzureCli' {
            $saved = $env:AZURE_CONFIG_DIR
            try {
                if ($Context.AzureConfigDir) { $env:AZURE_CONFIG_DIR = $Context.AzureConfigDir } else { Remove-Item Env:\AZURE_CONFIG_DIR -ErrorAction SilentlyContinue }
                $json = & az account get-access-token --resource $Resource --tenant $Context.TenantId --output json 2>$null
                if ($LASTEXITCODE -or -not $json) { throw "az account get-access-token --resource $Resource failed. Run 'az login --tenant $($Context.TenantId) --allow-no-subscriptions' as a Global Administrator first." }
                $r = $json | ConvertFrom-Json
                $token = $r.accessToken; $expires = [datetime]$r.expiresOn
            }
            finally { if ($saved) { $env:AZURE_CONFIG_DIR = $saved } }
        }
        default { throw "Unknown bootstrap mode $($Context.Mode)." }
    }
    $script:BootstrapCache[$key] = @{ Token = $token; Expires = $expires }
    return $token
}

function Resolve-BootstrapContext {
    <#
        Chooses the bootstrap identity. Auto: the CloudLabs service principal when its application
        ID tag and its Key Vault secret are present, else the ODL password (first boot), else the
        current Azure CLI session.
    #>
    param(
        [ValidateSet('Auto', 'ServicePrincipal', 'Password', 'AzureCli')][string]$Mode = 'Auto',
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$UserName,
        [string]$VaultUri,
        [string]$AzureConfigDir
    )
    $appId = Get-LabTag 'msplab-bootstrap-app-id'
    $context = @{ TenantId = $TenantId; UserName = $UserName; AzureConfigDir = $AzureConfigDir; Mode = $Mode; Reason = '' }
    if ($Mode -in 'Auto', 'ServicePrincipal' -and $appId -and $VaultUri) {
        $secret = Get-KeyVaultSecret -VaultUri $VaultUri -Name 'setup-bootstrap-secret'
        if ($secret) {
            $context.Mode = 'ServicePrincipal'; $context.AppId = $appId; $context.AppSecret = $secret
            $context.Reason = "CloudLabs bootstrap service principal $appId (secret read from Key Vault)"
            return $context
        }
        if ($Mode -eq 'ServicePrincipal') { throw 'The bootstrap service principal secret is not in Key Vault (setup-bootstrap-secret). The last provisioning step deletes it; use -Bootstrap AzureCli for a re-run.' }
    }
    elseif ($Mode -eq 'ServicePrincipal') { throw 'No bootstrap service principal was supplied (VM tag msplab-bootstrap-app-id is empty).' }
    if ($Mode -in 'Auto', 'Password' -and $env:MSPLAB_SIGNIN_SECRET) {
        $context.Mode = 'Password'; $context.Reason = "ODL user $UserName (resource owner password grant)"
        return $context
    }
    if ($Mode -eq 'Password') { throw 'MSPLAB_SIGNIN_SECRET is not set; the Password bootstrap runs only at first boot.' }
    $context.Mode = 'AzureCli'; $context.Reason = 'the current Azure CLI session'
    return $context
}

# ==== Service principals, app roles and directory roles

function Get-ServicePrincipalByAppId {
    param([Parameter(Mandatory)][string]$AppId, [Parameter(Mandatory)][string]$Token, [switch]$Create)
    $found = @(Invoke-Graph -Method GET -Path "servicePrincipals?`$filter=appId eq '$AppId'&`$select=id,appId,displayName,appRoles,oauth2PermissionScopes" -Token $Token -All)
    if ($found.Count) { return $found[0] }
    if (-not $Create) { return $null }
    $r = Invoke-Graph -Method POST -Path 'servicePrincipals' -Token $Token -Body @{ appId = $AppId }
    return $r.Body
}

function Grant-AppRole {
    <# Grants one application permission (app role) of a resource API to a service principal. Idempotent. #>
    param(
        [Parameter(Mandatory)][string]$PrincipalSpId,
        [Parameter(Mandatory)]$ResourceSp,
        [Parameter(Mandatory)][string]$RoleValue,
        [Parameter(Mandatory)][string]$Token,
        [switch]$Optional
    )
    $role = @($ResourceSp.appRoles | Where-Object { $_.value -eq $RoleValue -and $_.allowedMemberTypes -contains 'Application' }) | Select-Object -First 1
    if (-not $role) {
        if ($Optional) { Write-Step "  $($ResourceSp.displayName) has no application permission $RoleValue; skipped."; return $null }
        throw "$($ResourceSp.displayName) has no application permission $RoleValue in this tenant."
    }
    $existing = @(Invoke-Graph -Method GET -Path "servicePrincipals/$PrincipalSpId/appRoleAssignments" -Token $Token -All |
        Where-Object { $_.appRoleId -eq $role.id -and $_.resourceId -eq $ResourceSp.id })
    if (-not $existing.Count) {
        $null = Invoke-Graph -Method POST -Path "servicePrincipals/$($ResourceSp.id)/appRoleAssignedTo" -Token $Token -Body @{
            principalId = $PrincipalSpId; resourceId = $ResourceSp.id; appRoleId = $role.id }
    }
    return $role.id
}

function Get-DirectoryRoleDefinition {
    param([Parameter(Mandatory)][string]$DisplayName, [Parameter(Mandatory)][string]$Token)
    $escaped = $DisplayName.Replace("'", "''")
    $definition = @(Invoke-Graph -Method GET -Path "roleManagement/directory/roleDefinitions?`$filter=displayName eq '$escaped'&`$select=id,displayName,templateId" -Token $Token -All) |
        Select-Object -First 1
    if (-not $definition) { throw "Directory role '$DisplayName' was not found." }
    return $definition
}

function Get-DirectoryRoleAssignments {
    <# Active directory role assignments of one principal, with the role names. #>
    param([Parameter(Mandatory)][string]$PrincipalId, [Parameter(Mandatory)][string]$Token)
    $assignments = @(Invoke-Graph -Method GET -Path "roleManagement/directory/roleAssignments?`$filter=principalId eq '$PrincipalId'&`$expand=roleDefinition(`$select=displayName,templateId)" -Token $Token -All)
    foreach ($a in $assignments) {
        [pscustomobject]@{ Id = $a.id; RoleDefinitionId = $a.roleDefinitionId; Role = $a.roleDefinition.displayName; Scope = $a.directoryScopeId }
    }
}

function Add-DirectoryRole {
    <# Assigns a directory role to a principal at tenant scope. Idempotent. #>
    param([Parameter(Mandatory)][string]$PrincipalId, [Parameter(Mandatory)][string]$RoleName, [Parameter(Mandatory)][string]$Token)
    $definition = Get-DirectoryRoleDefinition -DisplayName $RoleName -Token $Token
    $current = @(Get-DirectoryRoleAssignments -PrincipalId $PrincipalId -Token $Token)
    if (@($current | Where-Object { $_.RoleDefinitionId -eq $definition.id -and $_.Scope -eq '/' }).Count) { return 'existing' }
    try {
        $null = Invoke-Graph -Method POST -Path 'roleManagement/directory/roleAssignments' -Token $Token -Body @{
            principalId = $PrincipalId; roleDefinitionId = $definition.id; directoryScopeId = '/' }
        return 'assigned'
    }
    catch {
        # Delegated bootstrap tokens without RoleManagement.ReadWrite.Directory: the directoryRoles API.
        Write-Step "  roleManagement assignment refused ($($_.Exception.Message)); trying the directoryRoles API."
        $templateId = if ($definition.templateId) { $definition.templateId } else { $definition.id }
        $role = Invoke-Graph -Method GET -Path "directoryRoles(roleTemplateId='$templateId')" -Token $Token -AllowNotFound
        if ($role.Status -eq 404) { $role = Invoke-Graph -Method POST -Path 'directoryRoles' -Token $Token -Body @{ roleTemplateId = $templateId } }
        $null = Invoke-Graph -Method POST -Path "directoryRoles/$($role.Body.id)/members/`$ref" -Token $Token -AllowStatus 400 -Body @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$PrincipalId" }
        return 'assigned (directoryRoles)'
    }
}

function Remove-DirectoryRoles {
    <# Removes every directory role assignment of a principal (or only the named roles). Returns the removed role names. #>
    param([Parameter(Mandatory)][string]$PrincipalId, [Parameter(Mandatory)][string]$Token, [string[]]$RoleNames = @())
    $removed = @()
    foreach ($a in @(Get-DirectoryRoleAssignments -PrincipalId $PrincipalId -Token $Token)) {
        if ($RoleNames.Count -and $a.Role -notin $RoleNames) { continue }
        $null = Invoke-Graph -Method DELETE -Path "roleManagement/directory/roleAssignments/$($a.Id)" -Token $Token -AllowNotFound
        $removed += $a.Role
    }
    return $removed
}

# ==== Applications

function Get-ApplicationByName {
    param([Parameter(Mandatory)][string]$DisplayName, [Parameter(Mandatory)][string]$Token)
    $escaped = $DisplayName.Replace("'", "''")
    return @(Invoke-Graph -Method GET -Path "applications?`$filter=displayName eq '$escaped'" -Token $Token -All) | Select-Object -First 1
}

function New-AppPassword {
    <# Adds a client secret, after removing older secrets with the same display name. Returns @{ KeyId; Value (SecureString) }. #>
    param([Parameter(Mandatory)][string]$AppObjectId, [Parameter(Mandatory)][string]$DisplayName, [Parameter(Mandatory)][string]$Token,
          [double]$Days = 14, [switch]$KeepExisting)
    if (-not $KeepExisting) {
        $app = (Invoke-Graph -Method GET -Path "applications/$($AppObjectId)?`$select=passwordCredentials" -Token $Token).Body
        foreach ($p in @($app.passwordCredentials | Where-Object { $_.displayName -eq $DisplayName })) {
            $null = Invoke-Graph -Method POST -Path "applications/$AppObjectId/removePassword" -Token $Token -Body @{ keyId = $p.keyId }
        }
    }
    $r = Invoke-Graph -Method POST -Path "applications/$AppObjectId/addPassword" -Token $Token -Body @{
        passwordCredential = @{ displayName = $DisplayName; endDateTime = (Get-Date).ToUniversalTime().AddDays($Days).ToString('yyyy-MM-ddTHH:mm:ssZ') } }
    return @{ KeyId = $r.Body.keyId; Value = (ConvertTo-SecureString -String $r.Body.secretText -AsPlainText -Force) }
}

function Remove-AppPassword {
    param([Parameter(Mandatory)][string]$AppObjectId, [Parameter(Mandatory)][string]$KeyId, [Parameter(Mandatory)][string]$Token)
    $null = Invoke-Graph -Method POST -Path "applications/$AppObjectId/removePassword" -Token $Token -Body @{ keyId = $KeyId } -AllowStatus 400, 404
}

function New-SetupCertificate {
    <#
        Creates the setup app's certificate in Cert:\LocalMachine\My: RSA 2048, SHA-256, a CryptoAPI
        key (Security & Compliance PowerShell does not support CNG keys) that cannot be exported.
        Created through Windows PowerShell, whose PKI module is native. Returns the thumbprint.
    #>
    param([Parameter(Mandatory)][string]$Subject, [int]$Days = 7)
    $command = "`$c = New-SelfSignedCertificate -Subject 'CN=$Subject' -CertStoreLocation 'Cert:\LocalMachine\My' " +
        "-KeyExportPolicy NonExportable -KeySpec KeyExchange -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256 " +
        "-Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider' -NotAfter (Get-Date).AddDays($Days) " +
        "-FriendlyName 'Relecloud lab setup app (removed when provisioning ends)'; `$c.Thumbprint"
    $thumbprint = (& powershell.exe -NoProfile -NonInteractive -Command $command | Select-Object -Last 1)
    if ("$thumbprint" -notmatch '^[0-9A-Fa-f]{40}$') { throw "Creating the setup certificate failed: $thumbprint" }
    return "$thumbprint".Trim()
}

function Initialize-SetupApp {
    <#
        Creates (or repairs) the setup app with the bootstrap identity: certificate, application and
        service principal, Graph application permissions, Exchange.ManageAsApp, the directory roles in
        LabConfig.psd1, read-only Graph permissions for id-prov (readiness), and, with a user context,
        the Power Platform management registration. Returns a summary hashtable.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Context,
        [Parameter(Mandatory)][string]$DeploymentId,
        [Parameter(Mandatory)][string]$ProvisioningClientId
    )
    $config = Get-LabConfig
    $token = Get-BootstrapToken -Context $Context -Resource 'https://graph.microsoft.com'
    $displayName = "$($config.SetupAppName) $DeploymentId"
    $info = Get-SetupAppInfo
    $graphSp = Get-ServicePrincipalByAppId -AppId $script:GraphAppId -Token $token -Create

    # ==== Certificate (reuse while valid; otherwise a new one replaces the app's key)
    $cert = $null
    if ($info -and -not $info.stripped) { $cert = Get-SetupAppCertificate }
    $newCertificate = $false
    if (-not $cert) {
        $thumbprint = New-SetupCertificate -Subject $displayName -Days $config.SetupCertificateDays
        $cert = Get-Item -Path "Cert:\LocalMachine\My\$thumbprint"
        $newCertificate = $true
    }
    $keyCredential = @{
        type = 'AsymmetricX509Cert'; usage = 'Verify'; key = [Convert]::ToBase64String($cert.RawData)
        displayName = "CN=$displayName"
        endDateTime = $cert.NotAfter.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    # ==== Application and service principal
    $app = Get-ApplicationByName -DisplayName $displayName -Token $token
    if (-not $app) {
        $app = (Invoke-Graph -Method POST -Path 'applications' -Token $token -Body @{
            displayName = $displayName; signInAudience = 'AzureADMyOrg'; keyCredentials = @($keyCredential)
            notes = 'Relecloud lab provisioning identity for this tenant. Certificate key on the lab VM only; every privilege is removed when provisioning ends.'
        }).Body
    }
    elseif ($newCertificate -or -not @($app.keyCredentials).Count) {
        $null = Invoke-Graph -Method PATCH -Path "applications/$($app.id)" -Token $token -Body @{ keyCredentials = @($keyCredential) }
    }
    $sp = Get-ServicePrincipalByAppId -AppId $app.appId -Token $token
    if (-not $sp) { $sp = (Invoke-Graph -Method POST -Path 'servicePrincipals' -Token $token -Body @{ appId = $app.appId }).Body }

    # ==== Application permissions
    $graphRoleIds = foreach ($value in $config.SetupAppGraphRoles) { Grant-AppRole -PrincipalSpId $sp.id -ResourceSp $graphSp -RoleValue $value -Token $token }
    $exchangeGranted = @()
    foreach ($exchangeAppId in @($script:ExchangeProtectionAppId, $script:ExchangeOnlineAppId)) {
        try {
            $resource = Get-ServicePrincipalByAppId -AppId $exchangeAppId -Token $token -Create
            if (Grant-AppRole -PrincipalSpId $sp.id -ResourceSp $resource -RoleValue 'Exchange.ManageAsApp' -Token $token -Optional) { $exchangeGranted += $resource.displayName }
        }
        catch { Write-Step "  Exchange.ManageAsApp on $exchangeAppId not granted: $($_.Exception.Message)" }
    }
    if (-not $exchangeGranted.Count) { throw 'Exchange.ManageAsApp could not be granted; Security & Compliance PowerShell would refuse the setup app.' }
    $null = Invoke-Graph -Method PATCH -Path "applications/$($app.id)" -Token $token -Body @{
        requiredResourceAccess = @(@{ resourceAppId = $script:GraphAppId; resourceAccess = @($graphRoleIds | ForEach-Object { @{ id = $_; type = 'Role' } }) }) }

    # ==== Directory roles (Security & Compliance PowerShell maps them to role groups)
    $roleResults = foreach ($roleName in $config.SetupAppDirectoryRoles) { "$roleName $(Add-DirectoryRole -PrincipalId $sp.id -RoleName $roleName -Token $token)" }

    # ==== Read-only Graph permissions for id-prov, used by the participant's readiness check.
    # Granted before id-prov ever asks for a Graph token: managed identity tokens are cached for
    # about 24 hours, so a grant after the first token would not show up in time.
    $provSp = Get-ServicePrincipalByAppId -AppId $ProvisioningClientId -Token $token
    if (-not $provSp) { throw "The service principal of id-prov ($ProvisioningClientId) was not found." }
    foreach ($value in $config.ProvisioningGraphRoles) { $null = Grant-AppRole -PrincipalSpId $provSp.id -ResourceSp $graphSp -RoleValue $value -Token $token }

    # ==== Power Platform: register the setup app as a management application. Power Platform accepts
    # this only from a user sign-in of a tenant administrator (a service principal can't register an
    # app), so it uses the bootstrap's user context, or the ODL password when the bootstrap ran as a
    # service principal. Not fatal here: the environment step reports it when no registered identity exists.
    $powerPlatform = 'not registered'
    $powerPlatformNote = ''
    if ($info -and $info.powerPlatform -eq 'registered' -and $info.appId -eq $app.appId) { $powerPlatform = 'registered' }
    else {
        $userContext = if ($Context.Mode -in 'Password', 'AzureCli') { $Context }
                       elseif ($env:MSPLAB_SIGNIN_SECRET) { @{ Mode = 'Password'; TenantId = $Context.TenantId; UserName = $Context.UserName; AzureConfigDir = '' } }
                       else { $null }
        if ($userContext) {
            try {
                $userToken = Get-BootstrapToken -Context $userContext -Resource 'https://service.powerapps.com/'
                $null = Invoke-WithRetry -What 'Power Platform management app registration' -Attempts 4 -DelaySeconds 20 -Action {
                    Invoke-LabRest -Method PUT -Token $userToken `
                        -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/adminApplications/$($app.appId)?api-version=2020-10-01"
                }
                $powerPlatform = 'registered'
            }
            catch { $powerPlatformNote = ConvertTo-SafeText $_.Exception.Message 300; Write-Step "  Power Platform registration not possible: $powerPlatformNote" }
        }
        else { $powerPlatformNote = 'no user sign-in available (service principal bootstrap and no ODL password)' }
    }

    $tenant = (Invoke-Graph -Method GET -Path 'organization?$select=id,verifiedDomains' -Token $token).Body.value | Select-Object -First 1
    $initialDomain = (@($tenant.verifiedDomains) | Where-Object { $_.isInitial } | Select-Object -First 1).name
    $record = [ordered]@{
        tenantId = $Context.TenantId; appId = $app.appId; objectId = $app.id; servicePrincipalId = $sp.id
        thumbprint = $cert.Thumbprint; certificateExpires = $cert.NotAfter.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        initialDomain = $initialDomain; bootstrap = $Context.Mode; powerPlatform = $powerPlatform; stripped = $false
        createdOn = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    Save-SetupAppInfo -Info $record

    # ==== The setup app's own token must work before the next steps (permissions replicate)
    $null = Invoke-WithRetry -What 'first setup app call' -Attempts 12 -DelaySeconds 15 -Action {
        $appToken = Get-SetupAppToken -Resource 'https://graph.microsoft.com' -Fresh
        $null = Invoke-Graph -Method GET -Path "applications/$($app.id)?`$select=id" -Token $appToken
        $null = Invoke-Graph -Method GET -Path 'users?$top=1&$select=id' -Token $appToken
    }
    return @{ AppId = $app.appId; ServicePrincipalId = $sp.id; Exchange = ($exchangeGranted -join ', '); Roles = ($roleResults -join '; ')
              PowerPlatform = $powerPlatform; PowerPlatformNote = $powerPlatformNote; InitialDomain = $initialDomain; NewCertificate = $newCertificate }
}

# ==== Gateway app (OAuth client and audience of the MCP gateway)

function Set-GatewayApp {
    <#
        Creates or updates the gateway app registration: delegated scope ServiceDesk.Access, v2
        tokens, identifier URIs (the deterministic audience from the template, and api://<appId>),
        Microsoft Graph sign-in scopes, and tenant-wide (AllPrincipals) consent for both.
    #>
    param([Parameter(Mandatory)][string]$Token, [Parameter(Mandatory)][string]$Audience, [string[]]$RedirectUris = @())
    $config = Get-LabConfig
    $scopeValue = $config.GatewayScope
    $app = Get-ApplicationByName -DisplayName $config.GatewayAppName -Token $Token
    if (-not $app) {
        $app = (Invoke-Graph -Method POST -Path 'applications' -Token $Token -Body @{
            displayName = $config.GatewayAppName; signInAudience = 'AzureADMyOrg'
            notes = 'Audience and OAuth client of the Relecloud Service Desk MCP gateway (API Management). The Foundry MCP connections use it for OAuth identity passthrough.'
            api = @{ requestedAccessTokenVersion = 2 }
        }).Body
    }
    $existingScope = @($app.api.oauth2PermissionScopes | Where-Object { $_.value -eq $scopeValue }) | Select-Object -First 1
    $scopeId = if ($existingScope) { $existingScope.id } else { [guid]::NewGuid().ToString() }
    $scopes = @(@($app.api.oauth2PermissionScopes | Where-Object { $_.value -ne $scopeValue }) + @(@{
        id = $scopeId; type = 'Admin'; value = $scopeValue; isEnabled = $true
        adminConsentDisplayName = 'Use the Relecloud Service Desk tools as the signed-in technician'
        adminConsentDescription = 'Lets the Service Desk agent call the MCP gateway on behalf of the signed-in technician. Dataverse decides what each technician may do.'
        userConsentDisplayName = 'Use the Service Desk tools as you'
        userConsentDescription = 'Lets the Service Desk agent call the Service Desk tools on your behalf.'
    }))
    $uris = @(@($app.web.redirectUris) + $RedirectUris | Where-Object { $_ } | Select-Object -Unique)
    $null = Invoke-Graph -Method PATCH -Path "applications/$($app.id)" -Token $Token -Body @{
        api = @{ requestedAccessTokenVersion = 2; oauth2PermissionScopes = $scopes }
        web = @{ redirectUris = $uris }
    }
    $identifierUris = @($Audience, "api://$($app.appId)")
    try { $null = Invoke-Graph -Method PATCH -Path "applications/$($app.id)" -Token $Token -Body @{ identifierUris = $identifierUris } }
    catch { throw "Setting the identifier URIs $($identifierUris -join ', ') failed: $($_.Exception.Message). The MCP Gateway Audience output must be accepted as an identifier URI in this tenant." }
    $null = Invoke-Graph -Method PATCH -Path "applications/$($app.id)" -Token $Token -Body @{
        requiredResourceAccess = @(
            @{ resourceAppId = $app.appId; resourceAccess = @(@{ id = $scopeId; type = 'Scope' }) },
            @{ resourceAppId = $script:GraphAppId; resourceAccess = @(
                @{ id = '37f7f235-527c-4136-accd-4a02d197296e'; type = 'Scope' },
                @{ id = '14dad69e-099b-42c9-810b-d002981feec1'; type = 'Scope' },
                @{ id = '7427e0e9-2fba-42fe-b0c0-848c9e6a8182'; type = 'Scope' }) }
        ) }
    $sp = Get-ServicePrincipalByAppId -AppId $app.appId -Token $Token
    if (-not $sp) { $sp = (Invoke-Graph -Method POST -Path 'servicePrincipals' -Token $Token -Body @{ appId = $app.appId }).Body }
    $graphSp = Get-ServicePrincipalByAppId -AppId $script:GraphAppId -Token $Token
    foreach ($grant in @(@{ Resource = $sp.id; Scope = $scopeValue }, @{ Resource = $graphSp.id; Scope = 'openid profile offline_access' })) {
        $existing = @(Invoke-Graph -Method GET -Path "oauth2PermissionGrants?`$filter=clientId eq '$($sp.id)' and resourceId eq '$($grant.Resource)'" -Token $Token -All) |
            Where-Object { $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1
        if ($existing) { $null = Invoke-Graph -Method PATCH -Path "oauth2PermissionGrants/$($existing.id)" -Token $Token -Body @{ scope = $grant.Scope } }
        else { $null = Invoke-Graph -Method POST -Path 'oauth2PermissionGrants' -Token $Token -Body @{ clientId = $sp.id; consentType = 'AllPrincipals'; resourceId = $grant.Resource; scope = $grant.Scope } }
    }
    return @{ AppId = $app.appId; ObjectId = $app.id; ServicePrincipalId = $sp.id; ScopeId = $scopeId; IdentifierUris = $identifierUris; RedirectUris = $uris }
}

function Add-GatewayRedirectUris {
    param([Parameter(Mandatory)][string]$AppObjectId, [Parameter(Mandatory)][string[]]$Uris, [Parameter(Mandatory)][string]$Token)
    $app = (Invoke-Graph -Method GET -Path "applications/$($AppObjectId)?`$select=web" -Token $Token).Body
    $all = @(@($app.web.redirectUris) + $Uris | Where-Object { $_ } | Select-Object -Unique)
    $null = Invoke-Graph -Method PATCH -Path "applications/$AppObjectId" -Token $Token -Body @{ web = @{ redirectUris = $all } }
    return $all
}

function Get-GatewayUserToken {
    <#
        A delegated token of the ODL user for the gateway scope, issued to the gateway app, for the
        readiness check's call through the read gateway. Needs the ODL password (first boot). Uses
        a client secret that lives one hour and is removed right after.
    #>
    param([Parameter(Mandatory)][string]$TenantId, [Parameter(Mandatory)][string]$UserName, [Parameter(Mandatory)][string]$GatewayAppId,
          [Parameter(Mandatory)][string]$GatewayAppObjectId, [Parameter(Mandatory)][string]$Audience, [Parameter(Mandatory)][string]$Scope)
    if (-not $env:MSPLAB_SIGNIN_SECRET) { return $null }
    $graphToken = Get-SetupAppToken -Resource 'https://graph.microsoft.com'
    $secret = New-AppPassword -AppObjectId $GatewayAppObjectId -DisplayName 'Readiness check (removed after use)' -Token $graphToken -Days 0.05 -KeepExisting
    try {
        $body = @{ client_id = $GatewayAppId; client_secret = [Net.NetworkCredential]::new('', $secret.Value).Password
                   grant_type = 'password'; username = $UserName; password = $env:MSPLAB_SIGNIN_SECRET; scope = "$($Audience.TrimEnd('/'))/$Scope" }
        return Invoke-WithRetry -What 'user token for the read gateway' -Attempts 6 -DelaySeconds 10 -Action {
            (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec 60).access_token
        }
    }
    finally { Remove-AppPassword -AppObjectId $GatewayAppObjectId -KeyId $secret.KeyId -Token $graphToken }
}

# ==== Purview integration app

function Set-PurviewApp {
    <# Creates or updates the Purview integration app (least-privileged Graph application permissions) and its consent. #>
    param([Parameter(Mandatory)][string]$Token)
    $config = Get-LabConfig
    $app = Get-ApplicationByName -DisplayName $config.PurviewAppName -Token $Token
    if (-not $app) {
        $app = (Invoke-Graph -Method POST -Path 'applications' -Token $Token -Body @{
            displayName = $config.PurviewAppName; signInAudience = 'AzureADMyOrg'
            notes = 'The Relecloud Service Desk MCP server sends tool results to Microsoft Purview (processContent) as this app. The DLP policy for the agent is scoped to it.'
        }).Body
    }
    $sp = Get-ServicePrincipalByAppId -AppId $app.appId -Token $Token
    if (-not $sp) { $sp = (Invoke-Graph -Method POST -Path 'servicePrincipals' -Token $Token -Body @{ appId = $app.appId }).Body }
    $graphSp = Get-ServicePrincipalByAppId -AppId $script:GraphAppId -Token $Token
    $roleIds = @(foreach ($value in $config.PurviewAppGraphRoles) { Grant-AppRole -PrincipalSpId $sp.id -ResourceSp $graphSp -RoleValue $value -Token $Token })
    $optional = @()
    foreach ($value in $config.PurviewAppOptionalRoles) {
        $id = Grant-AppRole -PrincipalSpId $sp.id -ResourceSp $graphSp -RoleValue $value -Token $Token -Optional
        if ($id) { $roleIds += $id; $optional += $value }
    }
    $null = Invoke-Graph -Method PATCH -Path "applications/$($app.id)" -Token $Token -Body @{
        requiredResourceAccess = @(@{ resourceAppId = $script:GraphAppId; resourceAccess = @($roleIds | ForEach-Object { @{ id = $_; type = 'Role' } }) }) }
    return @{ AppId = $app.appId; ObjectId = $app.id; ServicePrincipalId = $sp.id; Permissions = @($config.PurviewAppGraphRoles + $optional) }
}

# ==== Users

function Resolve-LabUser {
    <# Finds a user by object ID or UPN, waiting while CloudLabs creates it. #>
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Token, [int]$WaitMinutes = 30)
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    do {
        $r = Invoke-Graph -Method GET -Path "users/$([uri]::EscapeDataString($Id))?`$select=id,userPrincipalName,displayName,accountEnabled,usageLocation" -Token $Token -AllowNotFound
        if ($r.Status -ne 404) {
            $licenses = @(Invoke-Graph -Method GET -Path "users/$($r.Body.id)/licenseDetails?`$select=skuPartNumber,servicePlans" -Token $Token -All)
            return [pscustomobject]@{
                Id = $r.Body.id; UserPrincipalName = $r.Body.userPrincipalName; DisplayName = $r.Body.displayName
                Enabled = [bool]$r.Body.accountEnabled; Skus = @($licenses.skuPartNumber)
                ServicePlans = @($licenses | ForEach-Object { @($_.servicePlans | Where-Object { $_.provisioningStatus -ne 'Disabled' }).servicePlanName })
            }
        }
        Write-Step "  waiting for $Id to exist in the tenant"
        Start-Sleep -Seconds 30
    } while ((Get-Date) -lt $deadline)
    throw "User $Id does not exist after $WaitMinutes minutes. CloudLabs creates it from setup/scripts/user-creation.json."
}

function Remove-ParticipantAdministratorRoles {
    <#
        Removes every directory role from the participant (the ODL user). A Global Administrator
        cannot remove their own role, so the setup app does it. With -RequireOtherGlobalAdministrator
        it refuses when no other enabled user holds Global Administrator, so the tenant always keeps a
        supplier administrator.
    #>
    param([Parameter(Mandatory)][string]$UserObjectId, [Parameter(Mandatory)][string]$Token, [switch]$RequireOtherGlobalAdministrator)
    $assignments = @(Get-DirectoryRoleAssignments -PrincipalId $UserObjectId -Token $Token)
    if (-not $assignments.Count) { return @{ Removed = @(); OtherGlobalAdministrators = $null } }
    $definition = Get-DirectoryRoleDefinition -DisplayName 'Global Administrator' -Token $Token
    $holders = @(Invoke-Graph -Method GET -Path "roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$($definition.id)'" -Token $Token -All)
    $others = 0
    foreach ($h in $holders) {
        if ($h.principalId -eq $UserObjectId) { continue }
        $user = Invoke-Graph -Method GET -Path "users/$($h.principalId)?`$select=id,accountEnabled" -Token $Token -AllowNotFound
        if ($user.Status -ne 404 -and $user.Body.accountEnabled) { $others++ }
    }
    if ($RequireOtherGlobalAdministrator -and $others -eq 0 -and @($assignments | Where-Object { $_.Role -eq 'Global Administrator' }).Count) {
        throw ('No other enabled user holds Global Administrator, so removing the participant''s role would leave the tenant without one. ' +
               'Keep a supplier-only Global Administrator in every lab tenant (setup/README.md, Questions for CloudLabs), or deploy with requireSupplierGlobalAdmin false.')
    }
    $removed = @(Remove-DirectoryRoles -PrincipalId $UserObjectId -Token $Token)
    return @{ Removed = $removed; OtherGlobalAdministrators = $others }
}

function Remove-SetupAppPrivileges {
    <#
        Last action of provisioning: the setup app removes its own key credential, directory roles and
        application permissions, in that order, with one token issued before the changes. The local
        certificate is deleted afterwards by the caller.
    #>
    param([Parameter(Mandatory)][string]$Token)
    $info = Get-SetupAppInfo
    if (-not $info) { throw 'No setup app record (C:\LabFiles\.setup\setup-app.json).' }
    $null = Invoke-Graph -Method PATCH -Path "applications/$($info.objectId)" -Token $Token -Body @{ keyCredentials = @(); passwordCredentials = @() }
    $roles = @(Remove-DirectoryRoles -PrincipalId $info.servicePrincipalId -Token $Token)
    $assignments = @(Invoke-Graph -Method GET -Path "servicePrincipals/$($info.servicePrincipalId)/appRoleAssignments" -Token $Token -All)
    foreach ($a in ($assignments | Sort-Object { $_.appRoleId -eq '06b708a9-e830-4db3-a914-8e69da51d44f' })) {
        $null = Invoke-Graph -Method DELETE -Path "servicePrincipals/$($info.servicePrincipalId)/appRoleAssignments/$($a.id)" -Token $Token -AllowNotFound
    }
    return @{ DirectoryRoles = $roles; AppRoleAssignments = $assignments.Count }
}

Export-ModuleMember -Function Get-BootstrapToken, Resolve-BootstrapContext, Get-ServicePrincipalByAppId, Grant-AppRole,
    Get-DirectoryRoleDefinition, Get-DirectoryRoleAssignments, Add-DirectoryRole, Remove-DirectoryRoles, Get-ApplicationByName,
    New-AppPassword, Remove-AppPassword, New-SetupCertificate, Initialize-SetupApp, Set-GatewayApp, Add-GatewayRedirectUris,
    Get-GatewayUserToken, Set-PurviewApp, Resolve-LabUser, Remove-ParticipantAdministratorRoles, Remove-SetupAppPrivileges
