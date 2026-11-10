#Requires -Version 7.0
<#
.SYNOPSIS
    Packages setup/assets/labfiles, the reference solutions and the MCP server release into
    setup/assets/msp-labfiles.zip, the archive psscript-01.ps1 downloads from the template library
    and extracts to C:\LabFiles.

.DESCRIPTION
    Contents (C:\LabFiles on the VM):
      provision\     provisioning scripts, LabConfig.psd1, the Dataverse schema and security files
      provision\mcp-server\  the MCP server release, exactly as tagged (git archive of the tag); the
                     image is built from it and C:\LabFiles\mcp-server is created from it
      seed\          the seed generator and loader (the data is generated on the VM)
      search\        the index definition and the data source, skillset and indexer templates
      tools\         the lab tools (the MCP release adds Deploy-McpServer.ps1, Invoke-McpTool.ps1 and
                     Show-McpServerLog.ps1 at provisioning)
      agent\         the baseline and grounded agent instructions
      solutions\     the repository's solutions folder (reference solution for Exercise 4 Task 5)
      labfiles-build.json  what was packed: release, commit, time, and a SHA-256 per file

    Checks before it writes the archive (it stops on the first failure):
      - the tag exists and its src/servicedesk_mcp/__init__.py __version__ equals the tag and the
        McpRelease in provision/LabConfig.psd1;
      - every ReadTools and WriteTools name in LabConfig.psd1 is a read or write tool of the release
        (@catalogue.read_tool and @catalogue.write_tool), so the agent's allowed_tools list matches
        the server; release tools missing from the lists are reported;
      - the release has the participant scripts LabConfig.psd1 copies to C:\LabFiles\tools;
      - every file the logon task checks is present, and every PowerShell file parses.

    The archive holds the private MCP server source: upload it to the template library only, never
    to a public place. The repository's .gitignore keeps it out of Git.

.PARAMETER McpServerRepo
    A clone of CloudLabsAI-Azure/agentic-msp-mcp-server, by default next to the lab repository.

.PARAMETER McpRelease
    The release tag to pack, by default v<McpRelease from LabConfig.psd1>.

.PARAMETER SkipReleaseChecks
    Packaging test only: skips the version and tool list checks (for example to pack an older tag
    into a scratch folder). Never upload an archive built with it.

.EXAMPLE
    pwsh setup/Build-LabFilesZip.ps1

.EXAMPLE
    pwsh setup/Build-LabFilesZip.ps1 -McpServerRepo D:\src\agentic-msp-mcp-server -McpRelease v3.0.0
#>
[CmdletBinding()]
param(
    [string]$Source = (Join-Path $PSScriptRoot 'assets\labfiles'),
    [string]$Destination = (Join-Path $PSScriptRoot 'assets\msp-labfiles.zip'),
    [string]$McpServerRepo = (Join-Path $PSScriptRoot '..\..\agentic-msp-mcp-server'),
    [string]$McpRelease = '',
    [switch]$SkipReleaseChecks
)

$ErrorActionPreference = 'Stop'
$config = Import-PowerShellDataFile -Path (Join-Path $Source 'provision\LabConfig.psd1')
if (-not $McpRelease) { $McpRelease = "v$($config.McpRelease)" }
if (-not (Test-Path (Join-Path $McpServerRepo '.git'))) {
    throw "No Git repository at $McpServerRepo. Clone it first: gh repo clone CloudLabsAI-Azure/agentic-msp-mcp-server"
}
& git -C $McpServerRepo rev-parse --verify --quiet "refs/tags/$McpRelease" | Out-Null
if ($LASTEXITCODE) { throw "Tag $McpRelease is not in $McpServerRepo. Run 'git -C $McpServerRepo fetch --tags', or pass -McpRelease." }
$commit = (& git -C $McpServerRepo rev-parse "$McpRelease^{commit}").Trim()

$staging = Join-Path ([IO.Path]::GetTempPath()) "msp-labfiles-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    # ==== Lab files, without generated or local-only content
    Copy-Item -Path (Join-Path $Source '*') -Destination $staging -Recurse
    Get-ChildItem $staging -Recurse -Directory -Include '__pycache__', '.pytest_cache' | Remove-Item -Recurse -Force
    foreach ($generated in 'seed\data', 'provision\mcp-server', 'search\export', 'search\sample-documents') {
        $p = Join-Path $staging $generated
        if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    }
    Get-ChildItem $staging -Recurse -File -Include '*.pyc', 'environment.json', 'export-manifest.json', 'provision-status.json', 'lab-settings.json' |
        Remove-Item -Force
    $solutions = Join-Path $PSScriptRoot '..\solutions'
    if (Test-Path $solutions) { Copy-Item -Path $solutions -Destination (Join-Path $staging 'solutions') -Recurse }
    else { throw "The solutions folder $solutions is missing." }

    # ==== The MCP server release, exactly as tagged
    $mcpZip = Join-Path ([IO.Path]::GetTempPath()) "mcp-server-$([guid]::NewGuid().ToString('N')).zip"
    & git -C $McpServerRepo archive --format=zip --output $mcpZip $McpRelease
    if ($LASTEXITCODE) { throw "git archive $McpRelease failed ($LASTEXITCODE)" }
    $mcpDest = Join-Path $staging 'provision\mcp-server'
    Expand-Archive -LiteralPath $mcpZip -DestinationPath $mcpDest
    Remove-Item $mcpZip -Force

    # ==== Release checks
    $init = Get-Content (Join-Path $mcpDest 'src\servicedesk_mcp\__init__.py') -Raw
    $version = if ($init -match '__version__\s*=\s*"([^"]+)"') { $Matches[1] } else { '' }
    $notes = @()
    if (-not $SkipReleaseChecks) {
        if ("v$version" -ne $McpRelease) { throw "Tag $McpRelease has __version__ '$version' in src/servicedesk_mcp/__init__.py." }
        if ($version -ne $config.McpRelease) { throw "LabConfig.psd1 expects MCP release $($config.McpRelease), but the archive would carry $version." }
        $sourceText = (Get-ChildItem (Join-Path $mcpDest 'src\servicedesk_mcp') -Filter '*.py' -File | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
        # Decorators only: the line must start with the decorator, so mentions in docstrings don't count.
        $releaseRead = @([regex]::Matches($sourceText, '(?m)^[ \t]*@catalogue\.read_tool\b[\s\S]*?def\s+(\w+)\s*\(') | ForEach-Object { $_.Groups[1].Value })
        $releaseWrite = @([regex]::Matches($sourceText, '(?m)^[ \t]*@catalogue\.write_tool\b[\s\S]*?def\s+(\w+)\s*\(') | ForEach-Object { $_.Groups[1].Value })
        if (-not $releaseRead.Count -or -not $releaseWrite.Count) { throw 'No @catalogue.read_tool or @catalogue.write_tool functions were found in the release; the tool list check cannot run.' }
        $missingRead = @($config.ReadTools | Where-Object { $_ -notin $releaseRead })
        $missingWrite = @($config.WriteTools | Where-Object { $_ -notin $releaseWrite })
        if ($missingRead.Count -or $missingWrite.Count) {
            throw "LabConfig.psd1 names tools the release does not have: read $($missingRead -join ', '); write $($missingWrite -join ', ')."
        }
        $extraRead = @($releaseRead | Where-Object { $_ -notin $config.ReadTools })
        $extraWrite = @($releaseWrite | Where-Object { $_ -notin $config.WriteTools })
        if ($extraRead.Count) { $notes += "read tools in the release but not in the agent's allowed_tools: $($extraRead -join ', ')" }
        if ($extraWrite.Count) { $notes += "write tools in the release but not in WriteTools (they still need approval): $($extraWrite -join ', ')" }
    }
    else { Write-Warning 'Release checks skipped: packaging test only, do not upload this archive.' }
    foreach ($script in $config.McpToolsFromRelease) {
        if (-not (Test-Path (Join-Path $mcpDest "scripts\$script"))) { throw "The release has no scripts\$script." }
    }

    # ==== Files the VM needs (the logon task checks the same list after provisioning)
    $required = @(
        'provision\Provision-ServiceDesk.ps1', 'provision\MspLab.Common.psm1', 'provision\LabConfig.psd1', 'provision\entra\MspLab.Entra.psm1',
        'provision\dataverse\Deploy-ServiceDeskSchema.ps1', 'provision\dataverse\schema.json', 'provision\dataverse\Set-DataverseSecurity.ps1',
        'provision\dataverse\security.json', 'provision\powerplatform\New-ManagedDeveloperEnvironment.ps1', 'provision\purview\Set-PurviewProtection.ps1',
        'provision\foundry\New-McpConnections.ps1', 'provision\foundry\New-SupportAgent.ps1', 'provision\mcp\Deploy-McpBaseline.ps1',
        'provision\export\Export-SearchContent.ps1', 'seed\generate_seed.py', 'seed\load_seed.py',
        'tools\Test-LabReadiness.ps1', 'tools\Get-ActionTrail.ps1', 'tools\Get-DocumentLabel.ps1', 'tools\Get-AgentIdentity.ps1',
        'tools\Update-AgentDefinition.ps1', 'tools\New-KnowledgeIndex.ps1',
        'search\index-definition.json', 'search\servicedesk-export-ds.json', 'search\servicedesk-embed-skills.json', 'search\servicedesk-export-indexer.json',
        'agent\instructions-baseline.md', 'agent\instructions-grounded.md'
    )
    $missing = @($required | Where-Object { -not (Test-Path (Join-Path $staging $_)) })
    if ($missing.Count) { throw "Missing from the lab files: $($missing -join ', ')" }
    $parseErrors = @()
    foreach ($file in Get-ChildItem $staging -Recurse -File -Include '*.ps1', '*.psm1') {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
        foreach ($e in @($errors)) { $parseErrors += "$($file.FullName.Substring($staging.Length + 1)):$($e.Extent.StartLineNumber) $($e.Message)" }
    }
    if ($parseErrors.Count) { throw "PowerShell parse errors: $($parseErrors -join ' | ')" }

    # ==== Build record, then the archive
    $files = Get-ChildItem $staging -Recurse -File
    $record = [ordered]@{
        builtOnUtc               = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        goldenEnvironmentVersion = $config.GoldenEnvironmentVersion
        mcpRelease               = $McpRelease
        mcpCommit                = $commit
        releaseChecks            = -not $SkipReleaseChecks
        notes                    = $notes
        files                    = [ordered]@{}
    }
    foreach ($f in ($files | Sort-Object FullName)) {
        $record.files[$f.FullName.Substring($staging.Length + 1).Replace('\', '/')] = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $record | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $staging 'labfiles-build.json') -Encoding utf8NoBOM
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    if (Test-Path $Destination) { Remove-Item $Destination -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $Destination
    foreach ($n in $notes) { Write-Warning $n }
    Write-Host "Wrote $Destination ($($files.Count + 1) files, $([math]::Round((Get-Item $Destination).Length / 1KB)) KB) with MCP server $McpRelease ($($commit.Substring(0, 12)))"
}
finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
