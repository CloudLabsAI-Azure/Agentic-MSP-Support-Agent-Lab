#Requires -Version 7.0
<#
    Shared helpers for the Agentic MSP lab provisioning scripts and the readiness check (PowerShell 7).

    Identities. Nothing here stores or prints a credential, and nothing is written to disk:
      Azure Resource Manager, Storage, Key Vault, Foundry, Dataverse
                         the lab VM's provisioning identity (id-prov), through the Instance Metadata
                         Service. Managed identities are outside Azure's mandatory MFA.
      Microsoft Graph, Power Platform, Security & Compliance
                         the setup app, app-only, with a certificate whose private key never leaves
                         the VM's LocalMachine store (Get-SetupAppToken). Created by the bootstrap
                         step (entra\MspLab.Entra.psm1) and stripped of every privilege at the end.

    Configuration comes from environment variables and the VM's msplab-* tags, never from module
    state, because other scripts re-import this module with -Force:
      MSPLAB_PROVISIONING_CLIENT_ID   client ID of id-prov (else the VM tag of the same purpose)
      MSPLAB_DATAVERSE_TOKEN_SOURCE   ManagedIdentity (default) or SetupApp

    Functions kept for the data author's Deploy-ServiceDeskSchema.ps1: Write-Step, Invoke-WithRetry,
    Invoke-Dataverse, Get-EntityIdFromHeader, New-DvLabel. Keep their signatures.
#>

$script:LabFiles = 'C:\LabFiles'
$script:StatusPath = 'C:\LabFiles\provision-status.json'
$script:SettingsPath = 'C:\LabFiles\lab-settings.json'
$script:SetupInfoPath = 'C:\LabFiles\.setup\setup-app.json'
$script:TokenCache = @{}

# ==== Configuration and logging

function Get-LabConfig {
    <# The lab constants in LabConfig.psd1 (next to this module). #>
    return Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'LabConfig.psd1')
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message)
}

function ConvertTo-SafeText {
    <# Plain ASCII without quotes, dollar signs or backslashes: safe for status files and messages. #>
    param([string]$Text, [int]$MaxLength = 450)
    $clean = (("$Text" -replace '[^\x20-\x7E]', ' ') -replace '["$\\]', ' ' -replace '\s{2,}', ' ').Trim()
    if ($clean.Length -gt $MaxLength) { $clean = $clean.Substring(0, $MaxLength - 3) + '...' }
    return $clean
}

function Set-StepStatus {
    <# Records the outcome of one provisioning step in provision-status.json. #>
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][ValidateSet('Running', 'Succeeded', 'Failed', 'Skipped')][string]$State,
        [string]$Detail = '',
        [double]$Seconds = 0
    )
    $status = [ordered]@{}
    if (Test-Path $script:StatusPath) {
        try { $status = Get-Content $script:StatusPath -Raw | ConvertFrom-Json -AsHashtable } catch { $status = [ordered]@{} }
    }
    $status[$Step] = [ordered]@{
        state   = $State
        detail  = (ConvertTo-SafeText $Detail 900)
        time    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        seconds = [math]::Round($Seconds)
    }
    New-Item -ItemType Directory -Path (Split-Path $script:StatusPath) -Force | Out-Null
    $status | ConvertTo-Json -Depth 5 | Set-Content -Path $script:StatusPath -Encoding utf8NoBOM
}

function Get-StepStatus {
    if (-not (Test-Path $script:StatusPath)) { return [ordered]@{} }
    return Get-Content $script:StatusPath -Raw | ConvertFrom-Json -AsHashtable
}

function Invoke-WithRetry {
    param([Parameter(Mandatory)][scriptblock]$Action, [int]$Attempts = 5, [int]$DelaySeconds = 15, [string]$What = 'operation')
    for ($i = 1; $i -le $Attempts; $i++) {
        try { return & $Action }
        catch {
            if ($i -eq $Attempts) { throw }
            Write-Step "  $What failed (attempt $i of $Attempts): $($_.Exception.Message). Retrying in $DelaySeconds s."
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# ==== Lab settings (C:\LabFiles\lab-settings.json, BUILD-SPEC 3.6)

function Read-LabSettings {
    param([string]$Path = $script:SettingsPath)
    if (-not (Test-Path $Path)) { return [ordered]@{} }
    return Get-Content $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Update-LabSettings {
    <# Merges values into lab-settings.json. Never put a secret here. #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Values, [string]$Path = $script:SettingsPath)
    $settings = Read-LabSettings -Path $Path
    foreach ($key in $Values.Keys) { $settings[$key] = $Values[$key] }
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding utf8NoBOM
    return $settings
}

Set-Alias -Name Read-TeamSettings -Value Read-LabSettings

# ==== Instance Metadata Service

function Get-VmMetadata {
    <# The VM's compute metadata: subscriptionId, resourceGroupName, location, name, tagsList. #>
    return Invoke-WithRetry -What 'read the instance metadata' -Attempts 10 -DelaySeconds 6 -Action {
        Invoke-RestMethod -Headers @{ Metadata = 'true' } -NoProxy -TimeoutSec 15 `
            -Uri 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01'
    }
}

function Get-VmTags {
    <# The VM's tags as a hashtable. deploy-01.json puts the non-secret lab settings there (msplab-*). #>
    $tags = @{}
    try { foreach ($t in @((Get-VmMetadata).tagsList)) { $tags[$t.name] = [string]$t.value } }
    catch { Write-Step "  could not read the VM tags: $($_.Exception.Message)" }
    return $tags
}

function Get-LabTag {
    param([Parameter(Mandatory)][string]$Name, [string]$Default = '')
    $value = (Get-VmTags)[$Name]
    if ([string]::IsNullOrWhiteSpace($value) -or $value -like 'GET-*' -or $value -like 'REPLACE-WITH-*') { return $Default }
    return $value
}

# ==== Tokens

function Get-ProvisioningClientId {
    if ($env:MSPLAB_PROVISIONING_CLIENT_ID) { return $env:MSPLAB_PROVISIONING_CLIENT_ID }
    $fromTag = Get-LabTag 'msplab-provisioning-client-id'
    if ($fromTag) { $env:MSPLAB_PROVISIONING_CLIENT_ID = $fromTag; return $fromTag }
    throw 'The provisioning identity client ID is unknown (MSPLAB_PROVISIONING_CLIENT_ID or the VM tag msplab-provisioning-client-id).'
}

function Get-ManagedIdentityToken {
    <#
        Access token of the provisioning identity (id-prov) for a resource, from the Instance
        Metadata Service. Retries while a new identity or role assignment settles.
    #>
    param([Parameter(Mandatory)][string]$Resource, [string]$ClientId, [switch]$Fresh)
    if (-not $ClientId) { $ClientId = Get-ProvisioningClientId }
    $key = "mi|$ClientId|$Resource"
    $cached = $script:TokenCache[$key]
    if (-not $Fresh -and $cached -and $cached.Expires -gt (Get-Date).AddMinutes(5)) { return $cached.Token }
    $uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=' +
        [uri]::EscapeDataString($Resource) + '&client_id=' + $ClientId
    $response = Invoke-WithRetry -What "managed identity token for $Resource" -Attempts 12 -DelaySeconds 10 -Action {
        Invoke-RestMethod -Headers @{ Metadata = 'true' } -NoProxy -TimeoutSec 30 -Uri $uri
    }
    $expires = [DateTimeOffset]::FromUnixTimeSeconds([long]$response.expires_on).LocalDateTime
    $script:TokenCache[$key] = @{ Token = $response.access_token; Expires = $expires }
    return $response.access_token
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-ClientAssertion {
    <# A signed JWT client assertion for the certificate credential flow (RS256, x5t header). #>
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = [ordered]@{ alg = 'RS256'; typ = 'JWT'; x5t = (ConvertTo-Base64Url $Certificate.GetCertHash()) } | ConvertTo-Json -Compress
    $payload = [ordered]@{
        aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        iss = $ClientId; sub = $ClientId; jti = [guid]::NewGuid().ToString()
        nbf = $now - 60; iat = $now; exp = $now + 600
    } | ConvertTo-Json -Compress
    $unsigned = (ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($header))) + '.' + (ConvertTo-Base64Url ([Text.Encoding]::UTF8.GetBytes($payload)))
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if (-not $rsa) { throw "The certificate $($Certificate.Thumbprint) has no usable private key." }
    $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned), [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    return $unsigned + '.' + (ConvertTo-Base64Url $signature)
}

function Get-SetupAppInfo {
    <# The setup app's public facts (application ID, object IDs, certificate thumbprint). No secret. #>
    if (-not (Test-Path $script:SetupInfoPath)) { return $null }
    return Get-Content $script:SetupInfoPath -Raw | ConvertFrom-Json -AsHashtable
}

function Save-SetupAppInfo {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Info)
    New-Item -ItemType Directory -Path (Split-Path $script:SetupInfoPath) -Force | Out-Null
    $Info | ConvertTo-Json -Depth 5 | Set-Content -Path $script:SetupInfoPath -Encoding utf8NoBOM
}

function Get-SetupAppCertificate {
    $info = Get-SetupAppInfo
    if (-not $info -or -not $info.thumbprint) { return $null }
    $cert = Get-Item -Path "Cert:\LocalMachine\My\$($info.thumbprint)" -ErrorAction SilentlyContinue
    if (-not $cert -or -not $cert.HasPrivateKey -or $cert.NotAfter -lt (Get-Date).AddHours(1)) { return $null }
    return $cert
}

function Get-SetupAppToken {
    <# App-only token of the setup app (certificate credential) for a resource or scope. #>
    param([Parameter(Mandatory)][string]$Resource, [switch]$Fresh)
    $info = Get-SetupAppInfo
    if (-not $info -or $info.stripped) { throw 'The setup app is not available (not bootstrapped, or already stripped at the end of provisioning). Run the bootstrap again: setup/tenant/RUNBOOK.md.' }
    $cert = Get-SetupAppCertificate
    if (-not $cert) { throw "The setup app certificate $($info.thumbprint) is missing from Cert:\LocalMachine\My or expired. Run the bootstrap again." }
    $scope = if ($Resource -match '/\.default$') { $Resource } else { $Resource.TrimEnd('/') + '/.default' }
    if ($Resource -eq 'https://service.powerapps.com/') { $scope = 'https://service.powerapps.com//.default' }
    $key = "app|$($info.appId)|$scope"
    $cached = $script:TokenCache[$key]
    if (-not $Fresh -and $cached -and $cached.Expires -gt (Get-Date).AddMinutes(5)) { return $cached.Token }
    $body = @{
        client_id             = $info.appId
        scope                 = $scope
        grant_type            = 'client_credentials'
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion      = (New-ClientAssertion -TenantId $info.tenantId -ClientId $info.appId -Certificate $cert)
    }
    $response = Invoke-WithRetry -What "setup app token for $scope" -Attempts 6 -DelaySeconds 15 -Action {
        Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$($info.tenantId)/oauth2/v2.0/token" `
            -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec 60
    }
    $script:TokenCache[$key] = @{ Token = $response.access_token; Expires = (Get-Date).AddSeconds([int]$response.expires_in) }
    return $response.access_token
}

function Get-PowerPlatformToken {
    <#
        Token for the Power Platform admin APIs (resource https://service.powerapps.com/ for
        api.bap.microsoft.com, or https://api.powerplatform.com/). Power Platform accepts a service
        principal only after a tenant administrator registered it as a management application, with
        a user sign-in (a service principal can't register itself). In order:
          1. the setup app, when the bootstrap registered it (setup-app.json powerPlatform registered);
          2. the CloudLabs bootstrap service principal, when CloudLabs registered it in the tenant; its
             secret stays in Key Vault (setup-bootstrap-secret) until the last provisioning step.
    #>
    param([Parameter(Mandatory)][string]$Resource)
    $info = Get-SetupAppInfo
    if ($info -and -not $info.stripped -and $info.powerPlatform -eq 'registered') { return Get-SetupAppToken -Resource $Resource }
    $appId = Get-LabTag 'msplab-bootstrap-app-id'
    $vault = (Read-LabSettings).KeyVaultUrl
    if ($appId -and $vault) {
        $scope = if ($Resource -eq 'https://service.powerapps.com/') { 'https://service.powerapps.com//.default' } else { $Resource.TrimEnd('/') + '/.default' }
        $key = "bootstrap-sp|$appId|$scope"
        $cached = $script:TokenCache[$key]
        if ($cached -and $cached.Expires -gt (Get-Date).AddMinutes(5)) { return $cached.Token }
        $secret = Get-KeyVaultSecret -VaultUri $vault -Name 'setup-bootstrap-secret'
        if ($secret) {
            $tenantId = if ($info) { $info.tenantId } else { (Read-LabSettings).TenantId }
            $body = @{ client_id = $appId; scope = $scope; grant_type = 'client_credentials'
                       client_secret = [Net.NetworkCredential]::new('', $secret).Password }
            $r = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
                -ContentType 'application/x-www-form-urlencoded' -Body $body -TimeoutSec 60
            $script:TokenCache[$key] = @{ Token = $r.access_token; Expires = (Get-Date).AddSeconds([int]$r.expires_in) }
            return $r.access_token
        }
    }
    throw ('No identity is registered with Power Platform: the setup app could not be registered (it needs a user sign-in of a tenant ' +
           'administrator, which the ODL credential cannot give when it is a Temporary Access Pass) and no registered CloudLabs service ' +
           'principal is available. Register the setup app as in setup/tenant/RUNBOOK.md, Register the setup app with Power Platform, then run the step again.')
}

function Get-DataverseToken {
    <#
        Access token for a Dataverse environment: the provisioning identity (default), or the setup
        app when MSPLAB_DATAVERSE_TOKEN_SOURCE is SetupApp. -Fresh skips the cache.
    #>
    param([Parameter(Mandatory)][string]$OrgUrl, [switch]$Fresh)
    $resource = $OrgUrl.TrimEnd('/')
    if ($env:MSPLAB_DATAVERSE_TOKEN_SOURCE -eq 'SetupApp') { return Get-SetupAppToken -Resource $resource -Fresh:$Fresh }
    return Get-ManagedIdentityToken -Resource $resource -Fresh:$Fresh
}

# ==== REST

function Get-RestErrorText {
    param($Body)
    if ($null -eq $Body) { return '' }
    if ($Body -is [string]) { return $Body.Substring(0, [Math]::Min(600, $Body.Length)) }
    foreach ($path in @('error.message', 'error_description', 'message', 'Message', 'error.code')) {
        $value = $Body
        foreach ($part in $path.Split('.')) {
            if ($null -eq $value) { break }
            $prop = $value.PSObject.Properties[$part]
            $value = if ($prop) { $prop.Value } else { $null }
        }
        if ($value -is [string] -and $value) { return $value }
    }
    $json = ($Body | ConvertTo-Json -Depth 6 -Compress) -replace '\s+', ' '
    return $json.Substring(0, [Math]::Min(500, $json.Length))
}

function Invoke-LabRest {
    <#
        One HTTP call with bounded retries on 429, 5xx and network failures. Returns
        @{ Status; Body; Headers }. Any other 4xx throws, unless it is 404 with -AllowNotFound or
        one of -AllowStatus. Tokens are sent but never written to the transcript.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [string]$Token,
        $Body = $null,
        [hashtable]$Headers = @{},
        [string]$ContentType = 'application/json',
        [switch]$AllowNotFound,
        [int[]]$AllowStatus = @(),
        [int]$Attempts = 6,
        [int]$TimeoutSec = 120
    )
    $display = ($Uri -split '\?')[0]
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $h = @{}
        if ($Token) { $h['Authorization'] = "Bearer $Token" }
        foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
        $params = @{
            Method = $Method; Uri = $Uri; Headers = $h; SkipHttpErrorCheck = $true; TimeoutSec = $TimeoutSec
            StatusCodeVariable = 'statusCode'; ResponseHeadersVariable = 'responseHeaders'
        }
        if ($null -ne $Body) {
            $params.Body = if ($Body -is [string] -or $Body -is [byte[]]) { $Body } else { $Body | ConvertTo-Json -Depth 50 -Compress }
            $params.ContentType = $ContentType
        }
        $statusCode = 0
        $responseHeaders = @{}
        try { $result = Invoke-RestMethod @params }
        catch {
            if ($attempt -eq $Attempts) { throw "$Method $display failed without a response: $($_.Exception.Message)" }
            Start-Sleep -Seconds (5 * $attempt)
            continue
        }
        if ($statusCode -eq 404 -and $AllowNotFound) { return @{ Status = 404; Body = $result; Headers = $responseHeaders } }
        if ($statusCode -in $AllowStatus) { return @{ Status = $statusCode; Body = $result; Headers = $responseHeaders } }
        if (($statusCode -eq 429 -or $statusCode -ge 500) -and $attempt -lt $Attempts) {
            $wait = 5 * $attempt
            $retryAfter = $responseHeaders['Retry-After'] | Select-Object -First 1
            if ($retryAfter -and "$retryAfter" -match '^\d+$') { $wait = [Math]::Min([int]$retryAfter, 120) }
            Write-Step "  $Method $display returned $statusCode; waiting $wait s."
            Start-Sleep -Seconds $wait
            continue
        }
        if ($statusCode -ge 400) { throw "$Method $display returned HTTP ${statusCode}: $(Get-RestErrorText $result)" }
        return @{ Status = $statusCode; Body = $result; Headers = $responseHeaders }
    }
    throw "$Method $display kept failing after $Attempts attempts."
}

function Wait-ArmOperation {
    <# Follows Azure-AsyncOperation or Location until the long-running ARM operation ends. #>
    param([Parameter(Mandatory)]$Headers, [int]$TimeoutMinutes = 30)
    $async = $Headers['Azure-AsyncOperation'] | Select-Object -First 1
    $location = $Headers['Location'] | Select-Object -First 1
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 10
        $token = Get-ManagedIdentityToken 'https://management.azure.com/'
        if ($async) {
            $r = Invoke-LabRest -Method GET -Uri $async -Token $token
            $state = [string]$r.Body.status
            if ($state -in 'Succeeded') { return }
            if ($state -in 'Failed', 'Canceled') { throw "ARM operation $state`: $(Get-RestErrorText $r.Body)" }
        }
        elseif ($location) {
            $r = Invoke-LabRest -Method GET -Uri $location -Token $token -AllowStatus 202
            if ($r.Status -ne 202) { return }
        }
        else { return }
    }
    throw "ARM operation did not finish within $TimeoutMinutes minutes."
}

function Invoke-Arm {
    <# Azure Resource Manager call as the provisioning identity. -Wait follows 201/202 operations. #>
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ApiVersion,
        $Body = $null,
        [switch]$AllowNotFound,
        [int[]]$AllowStatus = @(),
        [switch]$Wait
    )
    $uri = if ($Path -match '^https://') { $Path } else { 'https://management.azure.com' + $Path }
    $uri += $(if ($uri.Contains('?')) { '&' } else { '?' }) + "api-version=$ApiVersion"
    $r = Invoke-LabRest -Method $Method -Uri $uri -Token (Get-ManagedIdentityToken 'https://management.azure.com/') -Body $Body `
        -AllowNotFound:$AllowNotFound -AllowStatus $AllowStatus
    if ($Wait -and $r.Status -in 201, 202) { Wait-ArmOperation -Headers $r.Headers }
    return $r
}

function Invoke-Graph {
    <# Microsoft Graph call with an explicit token. -All follows @odata.nextLink and returns the items. #>
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Token,
        $Body = $null,
        [switch]$AllowNotFound,
        [int[]]$AllowStatus = @(),
        [switch]$All,
        [string]$Version = 'v1.0',
        [hashtable]$Headers = @{}
    )
    $uri = if ($Path -match '^https://') { $Path } else { "https://graph.microsoft.com/$Version/$($Path.TrimStart('/'))" }
    if (-not $All) {
        return Invoke-LabRest -Method $Method -Uri $uri -Token $Token -Body $Body -Headers $Headers -AllowNotFound:$AllowNotFound -AllowStatus $AllowStatus
    }
    $items = New-Object System.Collections.Generic.List[object]
    while ($uri) {
        $r = Invoke-LabRest -Method GET -Uri $uri -Token $Token -Headers $Headers -AllowNotFound:$AllowNotFound
        if ($r.Status -eq 404) { break }
        foreach ($v in @($r.Body.value)) { if ($null -ne $v) { $items.Add($v) } }
        $next = $r.Body.PSObject.Properties['@odata.nextLink']
        $uri = if ($next) { [string]$next.Value } else { $null }
    }
    # Items are written to the pipeline one by one: wrap the call in @() to always get an array.
    return $items.ToArray()
}

function Invoke-Dataverse {
    <#
        Calls the Dataverse Web API. Returns @{ Body; Headers; Status }.
        -AllowNotFound returns $null on 404. Retries 429 and 5xx with backoff.
    #>
    param(
        [Parameter(Mandatory)][string]$OrgUrl,
        [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        $Body = $null,
        [hashtable]$Headers = @{},
        [string]$Solution = '',
        [switch]$AllowNotFound
    )
    $uri = "$($OrgUrl.TrimEnd('/'))/api/data/v9.2/$Path"
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $h = @{
            Authorization      = "Bearer $(Get-DataverseToken -OrgUrl $OrgUrl)"
            Accept             = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
            'If-None-Match'    = 'null'
            Consistency        = 'Strong'
        }
        if ($Solution) { $h['MSCRM.SolutionUniqueName'] = $Solution }
        foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
        $params = @{ Method = $Method; Uri = $uri; Headers = $h; SkipHttpErrorCheck = $true; ResponseHeadersVariable = 'respHeaders'; StatusCodeVariable = 'status' }
        if ($null -ne $Body) {
            $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 -Compress }
            $params.ContentType = 'application/json; charset=utf-8'
        }
        try { $result = Invoke-RestMethod @params }
        catch {
            if ($attempt -eq 6) { throw "Dataverse $Method $Path failed without a response: $($_.Exception.Message)" }
            Start-Sleep -Seconds (5 * $attempt)
            continue
        }
        if ($status -eq 404 -and $AllowNotFound) { return $null }
        if ($status -eq 429 -or $status -ge 500) {
            $wait = 5 * $attempt
            if ($respHeaders -and $respHeaders['Retry-After']) { $wait = [int]($respHeaders['Retry-After'] | Select-Object -First 1) }
            Write-Step "  Dataverse $Method $Path returned $status; waiting $wait s."
            Start-Sleep -Seconds $wait
            continue
        }
        if ($status -ge 400) {
            throw "Dataverse $Method $Path failed with HTTP ${status}: $(Get-RestErrorText $result)"
        }
        return @{ Body = $result; Headers = $respHeaders; Status = $status }
    }
    throw "Dataverse $Method $Path kept failing after retries."
}

function Get-EntityIdFromHeader {
    <# Reads the GUID from an OData-EntityId response header. #>
    param($Headers)
    $value = $Headers['OData-EntityId'] | Select-Object -First 1
    if ($value -match '\(([0-9a-fA-F-]{36})\)') { return $Matches[1] }
    return $null
}

function New-DvLabel {
    param([Parameter(Mandatory)][string]$Text)
    return @{
        '@odata.type'   = 'Microsoft.Dynamics.CRM.Label'
        LocalizedLabels = @(@{ '@odata.type' = 'Microsoft.Dynamics.CRM.LocalizedLabel'; Label = $Text; LanguageCode = 1033 })
    }
}

# ==== Key Vault and Blob data plane (provisioning identity)

function Set-KeyVaultSecret {
    param([Parameter(Mandatory)][string]$VaultUri, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][securestring]$Value,
          [string]$ContentType = '', [int]$ExpiresInDays = 0)
    $body = [ordered]@{ value = [Net.NetworkCredential]::new('', $Value).Password }
    if ($ContentType) { $body.contentType = $ContentType }
    if ($ExpiresInDays -gt 0) { $body.attributes = @{ exp = [DateTimeOffset]::UtcNow.AddDays($ExpiresInDays).ToUnixTimeSeconds() } }
    $null = Invoke-LabRest -Method PUT -Uri "$($VaultUri.TrimEnd('/'))/secrets/$($Name)?api-version=7.4" `
        -Token (Get-ManagedIdentityToken 'https://vault.azure.net') -Body $body
}

function Get-KeyVaultSecret {
    <# Returns the secret value as a SecureString, or $null when it does not exist. #>
    param([Parameter(Mandatory)][string]$VaultUri, [Parameter(Mandatory)][string]$Name)
    $r = Invoke-LabRest -Method GET -Uri "$($VaultUri.TrimEnd('/'))/secrets/$($Name)?api-version=7.4" `
        -Token (Get-ManagedIdentityToken 'https://vault.azure.net') -AllowNotFound
    if ($r.Status -eq 404) { return $null }
    return (ConvertTo-SecureString -String ([string]$r.Body.value) -AsPlainText -Force)
}

function Remove-KeyVaultSecret {
    <# Deletes a secret and, when the role allows it, purges the soft-deleted copy. #>
    param([Parameter(Mandatory)][string]$VaultUri, [Parameter(Mandatory)][string]$Name)
    $token = Get-ManagedIdentityToken 'https://vault.azure.net'
    $vault = $VaultUri.TrimEnd('/')
    $null = Invoke-LabRest -Method DELETE -Uri "$vault/secrets/$($Name)?api-version=7.4" -Token $token -AllowNotFound
    for ($i = 1; $i -le 6; $i++) {
        $purge = Invoke-LabRest -Method DELETE -Uri "$vault/deletedsecrets/$($Name)?api-version=7.4" -Token $token -AllowNotFound -AllowStatus 403, 409
        if ($purge.Status -in 204, 200, 404, 403) { return $purge.Status }
        Start-Sleep -Seconds 5
    }
}

function Set-BlobContent {
    <# Uploads text (UTF-8) as a block blob with the provisioning identity (shared key access is off). #>
    param([Parameter(Mandatory)][string]$Account, [Parameter(Mandatory)][string]$Container, [Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)][string]$Text, [string]$ContentType = 'application/json', [string]$Token)
    if (-not $Token) { $Token = Get-ManagedIdentityToken 'https://storage.azure.com/' }
    $null = Invoke-LabRest -Method PUT -Uri "https://$Account.blob.core.windows.net/$Container/$([uri]::EscapeDataString($Name))" -Token $Token `
        -Headers @{ 'x-ms-version' = '2023-11-03'; 'x-ms-blob-type' = 'BlockBlob'; 'x-ms-blob-content-type' = $ContentType } `
        -Body ([Text.Encoding]::UTF8.GetBytes($Text)) -ContentType $ContentType
}

function Get-BlobNames {
    param([Parameter(Mandatory)][string]$Account, [Parameter(Mandatory)][string]$Container, [string]$Token)
    if (-not $Token) { $Token = Get-ManagedIdentityToken 'https://storage.azure.com/' }
    $names = New-Object System.Collections.Generic.List[string]
    $marker = ''
    do {
        $uri = "https://$Account.blob.core.windows.net/$($Container)?restype=container&comp=list&maxresults=5000"
        if ($marker) { $uri += '&marker=' + [uri]::EscapeDataString($marker) }
        $r = Invoke-LabRest -Method GET -Uri $uri -Token $Token -Headers @{ 'x-ms-version' = '2023-11-03' }
        $text = if ($r.Body -is [xml]) { $r.Body.OuterXml } else { [string]$r.Body }
        $xml = [xml]($text.TrimStart([char]0xFEFF))
        foreach ($blob in @($xml.EnumerationResults.Blobs.Blob)) { if ($blob -and $blob.Name) { $names.Add([string]$blob.Name) } }
        $marker = [string]$xml.EnumerationResults.NextMarker
    } while ($marker)
    return $names.ToArray()
}

Export-ModuleMember -Function Get-LabConfig, Write-Step, ConvertTo-SafeText, Set-StepStatus, Get-StepStatus, Invoke-WithRetry,
    Read-LabSettings, Update-LabSettings, Get-VmMetadata, Get-VmTags, Get-LabTag, Get-ProvisioningClientId,
    Get-ManagedIdentityToken, ConvertTo-Base64Url, New-ClientAssertion, Get-SetupAppInfo, Save-SetupAppInfo,
    Get-SetupAppCertificate, Get-SetupAppToken, Get-PowerPlatformToken, Get-DataverseToken, Get-RestErrorText, Invoke-LabRest, Wait-ArmOperation,
    Invoke-Arm, Invoke-Graph, Invoke-Dataverse, Get-EntityIdFromHeader, New-DvLabel, Set-KeyVaultSecret, Get-KeyVaultSecret,
    Remove-KeyVaultSecret, Set-BlobContent, Get-BlobNames -Alias Read-TeamSettings
