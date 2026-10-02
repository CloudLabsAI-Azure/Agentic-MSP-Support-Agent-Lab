#Requires -Version 7.0
<#
.SYNOPSIS
    Packages setup/assets/labfiles and a release of the MCP server into
    setup/assets/msp-labfiles.zip, the archive psscript-01.ps1 downloads from the template blob
    and extracts to C:\LabFiles.

.DESCRIPTION
    Excludes generated and local-only content (seed data output, Python caches). The MCP server
    source comes from its private repository at a release tag, through 'git archive', so the
    archive holds exactly the tagged files and the lab VMs never need access to GitHub. It lands
    in provision\mcp-server; provisioning builds the starter image from it and gives each team a
    local Git copy in C:\LabFiles\mcp-server.

    The archive therefore contains the private MCP server source: upload it to the template
    library only. The lab repository's .gitignore keeps it out of Git.

    Run it after any change under setup/assets/labfiles and after every new MCP server release,
    then upload the zip with the rest of the project folder (see setup/README.md).

.PARAMETER McpServerRepo
    A clone of CloudLabsAI-Azure/agentic-msp-mcp-server. Defaults to the build workspace layout,
    with the clone next to this lab repository.

.PARAMETER McpRelease
    The release tag to pack. Its __version__ must match the tag (v1.0.0 and "1.0.0").

.EXAMPLE
    pwsh setup/Build-LabFilesZip.ps1

.EXAMPLE
    pwsh setup/Build-LabFilesZip.ps1 -McpServerRepo D:\src\agentic-msp-mcp-server -McpRelease v1.0.0
#>
[CmdletBinding()]
param([string]$Source = (Join-Path $PSScriptRoot 'assets\labfiles'),
      [string]$Destination = (Join-Path $PSScriptRoot 'assets\msp-labfiles.zip'),
      [string]$McpServerRepo = (Join-Path $PSScriptRoot '..\..\agentic-msp-mcp-server'),
      [string]$McpRelease = 'v1.0.0')

$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $McpServerRepo '.git'))) {
    throw "No Git repository at $McpServerRepo. Clone it first: gh repo clone CloudLabsAI-Azure/agentic-msp-mcp-server"
}
git -C $McpServerRepo rev-parse --verify --quiet "refs/tags/$McpRelease" | Out-Null
if ($LASTEXITCODE) { throw "Tag $McpRelease is not in $McpServerRepo. Run 'git -C $McpServerRepo fetch --tags' or pass -McpRelease." }

$staging = Join-Path ([IO.Path]::GetTempPath()) "msp-labfiles-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    Copy-Item -Path (Join-Path $Source '*') -Destination $staging -Recurse
    Get-ChildItem $staging -Recurse -Directory -Include '__pycache__', 'data', 'mcp-src', 'mcp-server' | Remove-Item -Recurse -Force
    Get-ChildItem $staging -Recurse -File -Include '*.pyc', 'environment.json' | Remove-Item -Force

    # The MCP server release, exactly as tagged.
    $mcpZip = Join-Path ([IO.Path]::GetTempPath()) "mcp-server-$([guid]::NewGuid().ToString('N')).zip"
    git -C $McpServerRepo archive --format=zip --output $mcpZip $McpRelease
    if ($LASTEXITCODE) { throw "git archive $McpRelease failed ($LASTEXITCODE)" }
    $mcpDest = Join-Path $staging 'provision\mcp-server'
    Expand-Archive -LiteralPath $mcpZip -DestinationPath $mcpDest
    Remove-Item $mcpZip -Force
    $init = Get-Content (Join-Path $mcpDest 'src\servicedesk_mcp\__init__.py') -Raw
    if ($init -notmatch '__version__\s*=\s*"([^"]+)"' -or "v$($Matches[1])" -ne $McpRelease) {
        throw "Tag $McpRelease doesn't match the __version__ in its src/servicedesk_mcp/__init__.py."
    }

    if (Test-Path $Destination) { Remove-Item $Destination -Force }
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $Destination
    $files = (Get-ChildItem $staging -Recurse -File).Count
    Write-Host "Wrote $Destination ($files files, $([math]::Round((Get-Item $Destination).Length / 1KB)) KB) with MCP server $McpRelease"
}
finally {
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
