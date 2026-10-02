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

    <# ==== VS Code extensions for this user. #>
    $codeCli = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
    if (-not (Test-Path $codeCli)) { $codeCli = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd" }
    foreach ($ext in @('ms-python.python', 'ms-vscode.powershell')) {
        & $codeCli --install-extension $ext --force
        if ($LASTEXITCODE) { Start-Sleep 10; & $codeCli --install-extension $ext --force }
    }

    <# ==== VS Code terminals open in PowerShell 7, which the lab scripts need. #>
    $codeUser = Join-Path $env:APPDATA 'Code\User'
    New-Item -ItemType Directory -Path $codeUser -Force | Out-Null
    $codeSettings = Join-Path $codeUser 'settings.json'
    if (-not (Test-Path $codeSettings)) {
        @{
            'terminal.integrated.profiles.windows'       = @{ 'PowerShell 7' = @{ path = 'C:\Program Files\PowerShell\7\pwsh.exe' } }
            'terminal.integrated.defaultProfile.windows' = 'PowerShell 7'
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $codeSettings -Encoding UTF8
    }

    <# ==== Desktop shortcuts for the portals the lab uses, and the readiness check. #>
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcuts = [ordered]@{
        'Service Desk'                  = $settings.ServiceDeskAppUrl
        'Microsoft Foundry'             = 'https://ai.azure.com'
        'Azure Portal'                  = 'https://portal.azure.com'
        'Microsoft Purview'             = 'https://purview.microsoft.com'
        'Power Platform admin center'   = 'https://admin.powerplatform.microsoft.com'
        'Microsoft Entra admin center'  = 'https://entra.microsoft.com'
    }
    foreach ($name in $shortcuts.Keys) {
        "[InternetShortcut]`r`nURL=$($shortcuts[$name])" | Set-Content -Path (Join-Path $desktop "$name.url") -Encoding ASCII
    }
    $shell = New-Object -ComObject WScript.Shell
    $readiness = $shell.CreateShortcut((Join-Path $desktop 'Lab readiness check.lnk'))
    $readiness.TargetPath = 'C:\Program Files\PowerShell\7\pwsh.exe'
    $readiness.Arguments = '-NoProfile -ExecutionPolicy Bypass -NoExit -File C:\LabFiles\tools\Test-LabReadiness.ps1'
    $readiness.WorkingDirectory = 'C:\LabFiles'
    $readiness.Description = 'Checks every component of your lab environment'
    $readiness.Save()

    <# ==== Plain-text summary of this team's names, on the desktop. #>
    $summary = @(
        'Agentic MSP Support Agent lab: your team environment'
        ''
        "Resource group            $($settings.ResourceGroup)"
        "Senior Technician         $($settings.TeamUser)"
        "Tier 1 Technician         $($settings.Tier1User)"
        "Service Desk app          $($settings.ServiceDeskAppUrl)"
        "Dataverse environment     $($settings.DataverseUrl)"
        "Foundry project endpoint  $($settings.FoundryProjectEndpoint)"
        "Agent name                $($settings.AgentName)"
        "MCP connection            $($settings.McpConnectionName)"
        "AI Search endpoint        $($settings.SearchEndpoint)"
        "MCP gateway (agent)       $($settings.McpGatewayUrl)"
        "MCP gateway (diagnostics) $($settings.McpDiagnosticsUrl)"
        "MCP server (direct)       $($settings.McpServerUrl)"
        "Key Vault                 $($settings.KeyVaultUrl)"
        "Container registry        $($settings.ContainerRegistryLoginServer)"
        "Container app             $($settings.ContainerApp)"
        "MCP server source         $($settings.McpServerSource)"
        ''
        'Full settings: C:\LabFiles\team-settings.json'
    )
    $summary | Set-Content -Path (Join-Path $desktop 'Team environment.txt') -Encoding UTF8

    <# ==== Notes file the lab guide asks the team to fill in as they go. #>
    $notesPath = Join-Path $desktop 'Lab notes.txt'
    if (-not (Test-Path $notesPath)) {
        @(
            'Agentic MSP Support Agent lab: team notes'
            'Keep this file open. The lab guide tells you what to record here.'
            ''
            '== Exercise 1: Environment Readiness and Grounding the Agent =='
            'Readiness check (every component Ready? anything else you saw):'
            'Index document count, and the count the loader expected:'
            'Ambiguous case: the two articles, your recommendation, and the deciding attribute:'
            'Thin explanations to revisit in Exercise 6:'
            ''
            '== Exercise 2: Ticket and Incident Intelligence =='
            'TCK-10514: closest historical tickets, and why they are similar:'
            'Customer history summary: customer, open tickets the agent counted, open tickets in the app:'
            'TCK-10514: recommended priority, category and technician or team:'
            'Ticket closest to an SLA breach, and the working:'
            ''
            '== Exercise 3: Using the MCP Read Tools =='
            'Tool you traced to its Dataverse query:'
            'Permission each read tool needs (for Exercise 5):'
            'Correlation ID of your first read tool call:'
            'Redeploy: your change, the new revision, how long the cycle took, how to roll back:'
            ''
            '== Exercise 4: Using the MCP Action Tools =='
            'Approved write: ticket, change, correlation ID:'
            'Declined write: ticket, confirmed unchanged:'
            'Customer-visible reply and internal note: ticket and note codes:'
            'Grounded action on TCK-10514: recommendation, sources, correlation ID:'
            'get_open_tickets limit before and after, and the rejected call:'
            'Your scoped tool: name, description, permission, approval:'
            ''
            '== Exercise 5: Identity, Secrets and Authorization =='
            'Identities on one write: user, Entra Agent ID, gateway, MCP managed identity, Dataverse application user:'
            'Backend credential: Key Vault secret name, and the access log entry at startup:'
            'Boundary you narrowed, and the Dataverse error:'
            'Tier 1 attempt (denied) and Senior attempt (allowed), with correlation IDs:'
            ''
            '== Exercise 6: Data Protection and Auditability =='
            'What the agent could not return, and what it said:'
            'Microsoft Purview: policy, sensitive information type, DLP event time:'
            'End-to-end trail: correlation ID and each hop you found:'
            ''
            '== Exercise 7: End-to-End Scenario and Business Case =='
            'TCK-10515: customer, recommendation, action taken, correlation ID:'
            ''
            '== Business case =='
            'Problem today:'
            'What the agent does (grounding and tools):'
            'Controls (identity, least privilege, approval, data protection, audit):'
            'Evidence from this lab:'
            'Operational value for the MSP (time, consistency, SLA):'
            'Risks and next steps:'
        ) | Set-Content -Path $notesPath -Encoding UTF8
    }

    <# ==== VALIDATION TABLE drives the final status. #>
    $provision = Get-Content 'C:\LabFiles\provision-status.json' -Raw | ConvertFrom-Json
    $requiredSteps = 'signin', 'settings', 'environment', 'schema', 'security', 'seed', 'export', 'incidents', 'mcp', 'agent', 'files',
                     'readiness'
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
        @{ Name = 'MCP server health';        Ok = ($health -and $health.status -eq 'ok' -and $health.gateway_key_source -eq 'key vault') },
        @{ Name = 'Entra Agent ID recorded';   Ok = [bool]$settings.AgentIdentityClientId },
        @{ Name = 'search index definition';   Ok = (Test-Path 'C:\LabFiles\search\index-definition.json') },
        @{ Name = 'search loader and export';  Ok = ((Test-Path 'C:\LabFiles\search\Load-SearchIndex.ps1') -and
                                                     (Test-Path 'C:\LabFiles\search\export\documents.json')) },
        @{ Name = 'MCP server source';         Ok = $mcpSourceOk },
        @{ Name = 'lab tools';                 Ok = (@('Test-LabReadiness.ps1', 'Invoke-McpTool.ps1', 'Show-McpServerLog.ps1', 'Get-ActionTrail.ps1',
                                                       'Get-AgentIdentity.ps1', 'Update-AgentDefinition.ps1', 'Get-DocumentLabel.ps1') |
                                                     Where-Object { -not (Test-Path "C:\LabFiles\tools\$_") }).Count -eq 0 },
        @{ Name = 'agent instructions';        Ok = ((Test-Path 'C:\LabFiles\agent\instructions-baseline.md') -and
                                                     (Test-Path 'C:\LabFiles\agent\instructions-grounded.md')) },
        @{ Name = 'git';                       Ok = [bool](Get-Command git -ErrorAction SilentlyContinue) },
        @{ Name = 'azure cli';                 Ok = [bool](Get-Command az -ErrorAction SilentlyContinue) },
        @{ Name = 'powershell 7';              Ok = (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe') },
        @{ Name = 'vs code';                   Ok = (Test-Path $codeCli) },
        @{ Name = 'readiness shortcut';        Ok = (Test-Path (Join-Path $desktop 'Lab readiness check.lnk')) },
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
