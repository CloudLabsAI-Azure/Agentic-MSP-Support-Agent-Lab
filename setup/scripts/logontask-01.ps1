<#
    logontask-01.ps1 - first-logon user-context script (stage 2 of 2).
    Launched by the 'Setup' scheduled task after psscript-01.ps1 reboots the VM and the lab user
    signs in once automatically. Takes no parameters. Owns the FINAL deployment status.
#>

$ErrorActionPreference = 'Stop'

$start = Get-Date
Start-Transcript -Path 'C:\WindowsAzure\Logs\CloudLabsLogOnTask.txt' -Append

Function SetDeploymentStatus($s, $m) {
    (Get-Content 'C:\WindowsAzure\Logs\status-sample.txt') -replace 'ReplaceStatus', $s `
        -replace 'ReplaceMessage', $m | Set-Content 'C:\WindowsAzure\Logs\validationstatus.txt'
}

try {
    . 'C:\LabFiles\cloudlabs-windows-functions.ps1'

    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:AZURE_EXTENSION_DIR = [Environment]::GetEnvironmentVariable('AZURE_EXTENSION_DIR', 'Machine')

    $settings = Get-Content 'C:\LabFiles\team-settings.json' -Raw | ConvertFrom-Json

    <# ---- VS Code extensions for this user. #>
    $codeCli = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
    if (-not (Test-Path $codeCli)) { $codeCli = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd" }
    foreach ($ext in @('ms-python.python', 'ms-vscode.powershell')) {
        & $codeCli --install-extension $ext --force
        if ($LASTEXITCODE) { Start-Sleep 10; & $codeCli --install-extension $ext --force }
    }

    <# ---- VS Code terminals open in PowerShell 7, which the lab scripts need. #>
    $codeUser = Join-Path $env:APPDATA 'Code\User'
    New-Item -ItemType Directory -Path $codeUser -Force | Out-Null
    $codeSettings = Join-Path $codeUser 'settings.json'
    if (-not (Test-Path $codeSettings)) {
        @{
            'terminal.integrated.profiles.windows'       = @{ 'PowerShell 7' = @{ path = 'C:\Program Files\PowerShell\7\pwsh.exe' } }
            'terminal.integrated.defaultProfile.windows' = 'PowerShell 7'
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $codeSettings -Encoding UTF8
    }

    <# ---- Desktop shortcuts for the portals the lab uses. #>
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcuts = [ordered]@{
        'Service Desk'                  = $settings.ServiceDeskAppUrl
        'Microsoft Foundry'             = 'https://ai.azure.com'
        'Azure Portal'                  = 'https://portal.azure.com'
        'Power Platform admin center'   = 'https://admin.powerplatform.microsoft.com'
        'Microsoft Entra admin center'  = 'https://entra.microsoft.com'
    }
    foreach ($name in $shortcuts.Keys) {
        "[InternetShortcut]`r`nURL=$($shortcuts[$name])" | Set-Content -Path (Join-Path $desktop "$name.url") -Encoding ASCII
    }

    <# ---- Plain-text summary of this team's names, on the desktop. #>
    $summary = @(
        'Agentic MSP Support Agent lab: your team environment'
        ''
        "Resource group           $($settings.ResourceGroup)"
        "Service Desk app         $($settings.ServiceDeskAppUrl)"
        "Dataverse environment    $($settings.DataverseUrl)"
        "Foundry project endpoint $($settings.FoundryProjectEndpoint)"
        "Agent name               $($settings.AgentName)"
        "AI Search endpoint       $($settings.SearchEndpoint)"
        "MCP server (direct)      $($settings.McpServerUrl)"
        "MCP gateway (agent)      $($settings.McpGatewayUrl)"
        "MCP gateway (operator)   $($settings.McpDiagnosticsUrl)"
        "MCP gateway audience     $($settings.McpGatewayAudience)"
        "Container registry       $($settings.ContainerRegistryLoginServer)"
        "Container app            $($settings.ContainerApp)"
        ''
        'Full settings: C:\LabFiles\team-settings.json'
    )
    $summary | Set-Content -Path (Join-Path $desktop 'Team environment.txt') -Encoding UTF8

    <# ---- Notes file the lab guide asks the team to fill in as they go. #>
    $notesPath = Join-Path $desktop 'Lab notes.txt'
    if (-not (Test-Path $notesPath)) {
        @(
            'Agentic MSP Support Agent lab: team notes'
            'Keep this file open. The lab guide tells you what to record here.'
            ''
            '== Exercise 1 =='
            'Environment check (pass or fail, with what you saw):'
            '  Resource group:'
            '  Service Desk app and seeded data:'
            '  Foundry agent (no knowledge, no tools):'
            '  Agent identity:'
            '  MCP health and reference tool call:'
            'Agent identity object ID:'
            'Agent identity client ID:'
            'Thin explanations to revisit in Exercise 5:'
            ''
            '== Exercise 2 =='
            'Triage recommendation for TCK-10512 (agree or not, and why):'
            ''
            '== Exercise 3 =='
            'get_ticket call through API Management: SessionId / CorrelationId:'
            'Redeploy cycle time (build / full cycle):'
            ''
            '== Exercise 4 =='
            'Time of the assign_ticket write on TCK-10507 (UTC):'
            'Boundary test on TCK-10501, before and after the fix:'
            ''
            '== Exercise 5 =='
            'Agent identity permissions:'
            'MCP application user permissions:'
            'One sentence on inherited permissions:'
            'Least-privilege boundary (one sentence):'
            'Platform error captured (code and message):'
            'Trace join: which join was manual, and why:'
            ''
            '== Findings (agent behavior to fix, any exercise) =='
        ) | Set-Content -Path $notesPath -Encoding UTF8
    }

    <# ---- VALIDATION TABLE drives the final status. #>
    $provision = Get-Content 'C:\LabFiles\provision-status.json' -Raw | ConvertFrom-Json
    $requiredSteps = 'signin', 'settings', 'environment', 'schema', 'security', 'seed', 'mcp', 'agent', 'gateway', 'files', 'smoketest'
    $health = $null
    try { $health = Invoke-RestMethod -Uri "$($settings.McpServerUrl)/health" -TimeoutSec 15 } catch { $health = $null }
    # The team's local Git copy of the MCP server, readable by this user's Git (safe.directory).
    $mcpSourceOk = $false
    try { $mcpSourceOk = (Test-Path 'C:\LabFiles\mcp-server\.git') -and [bool](& git -C 'C:\LabFiles\mcp-server' tag --list 2>$null) }
    catch { $mcpSourceOk = $false }
    $checks = @()
    foreach ($step in $requiredSteps) {
        $state = $provision.$step.state
        $checks += @{ Name = "provisioning step $step"; Ok = ($state -eq 'Succeeded') }
    }
    $checks += @(
        @{ Name = 'MCP server health';        Ok = ($health -and $health.status -eq 'ok') },
        @{ Name = 'agent identity recorded';   Ok = [bool]$settings.AgentIdentityClientId },
        @{ Name = 'search index definition';   Ok = (Test-Path 'C:\LabFiles\search\index-definition.json') },
        @{ Name = 'search loader';             Ok = (Test-Path 'C:\LabFiles\search\Load-SearchIndex.ps1') },
        @{ Name = 'tool invoker';              Ok = (Test-Path 'C:\LabFiles\tools\Invoke-McpTool.ps1') },
        @{ Name = 'MCP server source';         Ok = $mcpSourceOk },
        @{ Name = 'agent helper scripts';      Ok = ((Test-Path 'C:\LabFiles\tools\Get-AgentIdentity.ps1') -and
                                                     (Test-Path 'C:\LabFiles\tools\Update-AgentDefinition.ps1')) },
        @{ Name = 'agent instructions';        Ok = ((Test-Path 'C:\LabFiles\agent\instructions-ex1.md') -and
                                                     (Test-Path 'C:\LabFiles\agent\instructions-ex3.md')) },
        @{ Name = 'git';                       Ok = [bool](Get-Command git -ErrorAction SilentlyContinue) },
        @{ Name = 'azure cli';                 Ok = [bool](Get-Command az -ErrorAction SilentlyContinue) },
        @{ Name = 'powershell 7';              Ok = (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') },
        @{ Name = 'vs code';                   Ok = (Test-Path $codeCli) },
        @{ Name = 'service desk shortcut';     Ok = (Test-Path (Join-Path $desktop 'Service Desk.url')) }
    )
    $failed = $checks | Where-Object { -not $_.Ok }
    if ($failed) {
        $ValidStatus  = 'Failed'
        $ValidMessage = 'Validation failed: ' + (($failed | ForEach-Object Name) -join ', ')
    } else {
        $ValidStatus  = 'Succeeded'
        $ValidMessage = 'Environment is validated and deployment is successful'
    }
}
catch {
    $ValidStatus  = 'Failed'
    $ValidMessage = 'Logon task failed: ' + ($_.Exception.Message -replace '[^\x20-\x7E]', ' ' -replace '["$\\]', ' ')
    Write-Warning $ValidMessage
}

try { SetDeploymentStatus $ValidStatus $ValidMessage } catch { Write-Warning "SetDeploymentStatus failed: $($_.Exception.Message)" }
Start-Sleep 3

$Validstatus  = $ValidStatus
$Validmessage = $ValidMessage
try { CloudlabsManualAgent setStatus } catch { Write-Warning "setStatus failed: $($_.Exception.Message)" }
try { CloudlabsManualAgent Start }     catch { Write-Warning "agent Start failed: $($_.Exception.Message)" }

Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' `
    -Name DefaultPassword -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Setup' -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "Logon task completed in $([int]((Get-Date) - $start).TotalSeconds)s with status $ValidStatus"
Stop-Transcript
