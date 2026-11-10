#Requires -Version 7.0
<#
.SYNOPSIS
    Creates or updates the two MCP project connections, servicedesk-read and servicedesk-write, with
    OAuth identity passthrough, and registers their redirect URLs on the gateway app.

.DESCRIPTION
    The connections are RemoteTool connections with authType OAuth2 (custom OAuth with the gateway
    app registration), one per gateway API:
      servicedesk-read    target <read gateway URL>    scopes <audience>/ServiceDesk.Access offline_access
      servicedesk-write   target <write gateway URL>   same scopes
    Each participant consents once per connection (Open Consent in the playground); Agent Service then
    stores and refreshes that user's token. The gateway validates it (audience, client application,
    ServiceDesk.Access) and forwards the user's object ID to the MCP server.

    Identities:
      setup app (Microsoft Graph)  a new client secret on the gateway app (older secrets with the same
                                   name are removed), and the redirect URLs
      id-prov (Resource Manager)   the connections (Foundry Project Manager on the project until the
                                   last provisioning step)
    The secret is held in memory only and stored by Resource Manager in the two connections. Nothing
    is written to disk and nothing is printed.

    Connection shape. The OAuth2 properties follow the Foundry user delegation article
    (authorizationUrl, tokenUrl, refreshUrl, scopes beside credentials.clientId and clientSecret). If
    Resource Manager refuses that shape, the script sends the template reference shape instead
    (credentials.tenantId and authUrl, the URLs in metadata) and reports which one was accepted.

    Redirect URL. Foundry generates one when an OAuth connection is created; the portal shows it as
    Redirect URL. The script reads every URL in the connection's response that looks like a redirect
    or consent callback, and adds those and -ExtraRedirectUris (the template parameter
    oauthRedirectUris) to the gateway app. When it finds none, it still returns (the connections
    exist and the agent can be created) with RedirectUris empty; the caller reports the step as
    failed, because consent would fail with AADSTS50011 until the URL is registered
    (setup/tenant/RUNBOOK.md, Register the OAuth redirect URL).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$FoundryResource,
    [Parameter(Mandatory)][string]$FoundryProject,
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$GatewayAppId,
    [Parameter(Mandatory)][string]$GatewayAppObjectId,
    [Parameter(Mandatory)][string]$Audience,
    [Parameter(Mandatory)][string]$ReadGatewayUrl,
    [Parameter(Mandatory)][string]$WriteGatewayUrl,
    [string[]]$ExtraRedirectUris = @()
)

$ErrorActionPreference = 'Stop'
$provision = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $provision 'MspLab.Common.psm1') -Force
Import-Module (Join-Path $provision 'entra\MspLab.Entra.psm1') -Force
$config = Get-LabConfig
$projectPath = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$FoundryResource/projects/$FoundryProject"
$login = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0"
$scopes = @("$($Audience.TrimEnd('/'))/$($config.GatewayScope)", 'offline_access')

# ==== 1. A fresh client secret on the gateway app (memory only)
$graphToken = Get-SetupAppToken -Resource 'https://graph.microsoft.com'
$secret = New-AppPassword -AppObjectId $GatewayAppObjectId -DisplayName 'Foundry MCP connections' -Token $graphToken -Days $config.SecretLifetimeDays
$expires = (Get-Date).ToUniversalTime().AddDays($config.SecretLifetimeDays).ToString('yyyy-MM-dd')
Write-Step "  new gateway client secret for the connections (expires $expires UTC)"

function New-ConnectionBody([string]$Target, [string]$Shape) {
    $plain = [Net.NetworkCredential]::new('', $secret.Value).Password
    if ($Shape -eq 'delegation') {
        return @{ properties = [ordered]@{
            category = 'RemoteTool'; target = $Target; authType = 'OAuth2'; isSharedToAll = $true
            credentials = @{ clientId = $GatewayAppId; clientSecret = $plain }
            authorizationUrl = "$login/authorize"; tokenUrl = "$login/token"; refreshUrl = "$login/token"; scopes = $scopes
            metadata = @{ type = $config.McpConnectionMetadataType }
        } }
    }
    return @{ properties = [ordered]@{
        category = 'RemoteTool'; target = $Target; authType = 'OAuth2'; isSharedToAll = $true
        credentials = @{ clientId = $GatewayAppId; clientSecret = $plain; tenantId = $TenantId; authUrl = "$login/authorize" }
        metadata = @{ type = $config.McpConnectionMetadataType; authorizationUrl = "$login/authorize"; tokenUrl = "$login/token"
                      refreshUrl = "$login/token"; scopes = ($scopes -join ' ') }
    } }
}

function Find-RedirectUrls($Node, [string]$Name = '') {
    # Walks the response and returns string values that look like an OAuth redirect or consent callback.
    if ($null -eq $Node) { return }
    if ($Node -is [string]) {
        if ($Node -match '^https://' -and ($Name -match '(?i)redirect|callback|consent' -or $Node -match '(?i)/redirect|consent\.azure-apim\.net|/callback')) { $Node }
        return
    }
    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [System.Collections.IDictionary]) {
        foreach ($item in $Node) { Find-RedirectUrls $item $Name }
        return
    }
    $properties = if ($Node -is [System.Collections.IDictionary]) { $Node.Keys | ForEach-Object { @{ Name = $_; Value = $Node[$_] } } }
                  else { $Node.PSObject.Properties | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } } }
    foreach ($p in $properties) { Find-RedirectUrls $p.Value $p.Name }
}

# ==== 2. The connections
$results = @()
$redirects = New-Object System.Collections.Generic.List[string]
foreach ($c in @(@{ Name = $config.ReadConnection; Target = $ReadGatewayUrl }, @{ Name = $config.WriteConnection; Target = $WriteGatewayUrl })) {
    $accepted = $null
    $errors = @()
    foreach ($apiVersion in $config.ConnectionApiVersions) {
        foreach ($shape in 'delegation', 'template') {
            try {
                $r = Invoke-Arm -Method PUT -Path "$projectPath/connections/$($c.Name)" -ApiVersion $apiVersion -Body (New-ConnectionBody $c.Target $shape) -Wait
                $accepted = @{ ApiVersion = $apiVersion; Shape = $shape; Response = $r.Body }
                break
            }
            catch {
                $message = ConvertTo-SafeText ($_.Exception.Message -replace '(?i)"clientSecret"\s*:\s*"[^"]*"', '"clientSecret":"(removed)"')
                $errors += "$apiVersion/$shape`: $message"
                if ($message -notmatch 'HTTP 400|HTTP 404|HTTP 422|InvalidRequest|BadRequest|ValidationError|NoRegisteredProviderFound|InvalidApiVersion') { break }
            }
        }
        if ($accepted) { break }
    }
    if (-not $accepted) { throw "Creating the connection $($c.Name) failed: $($errors -join ' | ')" }
    $current = (Invoke-Arm -Method GET -Path "$projectPath/connections/$($c.Name)" -ApiVersion $accepted.ApiVersion).Body
    $p = $current.properties
    if ($p.authType -ne 'OAuth2' -or $p.category -ne 'RemoteTool' -or $p.target -ne $c.Target) {
        throw "The connection $($c.Name) reads back as $($p.category)/$($p.authType) to $($p.target); expected RemoteTool/OAuth2 to $($c.Target)."
    }
    foreach ($url in @(Find-RedirectUrls $accepted.Response) + @(Find-RedirectUrls $current)) { if ($url -and -not $redirects.Contains($url)) { $redirects.Add($url) } }
    Write-Step "  connection $($c.Name): RemoteTool, OAuth2, $($c.Target) (API $($accepted.ApiVersion), $($accepted.Shape) shape)"
    $results += [pscustomobject]@{ Name = $c.Name; Target = $c.Target; ApiVersion = $accepted.ApiVersion; Shape = $accepted.Shape }
}

# ==== 3. Redirect URLs on the gateway app
foreach ($url in $ExtraRedirectUris) { if ($url -and $url -match '^https://' -and -not $redirects.Contains($url)) { $redirects.Add($url) } }
if ($redirects.Count) {
    $all = Add-GatewayRedirectUris -AppObjectId $GatewayAppObjectId -Uris $redirects.ToArray() -Token $graphToken
    Write-Step "  gateway app redirect URIs: $(@($all).Count) ($($redirects -join ', '))"
}
else { Write-Step '  WARNING: no OAuth redirect URL found in the connection responses, and oauthRedirectUris is empty' }

[pscustomobject]@{
    Connections   = $results
    RedirectUris  = @($redirects)
    SecretExpires = $expires
    Scopes        = $scopes -join ' '
}
