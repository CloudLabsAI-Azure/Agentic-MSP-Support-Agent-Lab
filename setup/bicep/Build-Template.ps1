#Requires -Version 7.0
<#
.SYNOPSIS
    Compiles setup/bicep/main.bicep into setup/deploy-01.json, the ARM template CloudLabs deploys,
    and fails when the committed deploy-01.json is out of date.

.DESCRIPTION
    1. Checks that the Azure CLI and its Bicep CLI are installed. The Bicep version is pinned in
       setup/bicep/bicepconfig.json (bicep.version); a different compiler stops with error BCP456.
       Install the pinned version with: az bicep install --version v<version>
    2. Compiles main.bicep with 'az bicep build' into a temporary file. Any compiler or linter
       warning fails the build (use -AllowWarnings only while you work).
    3. Renames the template outputs: Bicep identifiers cannot contain spaces, so main.bicep writes
       Resource_Group_Name for the CloudLabs output 'Resource Group Name'. Every underscore of a
       top-level output name becomes a space. Only the top-level outputs block is touched.
    4. Checks the contract: the eight CloudLabs platform parameters exist, and the output names are
       exactly the BUILD-SPEC 3.2 list plus the two trainer outputs.
    5. Compares the result with setup/deploy-01.json (line endings normalized). Without -Update
       the script exits 1 when they differ; with -Update it writes the new deploy-01.json.

    The policies in setup/apim are compiled into the template (loadTextContent), so a policy
    change also needs a rebuild.

.PARAMETER Update
    Write setup/deploy-01.json when it differs from the fresh build.

.PARAMETER AllowWarnings
    Do not fail on Bicep warnings (work in progress only).

.EXAMPLE
    pwsh setup/bicep/Build-Template.ps1            # check: exit 1 when deploy-01.json is stale

.EXAMPLE
    pwsh setup/bicep/Build-Template.ps1 -Update    # rebuild deploy-01.json
#>
[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$AllowWarnings
)

$ErrorActionPreference = 'Stop'
$bicepDir = $PSScriptRoot
$setupDir = Split-Path -Parent $bicepDir
$mainBicep = Join-Path $bicepDir 'main.bicep'
$target = Join-Path $setupDir 'deploy-01.json'

$platformParameters = @('adminUsername', 'adminPassword', 'AzureUserName', 'AzurePassword', 'ODLID', 'DeploymentID',
    'trainerUserName', 'trainerUserPassword')
$expectedOutputs = @(
    'DeploymentID', 'Region', 'Resource Group Name', 'LabVM DNS Name', 'LabVM Admin Username', 'LabVM Admin Password',
    'Trainer Username', 'Trainer Password', 'Foundry Resource Name', 'Foundry Project Name', 'Foundry Project Endpoint',
    'Chat Model Deployment', 'Embedding Model Deployment', 'Agent Name', 'AI Search Service Name', 'AI Search Endpoint',
    'Storage Account Name', 'Export Container', 'API Management Name', 'MCP Read Gateway URL', 'MCP Write Gateway URL',
    'MCP Diagnostics URL', 'MCP Gateway Audience', 'MCP Read Connection', 'MCP Write Connection', 'MCP Server URL',
    'Container App Name', 'Container Registry Name', 'Key Vault Name', 'Key Vault URL', 'Log Analytics Workspace',
    'Application Insights Name', 'MCP Backend Identity Name', 'MCP Backend Identity Client ID', 'Dataverse Environment URL',
    'Service Desk App URL', 'Tier 1 Technician Username', 'Golden Environment Version')

# ==== 1. Toolchain
if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'The Azure CLI is not installed (https://aka.ms/installazurecliwindows).' }
$config = Get-Content (Join-Path $bicepDir 'bicepconfig.json') -Raw | ConvertFrom-Json
$pinned = $config.bicep.version
$versionText = (& az bicep version 2>&1 | Out-String)
if ($versionText -notmatch 'Bicep CLI version (\d+\.\d+\.\d+)') {
    throw "The Bicep CLI is not installed. Run: az bicep install --version v$pinned"
}
$installed = $Matches[1]
Write-Host "Bicep CLI $installed (pinned: $pinned)"
if ($installed -ne $pinned) { throw "Bicep CLI $installed does not match the pinned version $pinned. Run: az bicep install --version v$pinned" }

# ==== 2. Compile
$temp = Join-Path ([IO.Path]::GetTempPath()) ("deploy-01-" + [guid]::NewGuid().ToString('N') + '.json')
try {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $buildOutput = & az bicep build --file $mainBicep --outfile $temp 2>&1 | ForEach-Object { '' + $_ }
    $buildExit = $LASTEXITCODE
    $ErrorActionPreference = $previous
    $warnings = @($buildOutput | Where-Object { $_ -match ': Warning ' })
    $errors = @($buildOutput | Where-Object { $_ -match ': Error |^ERROR' })
    $warnings | ForEach-Object { Write-Warning $_ }
    if ($buildExit -ne 0 -or $errors.Count -or -not (Test-Path $temp)) {
        $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        throw "az bicep build failed ($buildExit)."
    }
    if ($warnings.Count -and -not $AllowWarnings) { throw "$($warnings.Count) Bicep warning(s). Fix them, or pass -AllowWarnings while you work." }

    # ==== 3. Rename the top-level outputs (underscore to space), textually, so the compiled JSON
    #      stays byte for byte what Bicep wrote everywhere else.
    $lines = [IO.File]::ReadAllLines($temp)
    $start = [Array]::IndexOf($lines, '  "outputs": {')
    if ($start -lt 0) { throw 'The compiled template has no top-level outputs block.' }
    for ($i = $start + 1; $i -lt $lines.Count -and $lines[$i] -ne '  }'; $i++) {
        if ($lines[$i] -match '^    "([^"]+)": \{$') {
            $lines[$i] = '    "' + ($Matches[1] -replace '_', ' ') + '": {'
        }
    }
    $built = ($lines -join "`n") + "`n"

    # ==== 4. Contract checks
    $template = $built | ConvertFrom-Json -AsHashtable
    $missingParameters = @($platformParameters | Where-Object { -not $template.parameters.ContainsKey($_) })
    if ($missingParameters.Count) { throw "Missing CloudLabs platform parameters: $($missingParameters -join ', ')" }
    $outputs = @($template.outputs.Keys)
    $missingOutputs = @($expectedOutputs | Where-Object { $_ -notin $outputs })
    $extraOutputs = @($outputs | Where-Object { $_ -notin $expectedOutputs })
    if ($missingOutputs.Count -or $extraOutputs.Count) {
        throw "Output contract broken. Missing: $($missingOutputs -join ', '). Not in BUILD-SPEC 3.2: $($extraOutputs -join ', ')."
    }
    if (($built -split "`n" | Where-Object { $_ -match '[\u2013\u2014]' }).Count) { throw 'The template contains an en or em dash.' }

    # ==== 5. Compare with the committed template
    $normalize = { param([string]$text) ($text -replace "`r`n", "`n") -replace '\\r\\n', '\n' }
    $current = if (Test-Path $target) { & $normalize ([IO.File]::ReadAllText($target)) } else { '' }
    $fresh = & $normalize $built
    $summary = "{0} parameters, {1} outputs, {2} nested deployments" -f $template.parameters.Count, $outputs.Count,
        @($template.resources | Where-Object { $_.type -eq 'Microsoft.Resources/deployments' }).Count
    if ($current -eq $fresh) {
        Write-Host "deploy-01.json is up to date ($summary)." -ForegroundColor Green
        exit 0
    }
    if ($Update) {
        [IO.File]::WriteAllText($target, $fresh, (New-Object Text.UTF8Encoding($false)))
        Write-Host "Wrote $target ($summary)." -ForegroundColor Green
        exit 0
    }
    $a = $current -split "`n"
    $b = $fresh -split "`n"
    $line = 0
    while ($line -lt [Math]::Min($a.Count, $b.Count) -and $a[$line] -eq $b[$line]) { $line++ }
    Write-Host "deploy-01.json is out of date: first difference at line $($line + 1)." -ForegroundColor Yellow
    if ($line -lt $a.Count) { Write-Host "  committed: $($a[$line].Trim())" }
    if ($line -lt $b.Count) { Write-Host "  fresh:     $($b[$line].Trim())" }
    Write-Host 'Run: pwsh setup/bicep/Build-Template.ps1 -Update' -ForegroundColor Yellow
    exit 1
}
finally {
    Remove-Item $temp -Force -ErrorAction SilentlyContinue
}
