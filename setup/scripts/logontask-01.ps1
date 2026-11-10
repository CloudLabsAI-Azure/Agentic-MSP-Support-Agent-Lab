<#
    logontask-01.ps1: first-logon script (stage 2 of 2) of the Agentic MSP Support Agent Guided Lab.

    Started by the 'Setup' scheduled task after psscript-01.ps1 restarts the VM and the VM
    administrator signs in once automatically. Windows PowerShell 5.1, the lab user's context. Takes
    no parameters and owns the FINAL deployment status that CloudLabs shows.

      1. Visual Studio Code: the Python and PowerShell extensions, terminals in PowerShell 7.
      2. Desktop: Lab readiness check, Service Desk, Microsoft Foundry, Azure Portal, Microsoft
         Purview, Microsoft Entra admin center, MCP server (VS Code), and Lab notes.txt with exactly
         the labels the lab guide uses (kept as it is when it already exists).
      3. C:\LabFiles\evidence, where participants export their evidence.
      4. The readiness check (Participant mode, the VM's identity) and the lab files checks decide
         Succeeded or Failed; the status message names the Golden Environment version and the
         consistency fingerprint, or what is not ready.
      5. Removes the autologon password and this task.
#>

$ErrorActionPreference = 'Stop'
$start = Get-Date
Start-Transcript -Path 'C:\WindowsAzure\Logs\CloudLabsLogOnTask.txt' -Append

function SetDeploymentStatus($s, $m) {
    (Get-Content 'C:\WindowsAzure\Logs\status-sample.txt') -replace 'ReplaceStatus', $s -replace 'ReplaceMessage', $m |
        Set-Content 'C:\WindowsAzure\Logs\validationstatus.txt'
}
function ConvertTo-StatusText([string]$Text) {
    $clean = (($Text -replace '[^\x20-\x7E]', ' ') -replace '["$\\]', ' ' -replace '\s{2,}', ' ').Trim()
    if ($clean.Length -gt 400) { $clean = $clean.Substring(0, 397) + '...' }
    return $clean
}

$labNotes = @'
Agentic MSP Support Agent Guided Lab: your notes
Keep this file open. The lab guide tells you what to record here.

== Exercise 1: Environment Readiness and Grounding the Agent ==
Readiness check and Golden Environment version:
Agent ID (client ID):
Baseline read tool: ticket and correlation ID:
Index document count:
First grounded answer: article cited:
Ambiguous case: articles, recommendation and deciding attribute:
Thin or unverifiable reasoning to revisit in Exercise 6:

== Exercise 2: Ticket and Incident Intelligence ==
TCK-10561: closest historical tickets, and why they are similar:
Customer history: customer, open tickets the agent counted, open tickets in the app:
TCK-10561: recommended priority, category and technician or team:
Incomplete ticket: what the agent asked for:
SLA risk: ticket closest to breach, and the working:

== Exercise 3: Using the MCP Read Tools ==
Tool you traced to its Dataverse query:
Permission each read tool needs (for Exercise 5):
Read tool call: ticket and correlation ID:
Error codes the agent received:
Redeploy: your change, the new revision, how long the cycle took, how to roll back:

== Exercise 4: Using the MCP Action Tools ==
Approved write: ticket, change and correlation ID (you trace it in Exercise 6):
Declined write: ticket, and confirmed unchanged:
Customer-visible reply and internal note: ticket and note codes:
Grounded action on TCK-10561: recommendation, sources and correlation ID:
get_open_tickets limit before and after, and the rejected call:
Your scoped tool: name, description, permission and approval:

== Exercise 5: Identity, Secrets and Authorization ==
Identities on one write: user, Agent ID, gateway, MCP managed identity, Dataverse application user:
Tokens: what each hop presents and its scope:
Backend credential: Key Vault secret name, and the access log entry at startup:
Boundary you narrowed, and the Dataverse error:
Tier 1 attempt (denied) and Senior attempt (allowed), with correlation IDs:

== Exercise 6: Data Protection and Auditability ==
What the agent could not return, and what it said:
Microsoft Purview: policy, sensitive information type, label and DLP event time:
End-to-end trail: correlation ID and each hop you found:

== Exercise 7: End-to-End Scenario and Business Case ==
TCK-10562: customer, recommendation, actions taken and correlation IDs:

== Business case ==
Problem today:
What the agent does (grounding and tools):
Controls (identity, least privilege, approval, data protection, audit):
Evidence from this lab:
Operational value for the MSP (time, consistency, SLA):
Risks and next steps:
'@

try {
    . 'C:\LabFiles\cloudlabs-windows-functions.ps1'
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:AZURE_EXTENSION_DIR = [Environment]::GetEnvironmentVariable('AZURE_EXTENSION_DIR', 'Machine')
    $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
    $settings = $null
    if (Test-Path 'C:\LabFiles\lab-settings.json') { $settings = Get-Content 'C:\LabFiles\lab-settings.json' -Raw | ConvertFrom-Json }

    # ==== 1. Visual Studio Code
    $codeCli = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
    if (-not (Test-Path $codeCli)) { $codeCli = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd" }
    $codeExe = Join-Path (Split-Path (Split-Path $codeCli -Parent) -Parent) 'Code.exe'
    foreach ($extension in 'ms-python.python', 'ms-vscode.powershell') {
        & $codeCli --install-extension $extension --force
        if ($LASTEXITCODE) { Start-Sleep -Seconds 10; & $codeCli --install-extension $extension --force }
    }
    $codeUser = Join-Path $env:APPDATA 'Code\User'
    New-Item -ItemType Directory -Path $codeUser -Force | Out-Null
    $codeSettings = Join-Path $codeUser 'settings.json'
    if (-not (Test-Path $codeSettings)) {
        @{
            'terminal.integrated.profiles.windows'       = @{ 'PowerShell 7' = @{ path = $pwsh } }
            'terminal.integrated.defaultProfile.windows' = 'PowerShell 7'
            'security.workspace.trust.untrustedFiles'    = 'open'
            'python.defaultInterpreterPath'              = 'C:\Program Files\Python312\python.exe'
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $codeSettings -Encoding UTF8
    }

    # ==== 2. Desktop
    $desktop = [Environment]::GetFolderPath('Desktop')
    $serviceDesk = if ($settings -and $settings.ServiceDeskAppUrl) { $settings.ServiceDeskAppUrl } else { 'https://make.powerapps.com' }
    $urls = [ordered]@{
        'Service Desk'                 = $serviceDesk
        'Microsoft Foundry'            = 'https://ai.azure.com'
        'Azure Portal'                 = 'https://portal.azure.com'
        'Microsoft Purview'            = 'https://purview.microsoft.com'
        'Microsoft Entra admin center' = 'https://entra.microsoft.com'
    }
    foreach ($name in $urls.Keys) { "[InternetShortcut]`r`nURL=$($urls[$name])" | Set-Content -Path (Join-Path $desktop "$name.url") -Encoding ASCII }
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut((Join-Path $desktop 'Lab readiness check.lnk'))
    $link.TargetPath = $pwsh
    $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -NoExit -File C:\LabFiles\tools\Test-LabReadiness.ps1'
    $link.WorkingDirectory = 'C:\LabFiles'
    $link.Description = 'Checks every component of your lab environment'
    $link.Save()
    $link = $shell.CreateShortcut((Join-Path $desktop 'MCP server (VS Code).lnk'))
    $link.TargetPath = $codeExe
    $link.Arguments = '"C:\LabFiles\mcp-server"'
    $link.WorkingDirectory = 'C:\LabFiles\mcp-server'
    $link.Description = 'Opens the MCP server source in Visual Studio Code'
    $link.Save()
    $notesPath = Join-Path $desktop 'Lab notes.txt'
    if (-not (Test-Path $notesPath)) { $labNotes -split "`r?`n" | Set-Content -Path $notesPath -Encoding ASCII }

    # ==== 3. Evidence folder (Get-ActionTrail.ps1 also creates it when missing)
    New-Item -ItemType Directory -Path 'C:\LabFiles\evidence' -Force | Out-Null

    # ==== 4. Validation: readiness check and lab files
    $problems = @()
    if (-not $settings) { $problems += 'lab-settings.json is missing (provisioning did not finish)' }
    $files = @(
        'tools\Test-LabReadiness.ps1', 'tools\Invoke-McpTool.ps1', 'tools\Show-McpServerLog.ps1', 'tools\Deploy-McpServer.ps1',
        'tools\Get-ActionTrail.ps1', 'tools\Get-DocumentLabel.ps1', 'tools\Get-AgentIdentity.ps1', 'tools\Update-AgentDefinition.ps1',
        'tools\New-KnowledgeIndex.ps1',
        'search\index-definition.json', 'search\servicedesk-export-ds.json', 'search\servicedesk-embed-skills.json',
        'search\servicedesk-export-indexer.json', 'search\export-manifest.json', 'search\sample-documents\kb-KB0058.json',
        'agent\instructions-baseline.md', 'agent\instructions-grounded.md', 'seed\data\manifest.json', 'solutions'
    )
    $missing = @($files | Where-Object { -not (Test-Path (Join-Path 'C:\LabFiles' $_)) })
    if ($missing.Count) { $problems += "missing lab files: $($missing -join ', ')" }
    foreach ($tool in @(@{ Name = 'Git'; Ok = [bool](Get-Command git -ErrorAction SilentlyContinue) },
                        @{ Name = 'Azure CLI'; Ok = [bool](Get-Command az -ErrorAction SilentlyContinue) },
                        @{ Name = 'PowerShell 7'; Ok = (Test-Path $pwsh) },
                        @{ Name = 'Visual Studio Code'; Ok = (Test-Path $codeExe) },
                        @{ Name = 'Python 3.12'; Ok = (Test-Path 'C:\Program Files\Python312\python.exe') -or [bool](Get-Command python -ErrorAction SilentlyContinue) })) {
        if (-not $tool.Ok) { $problems += "$($tool.Name) is not installed" }
    }
    $tags = @()
    if (Test-Path 'C:\LabFiles\mcp-server\.git') {
        $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $tags = @(& git -C 'C:\LabFiles\mcp-server' tag --list)
        $ErrorActionPreference = $previous
    }
    if (-not ($tags -match '^v3\.')) { $problems += 'the MCP server working copy C:\LabFiles\mcp-server has no v3 release tag' }

    $fingerprint = ''
    $golden = 'v1.0'
    if (Test-Path 'C:\LabFiles\tools\Test-LabReadiness.ps1') {
        $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $pwsh -NoProfile -ExecutionPolicy Bypass -File 'C:\LabFiles\tools\Test-LabReadiness.ps1' -Mode Participant | Out-Host
        $readinessExit = $LASTEXITCODE
        $ErrorActionPreference = $previous
        $reportPath = 'C:\LabFiles\readiness\consistency-report.json'
        if (Test-Path $reportPath) {
            $report = Get-Content $reportPath -Raw | ConvertFrom-Json
            $fingerprint = ([string]$report.fingerprint).Substring(0, [Math]::Min(12, ([string]$report.fingerprint).Length))
            $golden = [string]$report.goldenEnvironmentVersion
            $notReady = @($report.components | Where-Object { $_.Status -ne 'Ready' })
            foreach ($c in $notReady) { $problems += "$($c.Component) not ready: $($c.Detail)" }
        }
        elseif ($readinessExit) { $problems += 'the readiness check did not complete' }
    }

    if ($problems.Count) {
        $ValidStatus = 'Failed'
        $ValidMessage = ConvertTo-StatusText ("Golden Environment $golden not ready. " + ($problems -join '; '))
    }
    else {
        $ValidStatus = 'Succeeded'
        $ValidMessage = ConvertTo-StatusText "Golden Environment $golden ready (fingerprint $fingerprint). Every component is ready."
    }
}
catch {
    $ValidStatus = 'Failed'
    $ValidMessage = ConvertTo-StatusText ('Logon task failed: ' + $_.Exception.Message)
    Write-Warning $ValidMessage
}

try { SetDeploymentStatus $ValidStatus $ValidMessage } catch { Write-Warning "SetDeploymentStatus failed: $($_.Exception.Message)" }
Start-Sleep -Seconds 3
$Validstatus = $ValidStatus
$Validmessage = $ValidMessage
try { CloudlabsManualAgent setStatus } catch { Write-Warning "setStatus failed: $($_.Exception.Message)" }
try { CloudlabsManualAgent Start } catch { Write-Warning "agent Start failed: $($_.Exception.Message)" }

# ==== 5. Cleanup: no stored password, no second autologon, no second run
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Remove-ItemProperty $winlogon -Name DefaultPassword -ErrorAction SilentlyContinue
Set-ItemProperty $winlogon -Name AutoAdminLogon -Value '0' -Type String -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'Setup' -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Logon task completed in $([int]((Get-Date) - $start).TotalSeconds) s with status $ValidStatus"
Stop-Transcript
