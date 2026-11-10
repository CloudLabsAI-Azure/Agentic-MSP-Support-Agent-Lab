#requires -Version 7.2

<#
.SYNOPSIS
Downloads the official Microsoft icon packs once and stages the icons that lab diagrams use, by key.

.DESCRIPTION
Lab diagrams (svgkit.py) load icons by key: the key "vm" reads <IconsPath>/vm.svg. This script
downloads the official Microsoft icon packs to a cache folder outside the repository, extracts
only their SVG files, and copies the icons listed in the icon map below into the icons folder
under their keys. Run it once per machine and lab, and again after you add keys to the map.

The icon map at the top of this script is a data table. To add an icon, run the script with
-Find to locate it in the packs, then paste the printed row into $IconMap (product icons) or add
the name to a concept icon list in $ConceptSets. Keys are lowercase words joined by hyphens;
concept icons get the prefix c- (Microsoft blue) or p- (Teams purple).

Microsoft icon terms (read the terms file inside each pack before you publish):
  * Microsoft permits these icons in architecture diagrams, training materials and
    documentation, which covers lab guides and their diagrams.
  * Use the icons as they are: do not crop, flip, rotate, distort, recolor or otherwise alter
    them, and do not combine them into new marks.
  * Show the product name near each product icon, so the icon is never the only label.
  * Do not use Microsoft product icons to represent your own product or service.
Download pages, with the terms:
  Azure architecture icons:            https://learn.microsoft.com/azure/architecture/icons/
  Microsoft Entra architecture icons:  https://learn.microsoft.com/entra/architecture/architecture-icons
  Power Platform icons (incl. Copilot Studio and Agent 365):
                                       https://learn.microsoft.com/power-platform/guidance/icons
  Microsoft 365 architecture icons (concept icons):
                                       https://learn.microsoft.com/microsoft-365/solutions/architecture-icons-templates

The packs are never committed. They are large (about 10 MB of downloads, about 1,700 SVG files
plus templates and terms documents), and every diagram embeds the few icons it uses as data URIs,
so the committed SVG and PNG files are self-contained. The cache lives outside the repository by default, and the staged icons folder
is git-ignored (tools/diagrams/.gitignore).

.PARAMETER IconsPath
Folder that receives the staged icons, one <key>.svg per icon. Created when missing.
Default: the icons folder next to this script (tools/diagrams/icons in a lab repository).
Alias: Destination.

.PARAMETER CachePath
Folder that keeps the downloaded packs and their extracted SVG files between runs.
Default: cloudlabs-lab-builder/icon-packs under the user's local application data folder
(%LOCALAPPDATA% on Windows).

.PARAMETER Key
Stage only these keys. Default: every key in the icon map. With -Key, the script exits with
code 1 when a requested key cannot be staged.

.PARAMETER Refresh
Download and extract the packs again even when they are already in the cache.

.PARAMETER Find
Search the cached packs (downloading them first if needed) for SVG files whose name contains
this text or matches this wildcard pattern, and print map rows ready to paste. Spaces, hyphens
and underscores match each other. Stages nothing.

.PARAMETER ListKeys
Print every key in the icon map with its pack and path, and stage nothing. Needs no download.

.EXAMPLE
pwsh tools/diagrams/Get-ProductIcons.ps1 -IconsPath tools/diagrams/icons
Stages every icon in the map into the lab's icons folder.

.EXAMPLE
pwsh tools/diagrams/Get-ProductIcons.ps1 -Find 'key vault'
Shows where the Key Vault icon is in the packs, as a row for $IconMap.

.EXAMPLE
pwsh tools/diagrams/Get-ProductIcons.ps1 -ListKeys
Lists the keys that diagrams can use.
#>
[CmdletBinding(DefaultParameterSetName = 'Stage')]
param(
    [Parameter(ParameterSetName = 'Stage')]
    [Alias('Destination')]
    [string]$IconsPath = (Join-Path $PSScriptRoot 'icons'),

    [string]$CachePath,

    [Parameter(ParameterSetName = 'Stage')]
    [string[]]$Key,

    [switch]$Refresh,

    [Parameter(ParameterSetName = 'Find', Mandatory)]
    [string]$Find,

    [Parameter(ParameterSetName = 'List', Mandatory)]
    [switch]$ListKeys
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# A list arrives as one comma-separated string when the script is started with pwsh -File from
# another shell (-Key "vm,key-vault"), so split it here.
if ($Key) { $Key = @($Key | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

# ==== Icon packs ===============================================================================
# Url: the official download. Base: the folder inside the extracted pack that map paths start
# from. When Microsoft publishes a new pack version, update Url (and Base if the layout changed);
# the resolver below also finds icons whose number prefix or folder moved.
$Packs = [ordered]@{
    azure = @{ Url = 'https://arch-center.azureedge.net/icons/Azure_Public_Service_Icons_V24.zip'
               Base = 'Azure_Public_Service_Icons/Icons' }
    entra = @{ Url = 'https://download.microsoft.com/download/3/1/a/31a56038-856a-4489-88e4-ee5a1c4352be/Microsoft%20Entra%20architecture%20icons%20-%20Oct%202023.zip'
               Base = 'Microsoft Entra architecture icons - Oct 2023/Microsoft Entra color icons SVG' }
    pp    = @{ Url = 'https://download.microsoft.com/download/498606aa-6d27-4f13-aa5c-1401078c153b/Power-Platform-icons-scalable.zip'
               Base = '' }
    m365  = @{ Url = 'https://go.microsoft.com/fwlink/?linkid=869455'
               Base = '' }
}

# ==== Product icons: key = pack, path below the pack's Base =====================================
$IconMap = [ordered]@{
    # Azure: compute, containers, web
    'vm'                    = 'azure', 'compute/10021-icon-service-Virtual-Machine.svg'
    'app-service'           = 'azure', 'app services/10035-icon-service-App-Services.svg'
    'app-service-plan'      = 'azure', 'app services/00046-icon-service-App-Service-Plans.svg'
    'function-app'          = 'azure', 'compute/10029-icon-service-Function-Apps.svg'
    'static-web-app'        = 'azure', 'web/01007-icon-service-Static-Apps.svg'
    'aks'                   = 'azure', 'containers/10023-icon-service-Kubernetes-Services.svg'
    'container-registry'    = 'azure', 'containers/10105-icon-service-Container-Registries.svg'
    'container-apps-env'    = 'azure', 'other/02989-icon-service-Container-Apps-Environments.svg'
    'container-app'         = 'azure', 'other/02884-icon-service-Worker-Container-App.svg'
    'container-instances'   = 'azure', 'containers/10104-icon-service-Container-Instances.svg'
    # Azure: data and storage
    'storage-account'       = 'azure', 'storage/10086-icon-service-Storage-Accounts.svg'
    'sql-database'          = 'azure', 'databases/10130-icon-service-SQL-Database.svg'
    'azure-sql'             = 'azure', 'databases/02390-icon-service-Azure-SQL.svg'
    'cosmos-db'             = 'azure', 'databases/10121-icon-service-Azure-Cosmos-DB.svg'
    'databricks'            = 'azure', 'analytics/10787-icon-service-Azure-Databricks.svg'
    'synapse'               = 'azure', 'analytics/00606-icon-service-Azure-Synapse-Analytics.svg'
    'data-factory'          = 'azure', 'integration/10126-icon-service-Data-Factories.svg'
    'event-hubs'            = 'azure', 'analytics/00039-icon-service-Event-Hubs.svg'
    # Azure: integration and DevOps
    'logic-apps'            = 'azure', 'integration/02631-icon-service-Logic-Apps.svg'
    'api-management'        = 'azure', 'integration/10042-icon-service-API-Management-Services.svg'
    'service-bus'           = 'azure', 'integration/10836-icon-service-Azure-Service-Bus.svg'
    'azure-devops'          = 'azure', 'devops/10261-icon-service-Azure-DevOps.svg'
    # Azure: AI
    'foundry'               = 'azure', 'ai + machine learning/035746832-icon-service-AI-Foundry.svg'
    'foundry-agents'        = 'azure', 'ai + machine learning/038470523-icon-service-Foundry-Agent-Service.svg'
    'foundry-models'        = 'azure', 'ai + machine learning/038470614-icon-service-Foundry-Models.svg'
    'azure-openai'          = 'azure', 'ai + machine learning/03438-icon-service-Azure-OpenAI.svg'
    'ai-search'             = 'azure', 'ai + machine learning/10044-icon-service-Cognitive-Search.svg'
    'machine-learning'      = 'azure', 'ai + machine learning/10166-icon-service-Machine-Learning.svg'
    'content-safety'        = 'azure', 'ai + machine learning/03390-icon-service-Content-Safety.svg'
    'document-intelligence' = 'azure', 'ai + machine learning/00819-icon-service-Form-Recognizers.svg'
    'bot-service'           = 'azure', 'ai + machine learning/10165-icon-service-Bot-Services.svg'
    # Azure: networking
    'virtual-network'       = 'azure', 'networking/10061-icon-service-Virtual-Networks.svg'
    'nsg'                   = 'azure', 'networking/10067-icon-service-Network-Security-Groups.svg'
    'bastion'               = 'azure', 'networking/02422-icon-service-Bastions.svg'
    'firewall'              = 'azure', 'networking/10084-icon-service-Firewalls.svg'
    'public-ip'             = 'azure', 'networking/10069-icon-service-Public-IP-Addresses.svg'
    # Azure: management, monitoring and cost
    'subscription'          = 'azure', 'general/10002-icon-service-Subscriptions.svg'
    'management-group'      = 'azure', 'general/10011-icon-service-Management-Groups.svg'
    'resource-group'        = 'azure', 'general/10007-icon-service-Resource-Groups.svg'
    'policy'                = 'azure', 'management + governance/10316-icon-service-Policy.svg'
    'arc'                   = 'azure', 'management + governance/00756-icon-service-Azure-Arc.svg'
    'automation'            = 'azure', 'management + governance/00022-icon-service-Automation-Accounts.svg'
    'recovery-vault'        = 'azure', 'management + governance/00017-icon-service-Recovery-Services-Vaults.svg'
    'monitor'               = 'azure', 'monitor/00001-icon-service-Monitor.svg'
    'log-analytics'         = 'azure', 'monitor/00009-icon-service-Log-Analytics-Workspaces.svg'
    'app-insights'          = 'azure', 'monitor/00012-icon-service-Application-Insights.svg'
    'cost-management'       = 'azure', 'general/10019-icon-service-Cost-Management.svg'
    'cost-budgets'          = 'azure', 'general/10793-icon-service-Cost-Budgets.svg'
    'cost-alerts'           = 'azure', 'general/10791-icon-service-Cost-Alerts.svg'
    # Azure: identity and security
    'key-vault'             = 'azure', 'security/10245-icon-service-Key-Vaults.svg'
    'defender-for-cloud'    = 'azure', 'security/10241-icon-service-Microsoft-Defender-for-Cloud.svg'
    'sentinel'              = 'azure', 'security/10248-icon-service-Azure-Sentinel.svg'
    'conditional-access'    = 'azure', 'security/10233-icon-service-Conditional-Access.svg'
    'id-protection'         = 'azure', 'identity/10231-icon-service-Entra-ID-Protection.svg'
    'users'                 = 'azure', 'identity/10230-icon-service-Users.svg'
    'groups'                = 'azure', 'identity/10223-icon-service-Groups.svg'
    'managed-identity'      = 'azure', 'identity/10227-icon-service-Managed-Identities.svg'
    'app-registration'      = 'azure', 'identity/10232-icon-service-App-Registrations.svg'
    # Microsoft Entra
    'entra'                 = 'entra', 'Microsoft Entra Product Family.svg'
    'entra-id'              = 'entra', 'Microsoft Entra ID color icon.svg'
    'entra-governance'      = 'entra', 'Microsoft Entra ID Governance color icon.svg'
    'entra-internet-access' = 'entra', 'Microsoft Entra Internet Access color icon.svg'
    'entra-private-access'  = 'entra', 'Microsoft Entra Private Access color icon.svg'
    'entra-verified-id'     = 'entra', 'Microsoft Entra Verified ID color icon.svg'
    'entra-workload-id'     = 'entra', 'Microsoft Entra Workload ID color icon.svg'
    # Power Platform, Copilot Studio and Agent 365
    'agent365'              = 'pp', 'Agent365_scalable.svg'
    'copilot-studio'        = 'pp', 'CopilotStudio_scalable.svg'
    'power-platform'        = 'pp', 'Power Platform/PowerPlatform_scalable.svg'
    'power-apps'            = 'pp', 'Power Platform/PowerApps_scalable.svg'
    'power-automate'        = 'pp', 'Power Platform/PowerAutomate_scalable.svg'
    'power-pages'           = 'pp', 'Power Platform/PowerPages_scalable.svg'
    'dataverse'             = 'pp', 'Power Platform/Dataverse_scalable.svg'
    'ai-builder'            = 'pp', 'Power Platform/AIBuilder_scalable.svg'
}

# ==== Concept icons (Microsoft 365 pack): key = prefix + name in lowercase with hyphens ==========
# For example 'Window Dev Edit' in the c- set becomes the key c-window-dev-edit.
$ConceptSets = [ordered]@{
    'c-' = @{
        Pack   = 'm365'
        Folder = 'Microsoft Blue/48x48 Light Blue Icon'
        Names  = @(
            'Apps', 'Arrow Sync', 'Bot', 'Building', 'Building Cloud', 'Building Multiple', 'Calculator',
            'Calendar Month', 'Certificate', 'Chart Multiple', 'Chat', 'Chat Multiple', 'Checkmark Circle',
            'Clipboard Task List', 'Clock', 'Cloud', 'Cloud Database', 'Cloud Desktop', 'Code', 'Data Pie',
            'Data Trending', 'Data Usage', 'Database', 'Deploy', 'Desktop Tower', 'Document', 'Document Lock',
            'Document Text', 'Fingerprint', 'Flag', 'Folder Open', 'Globe', 'Grid Circles', 'Handshake',
            'Hat Graduation', 'Headset', 'Key', 'Laptop', 'Layer Diagonal', 'Lightbulb', 'Lightbulb Checkmark',
            'Lock Closed', 'Lock Shield', 'Mail', 'Map', 'Megaphone Loud', 'Organization', 'Payment', 'People',
            'People Team', 'Person', 'Person Accounts', 'Presenter', 'Radar', 'Receipt', 'Ribbon Star', 'Script',
            'Search', 'Settings', 'Shapes Three', 'Share', 'Shield Error', 'Task List Square', 'Toolbox',
            'Top Speed', 'Wallet Credit Card', 'Window Dev Edit', 'Wrench'
        )
    }
    'p-' = @{
        Pack   = 'm365'
        Folder = 'Teams Purple/48x48 Light Purple Icon'
        Names  = @(
            'Bot', 'Chat Multiple', 'Checkmark Circle', 'Data Trending', 'Document Lock', 'Document Text',
            'Fingerprint', 'Key', 'Lightbulb', 'Lock Shield', 'People Team', 'Person', 'Person Accounts',
            'Radar', 'Settings', 'Shield Error'
        )
    }
}

# ==== Implementation ===========================================================================

function ConvertTo-IconKey([string]$Name) {
    ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
}

# Every key, including the concept icons, as key = pack, path.
$AllIcons = [ordered]@{}
foreach ($k in $IconMap.Keys) { $AllIcons[$k] = $IconMap[$k] }
foreach ($prefix in $ConceptSets.Keys) {
    $set = $ConceptSets[$prefix]
    foreach ($n in $set.Names) { $AllIcons[$prefix + (ConvertTo-IconKey $n)] = $set.Pack, "$($set.Folder)/$n.svg" }
}

if ($ListKeys) {
    $AllIcons.Keys | ForEach-Object {
        [pscustomobject]@{ Key = $_; Pack = $AllIcons[$_][0]; Path = $AllIcons[$_][1] }
    } | Format-Table -AutoSize | Out-String -Width 220 | Write-Output
    Write-Output "$($AllIcons.Count) keys."
    return
}

if (-not $CachePath) {
    $appData = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $appData) { $appData = [IO.Path]::GetTempPath() }
    $CachePath = Join-Path $appData 'cloudlabs-lab-builder' 'icon-packs'
}
New-Item -ItemType Directory -Force -Path $CachePath | Out-Null
$CachePath = (Resolve-Path -LiteralPath $CachePath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Downloads one pack (once) and extracts its SVG files into a folder of its own.
# Returns the extraction folder, or $null when the pack is unavailable.
function Get-IconPack([string]$Pack) {
    $zip = Join-Path $CachePath "$Pack.zip"
    $dir = Join-Path $CachePath $Pack
    $marker = Join-Path $dir '.extracted'
    if ($Refresh -or -not (Test-Path -LiteralPath $zip)) {
        $partial = "$zip.partial"
        Write-Host "Downloading the $Pack icon pack from $($Packs[$Pack].Url)"
        $ok = $false
        foreach ($attempt in 1..3) {
            try {
                Invoke-WebRequest -Uri $Packs[$Pack].Url -OutFile $partial -TimeoutSec 600
                $ok = $true
                break
            }
            catch {
                Write-Warning "Attempt $attempt to download the $Pack pack failed: $($_.Exception.Message)"
                Start-Sleep -Seconds (5 * $attempt)
            }
        }
        if (-not $ok) { return $null }
        Move-Item -LiteralPath $partial -Destination $zip -Force
    }
    $stamp = '{0} {1}' -f (Get-Item -LiteralPath $zip).Length, (Get-Item -LiteralPath $zip).LastWriteTimeUtc.Ticks
    if ((Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $stamp)) { return $dir }

    # Extract only the SVG files, each pack into a new, empty folder, and never outside it.
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $root = [IO.Path]::GetFullPath($dir).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
        $count = 0
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName -replace '\\', '/'
            if (-not $name.EndsWith('.svg', [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (($name -split '/') -contains '..' -or $name.StartsWith('/') -or $name -match '^[A-Za-z]:') { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $dir $name))
            if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            $count++
        }
    }
    catch {
        Write-Warning "The $Pack pack at $zip could not be read: $($_.Exception.Message). Run again with -Refresh."
        return $null
    }
    finally {
        if ($archive) { $archive.Dispose() }
    }
    Set-Content -LiteralPath $marker -Value $stamp -NoNewline
    Write-Host "Extracted $count SVG files from the $Pack pack"
    return $dir
}

# Index of a pack's SVG files as relative paths with forward slashes.
$indexes = @{}
function Get-PackIndex([string]$Pack, [string]$Dir) {
    if (-not $indexes.ContainsKey($Pack)) {
        $indexes[$Pack] = @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Filter '*.svg' | ForEach-Object {
                [pscustomobject]@{ Rel = ([IO.Path]::GetRelativePath($Dir, $_.FullName) -replace '\\', '/'); Full = $_.FullName }
            })
    }
    $indexes[$Pack]
}

# Finds the file for one map entry. Tries the exact path, then any path that ends with it, then
# (for Azure icons) the same service name under a new number, then the file name in a folder of
# the same name.
function Resolve-Icon([string]$Pack, [string]$Dir, [string]$Path) {
    $base = $Packs[$Pack].Base
    $wanted = if ($base) { "$base/$Path" } else { $Path }
    $index = Get-PackIndex $Pack $Dir
    $hit = $index | Where-Object { $_.Rel -ieq $wanted } | Select-Object -First 1
    if (-not $hit) { $hit = $index | Where-Object { $_.Rel.EndsWith("/$Path", [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1 }
    $leaf = ($Path -split '/')[-1]
    $parent = if ($Path.Contains('/')) { ($Path -split '/')[-2] } else { '' }
    if (-not $hit -and $leaf -match '^\d+\s*-icon-service-(.+)$') {
        $suffix = "-icon-service-$($Matches[1])"
        $cands = @($index | Where-Object { ($_.Rel -split '/')[-1].EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase) })
        $hit = ($cands | Where-Object { $parent -and $_.Rel -ilike "*/$parent/*" } | Select-Object -First 1) ?? ($cands | Select-Object -First 1)
    }
    if (-not $hit) {
        $cands = @($index | Where-Object { ($_.Rel -split '/')[-1] -ieq $leaf })
        $hit = ($cands | Where-Object { $parent -and $_.Rel -ilike "*/$parent/*" } | Select-Object -First 1) ?? ($cands | Select-Object -First 1)
    }
    if ($hit) { $hit.Full } else { $null }
}

if ($PSCmdlet.ParameterSetName -eq 'Find') {
    $pattern = $Find -replace '[-_ ]+', ' '
    if ($pattern -notmatch '[*?\[]') { $pattern = "*$pattern*" }
    $rows = foreach ($pack in $Packs.Keys) {
        $dir = Get-IconPack $pack
        if (-not $dir) { continue }
        $base = $Packs[$pack].Base
        foreach ($item in (Get-PackIndex $pack $dir)) {
            $leafName = [IO.Path]::GetFileNameWithoutExtension(($item.Rel -split '/')[-1])
            if (($leafName -replace '[-_ ]+', ' ') -notlike $pattern) { continue }
            $rel = if ($base -and $item.Rel.StartsWith("$base/", [StringComparison]::OrdinalIgnoreCase)) { $item.Rel.Substring($base.Length + 1) } else { $item.Rel }
            $name = $leafName -replace '^\d+\s*-icon-service-', '' -replace '_scalable$', '' -replace ' color icon$', ''
            [pscustomobject]@{ Pack = $pack; Row = ("'{0}' = '{1}', '{2}'" -f (ConvertTo-IconKey $name), $pack, $rel) }
        }
    }
    if (-not $rows) { Write-Output "No icon file name matches '$Find'."; return }
    Write-Output "Rows for `$IconMap (check the key name; Microsoft 365 concept icons usually go in `$ConceptSets instead):"
    $rows | Select-Object -First 60 | ForEach-Object { Write-Output ('    {0}' -f $_.Row) }
    if (@($rows).Count -gt 60) { Write-Output "    ... $(@($rows).Count - 60) more; narrow the search." }
    return
}

# ==== Stage the icons ==========================================================================
$selected = if ($Key) { @($Key | ForEach-Object { $_.ToLowerInvariant() }) } else { @($AllIcons.Keys) }
$unknown = @($selected | Where-Object { -not $AllIcons.Contains($_) })
if ($unknown) {
    throw "Unknown key(s): $($unknown -join ', '). Add them to the icon map, or run with -ListKeys to see the keys."
}

New-Item -ItemType Directory -Force -Path $IconsPath | Out-Null
$IconsPath = (Resolve-Path -LiteralPath $IconsPath).Path
$packDirs = @{}
$failedPacks = @()
foreach ($pack in @($selected | ForEach-Object { $AllIcons[$_][0] } | Sort-Object -Unique)) {
    $dir = Get-IconPack $pack
    if ($dir) { $packDirs[$pack] = $dir } else { $failedPacks += $pack }
}

$missing = @()
$staged = 0
foreach ($k in $selected) {
    $pack, $path = $AllIcons[$k]
    if (-not $packDirs.ContainsKey($pack)) { $missing += $k; continue }
    $src = Resolve-Icon $pack $packDirs[$pack] $path
    if (-not $src) { $missing += $k; continue }
    # Copied byte for byte: the icon terms do not allow altered icons.
    Copy-Item -LiteralPath $src -Destination (Join-Path $IconsPath "$k.svg") -Force
    $staged++
}

Write-Host ("Staged {0} of {1} icons in {2}" -f $staged, $selected.Count, $IconsPath)
Write-Host 'Icon terms: use them unaltered, in diagrams and training material, with the product name near each icon.'
if ($failedPacks) { Write-Warning "Could not download or read: $($failedPacks -join ', '). Check the Url in `$Packs or try -Refresh." }
if ($missing) { Write-Warning "Not found in the current packs: $($missing -join ', '). Run -Find to locate them and update the map." }
if ($failedPacks -or ($Key -and $missing)) { exit 1 }
