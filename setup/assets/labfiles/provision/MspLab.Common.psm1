#Requires -Version 7.0
<#
    Shared helpers for the Agentic MSP lab provisioning scripts (PowerShell 7).
    Every function is idempotent-friendly and writes its progress to the transcript.

    Two identities are used, and no credential is ever written to disk or put on a command line:
      Azure Resource Manager  the Azure CLI session. During first-boot provisioning that is the
                              lab VM's provisioning managed identity (outside Azure's mandatory
                              MFA); when support re-runs a step it is their own 'az login'.
      Dataverse               the team user, because the team user owns the developer
                              environment. During provisioning the token is requested in-process
                              with the password in MSPLAB_SIGNIN_SECRET; otherwise it comes from
                              the Azure CLI session.
#>

Set-StrictMode -Version Latest

$script:StatusPath = 'C:\LabFiles\provision-status.json'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message)
}

function Set-StepStatus {
    <# Records the outcome of one provisioning step for the logon task's validation table. #>
    param([Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)][ValidateSet('Succeeded', 'Failed', 'Skipped')][string]$State,
          [string]$Detail = '')
    $status = @{}
    if (Test-Path $script:StatusPath) {
        (Get-Content $script:StatusPath -Raw | ConvertFrom-Json -AsHashtable).GetEnumerator() | ForEach-Object { $status[$_.Key] = $_.Value }
    }
    $status[$Step] = @{ state = $State; detail = $Detail; time = (Get-Date).ToUniversalTime().ToString('s') + 'Z' }
    $status | ConvertTo-Json -Depth 5 | Set-Content -Path $script:StatusPath -Encoding utf8
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

$script:TokenCache = @{}

function Get-AzCliToken {
    <# Access token for a resource from the team user's Azure CLI session, cached for 45 minutes. #>
    param([Parameter(Mandatory)][string]$Resource)
    $cached = $script:TokenCache[$Resource]
    if ($cached -and $cached.Expires -gt (Get-Date)) { return $cached.Token }
    $token = az account get-access-token --resource $Resource --query accessToken --output tsv 2>$null
    if (-not $token) { throw "Could not get an access token for $Resource. Is 'az login' done?" }
    $script:TokenCache[$Resource] = @{ Token = $token; Expires = (Get-Date).AddMinutes(45) }
    return $token
}

$script:UserSignIn = $null
$script:AzureCliClientId = '04b07795-8ddb-461a-bbee-02f9e1bf7b46'   # first-party public client used by 'az login'

function Set-UserSignIn {
    <# Remembers who the team user is. The password itself stays in MSPLAB_SIGNIN_SECRET. #>
    param([Parameter(Mandatory)][string]$UserName, [Parameter(Mandatory)][string]$TenantId)
    $script:UserSignIn = @{ UserName = $UserName; TenantId = $TenantId }
}

function Get-DataverseToken {
    <#
        Access token for Dataverse as the team user, cached for 45 minutes.
        With MSPLAB_SIGNIN_SECRET set (first-boot provisioning) the token is requested in-process,
        so the password never appears on a command line; otherwise the Azure CLI session is used.
        -Fresh skips the cache, for a token handed to a long-running child process.
    #>
    param([Parameter(Mandatory)][string]$OrgUrl, [switch]$Fresh)
    $resource = $OrgUrl.TrimEnd('/')
    $cached = $script:TokenCache["user:$resource"]
    if (-not $Fresh -and $cached -and $cached.Expires -gt (Get-Date)) { return $cached.Token }
    if ($env:MSPLAB_SIGNIN_SECRET -and $script:UserSignIn) {
        $body = @{
            client_id  = $script:AzureCliClientId
            grant_type = 'password'
            username   = $script:UserSignIn.UserName
            password   = $env:MSPLAB_SIGNIN_SECRET
            scope      = "$resource/.default"
        }
        $response = Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' -Body $body `
            -Uri "https://login.microsoftonline.com/$($script:UserSignIn.TenantId)/oauth2/v2.0/token"
        $token = $response.access_token
    }
    else {
        $token = az account get-access-token --resource $resource --query accessToken --output tsv 2>$null
    }
    if (-not $token) { throw "Could not get a Dataverse token for $resource as the team user." }
    $script:TokenCache["user:$resource"] = @{ Token = $token; Expires = (Get-Date).AddMinutes(45) }
    return $token
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
        $result = Invoke-RestMethod @params
        if ($status -eq 404 -and $AllowNotFound) { return $null }
        if ($status -eq 429 -or $status -ge 500) {
            $wait = 5 * $attempt
            if ($respHeaders -and $respHeaders['Retry-After']) { $wait = [int]($respHeaders['Retry-After'] | Select-Object -First 1) }
            Write-Step "  Dataverse $Method $Path returned $status; waiting $wait s."
            Start-Sleep -Seconds $wait
            continue
        }
        if ($status -ge 400) {
            $msg = if ($result.error) { "$($result.error.code) $($result.error.message)" } else { "$result" }
            throw "Dataverse $Method $Path failed with HTTP ${status}: $msg"
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

function Get-VmTags {
    <#
        The lab VM's tags, read from the Azure Instance Metadata Service (no sign-in needed).
        deploy-01.json puts the non-secret per-team lab settings there (msplab-*), so they never
        travel on a command line. Returns a hashtable of tag name to value.
    #>
    $tags = @{}
    try {
        $list = Invoke-RestMethod -Headers @{ Metadata = 'true' } -TimeoutSec 10 -NoProxy `
            -Uri 'http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01'
        foreach ($t in @($list)) { $tags[$t.name] = $t.value }
    }
    catch { Write-Step "  could not read the VM tags: $($_.Exception.Message)" }
    return $tags
}

function Read-TeamSettings {
    param([string]$Path = 'C:\LabFiles\team-settings.json')
    return Get-Content $Path -Raw | ConvertFrom-Json
}

Export-ModuleMember -Function Write-Step, Set-StepStatus, Invoke-WithRetry, Get-AzCliToken, Set-UserSignIn,
    Get-DataverseToken, Invoke-Dataverse, Get-EntityIdFromHeader, New-DvLabel, Get-VmTags, Read-TeamSettings
