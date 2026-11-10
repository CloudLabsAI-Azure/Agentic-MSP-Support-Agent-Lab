#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 9: secure secret handling. No secret in the repositories, the lab files or the
    Container App configuration; secrets live in Key Vault and are read through managed identity, and
    the read is in the Key Vault audit log.

.DESCRIPTION
    1. Scans the lab repository, the MCP server source on the VM (C:\LabFiles\mcp-server) and
       lab-settings.json for secrets (private keys, storage keys and connection strings, SAS
       signatures, access tokens, client secrets, subscription keys, passwords in assignments).
       Findings show the file, line and kind, never the value.
    2. Reads the Container App configuration: every app secret must be a Key Vault reference, and no
       environment variable may carry a literal secret.
    3. Reads the API Management named values: every secret named value must be a Key Vault reference.
    4. Checks that the secret mcp-backend-key exists in the vault (metadata only).
    5. Finds the Key Vault audit row (AZKVAuditLogs, or AzureDiagnostics) of the MCP server's managed
       identity reading that secret.
    6. With -IncludeDeniedRead, asks for the secret as the signed-in user, which must be refused
       (the participant holds Key Vault Reader, not Key Vault Secrets User). Only the secret's ID is
       requested, so no value is printed even if the read were allowed.

.EXAMPLE
    .\Test-SecretHandling.ps1 -IncludeDeniedRead -EvidencePath C:\Acceptance\evidence
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string[]]$ScanPath,
    [string]$SecretName = 'mcp-backend-key',
    [ValidateRange(1, 14)][int]$AuditDays = 3,
    [switch]$IncludeDeniedRead,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

$patterns = [ordered]@{
    'private key'                 = '-----BEGIN (RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----'
    'storage account key'         = '(?i)AccountKey=[A-Za-z0-9+/=]{40,}'
    'storage connection string'   = '(?i)DefaultEndpointsProtocol=https?;AccountName=[^;]+;AccountKey='
    'SAS signature'               = '(?i)[?&]sig=[A-Za-z0-9%+/=]{30,}'
    'access token'                = 'eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
    'client secret'               = '(?i)client[_-]?secret["'']?\s*[:=]\s*["''][A-Za-z0-9~._\-]{30,}["'']'
    'subscription or API key'     = '(?i)(ocp-apim-subscription-key|api-key|x-backend-key|subscriptionkey)["'']?\s*[:=]\s*["''][0-9a-f]{32}["'']'
    'GitHub token'                = '\b(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b'
    'password in an assignment'   = '(?i)\b(password|passwd|pwd)\s*[:=]\s*["''](?![<{$]|GEN-|GET-|\*+["''])[^"''\s]{8,}["'']'
}
$skipDirs = '\\(\.git|\.venv|venv|node_modules|__pycache__|\.pytest_cache|acceptance-evidence)\\'
$textExtensions = '.ps1', '.psm1', '.psd1', '.py', '.json', '.md', '.txt', '.yml', '.yaml', '.bicep', '.xml', '.toml', '.cfg', '.ini', '.env', '.example', '.sh', '.cmd', '.bat', '.config', '.dockerignore', ''

$settings = Read-LabSettings $SettingsPath @('ResourceGroup', 'ContainerApp', 'KeyVault')
$report = New-AcceptanceReport 9 'Secure secret handling' $settings
try {
    # ==== 1. Repositories and lab files
    if (-not $ScanPath) {
        $ScanPath = @((Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path, 'C:\LabFiles\mcp-server', $SettingsPath) | Where-Object { Test-Path $_ }
    }
    $findings = [System.Collections.Generic.List[object]]::new()
    $scanned = 0
    foreach ($root in $ScanPath) {
        $files = if (Test-Path $root -PathType Leaf) { @(Get-Item $root) } else { @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue) }
        foreach ($f in $files) {
            if ($f.FullName -match $skipDirs -or $f.Length -gt 5MB) { continue }
            if ($f.Extension.ToLowerInvariant() -notin $textExtensions -and $f.Name -notmatch '^(Dockerfile|\.env.*)$') { continue }
            $scanned++
            $n = 0
            foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
                $n++
                foreach ($kind in $patterns.Keys) {
                    if ($line -match $patterns[$kind]) {
                        $findings.Add([pscustomobject]@{ File = $f.FullName; Line = $n; Kind = $kind; Hint = ($Matches[0].Substring(0, [Math]::Min(6, $Matches[0].Length)) + '...') })
                    }
                }
            }
        }
    }
    $report.Evidence['secretScan'] = [pscustomobject]@{ Paths = $ScanPath; FilesScanned = $scanned; Findings = $findings }
    Add-Check $report 'No secret in the repositories, the MCP server source or lab-settings.json' ($findings.Count -eq 0) "$scanned files scanned; $($findings.Count) finding(s)$(if ($findings.Count) { ': ' + (@($findings | Select-Object -First 5 | ForEach-Object { "$($_.Kind) in $(Split-Path -Leaf $_.File):$($_.Line)" }) -join '; ') })"

    Use-LabIdentity Current $settings

    # ==== 2. Container App configuration
    $app = & az containerapp show --name $settings.ContainerApp --resource-group $settings.ResourceGroup --output json 2>$null | ConvertFrom-Json
    if (-not $app) { throw "Could not read the Container App $($settings.ContainerApp) (sign in with an account that holds Reader on the resource group)." }
    $plainSecrets = @($app.properties.configuration.secrets | Where-Object { $_ -and -not $_.keyVaultUrl })
    Add-Check $report 'Every Container App secret is a Key Vault reference' ($plainSecrets.Count -eq 0) "$(@($app.properties.configuration.secrets).Count) app secret(s); stored in the app: $(if ($plainSecrets.Count) { $plainSecrets.name -join ', ' } else { 'none' })"
    $safeName = '(?i)(_NAME|_URL|_URI|_ID|_ENABLED|_LEVEL|_BACKEND|_HOSTS|_STATELESS|_IMPERSONATION|_FOR_WRITES|_CONSISTENCY|_LABELS)$'
    $suspect = @(foreach ($c in @($app.properties.template.containers)) {
        foreach ($e in @($c.env)) {
            if ($e.value -and $e.name -match '(?i)secret|password|token|key|connection' -and $e.name -notmatch $safeName) { $e.name }
        }
    })
    Add-Check $report 'No environment variable carries a literal secret' ($suspect.Count -eq 0) $(if ($suspect.Count) { "check: $($suspect -join ', ')" } else { "$(@($app.properties.template.containers.env).Count) variables checked" })

    # ==== 3. API Management named values
    $apim = "/subscriptions/$($settings.SubscriptionId)/resourceGroups/$($settings.ResourceGroup)/providers/Microsoft.ApiManagement/service/$($settings.ApimName)"
    $nv = & az rest --method get --uri "https://management.azure.com$apim/namedValues?api-version=2024-05-01" --output json 2>$null | ConvertFrom-Json
    if ($nv) {
        $secretValues = @($nv.value | Where-Object { $_.properties.secret })
        $notVault = @($secretValues | Where-Object { -not $_.properties.keyVault.secretIdentifier })
        Add-Check $report 'Every secret named value in API Management is a Key Vault reference' ($notVault.Count -eq 0) "$($secretValues.Count) secret named value(s); not from Key Vault: $(if ($notVault.Count) { $notVault.name -join ', ' } else { 'none' })"
    }
    else { Add-Note $report 'The API Management named values could not be read with this account.' }

    # ==== 4. The secret exists (metadata only)
    $meta = & az keyvault secret list --vault-name $settings.KeyVault --query "[?name=='$SecretName'].{name:name, enabled:attributes.enabled, updated:attributes.updated}" --output json 2>$null | ConvertFrom-Json
    Add-Check $report "Key Vault holds $SecretName" (@($meta).Count -eq 1) $(if (@($meta).Count) { "enabled $(@($meta)[0].enabled), updated $(@($meta)[0].updated)" } else { 'not listed (the account needs Key Vault Reader)' })

    # ==== 5. The audit row of the managed identity's read
    $mcpClient = [string]$settings.McpBackendIdentityClientId
    $q = @"
union isfuzzy=true
  (AZKVAuditLogs | where OperationName == 'SecretGet' and tostring(column_ifexists('Id', '')) contains '$SecretName'
   | project TimeGenerated, Caller = tostring(Identity), AppId = tostring(Identity.claim.appid), Status = tostring(column_ifexists('HttpStatusCode', ''))),
  (AzureDiagnostics | where ResourceProvider == 'MICROSOFT.KEYVAULT' and OperationName == 'SecretGet' and tostring(column_ifexists('requestUri_s', '')) contains '$SecretName'
   | project TimeGenerated, Caller = tostring(column_ifexists('identity_claim_upn_s', '')), AppId = tostring(column_ifexists('identity_claim_appid_g', '')), Status = tostring(column_ifexists('httpStatusCode_d', '')))
| order by TimeGenerated desc
| take 50
"@
    $rows = @(Invoke-LabLogQuery $settings $q "P$($AuditDays)D")
    $byMcp = @($rows | Where-Object { $mcpClient -and ("$($_.AppId) $($_.Caller)" -match [regex]::Escape($mcpClient)) -and "$($_.Status)" -match '^200' })
    $report.Evidence['keyVaultAudit'] = $rows
    Add-Check $report "Key Vault audit shows the MCP server's identity reading $SecretName" ($byMcp.Count -ge 1) "$($rows.Count) SecretGet row(s) in $AuditDays days; by the MCP identity ($mcpClient) with HTTP 200: $($byMcp.Count)$(if ($byMcp.Count) { ", latest $($byMcp[0].TimeGenerated)" })"

    # ==== 6. The participant can't read the value
    if ($IncludeDeniedRead) {
        Use-LabIdentity Senior $settings
        $out = & az keyvault secret show --vault-name $settings.KeyVault --name $SecretName --query id --output tsv 2>&1
        $denied = ($LASTEXITCODE -ne 0)
        Add-Check $report 'The Senior Technician is refused the secret value' $denied $(if ($denied) { 'refused, as Key Vault Reader allows metadata only' } else { 'the read was ALLOWED: remove Key Vault Secrets User from the participant' })
        Add-Note $report 'The refused read is itself recorded in the Key Vault audit log (HTTP 403).'
    }
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
