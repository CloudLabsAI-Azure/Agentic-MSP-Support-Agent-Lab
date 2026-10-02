<#
    psscript-01.ps1 - bootstrap entry script (stage 1 of 2) for the Agentic MSP Support Agent lab.
    Delivered by userData on the Spektra cloudlabs-windows-jumpvm image: the baked 'runuserdata'
    task runs it as SYSTEM at first boot with cwd C:\CloudLabs.

    Stage 1 does machine-level work and then finishes the team environment
    (Provision-ServiceDesk.ps1): Power Platform developer environment, Service Desk schema and
    app, application user, seed data, MCP server image, Foundry agent and gateway identity.
    Azure Resource Manager changes run as the VM's provisioning managed identity, so Azure's
    mandatory MFA for Resource Manager writes does not block them; Power Platform and Dataverse
    calls run as the TEAM USER, who owns the developer environment.
    Stage 2 (logontask-01.ps1) runs after one autologon and reports the final status.

    Argument names below MUST match the arg1LabVM..arg6LabVM concat in deploy-01.json exactly;
    -ProvisioningIdentityClientId is appended by the VM userData expression in deploy-01.json.
#>
Param (
    [Parameter(Mandatory = $true)]
    [string]$AzureUserName,
    [string]$AzurePassword,
    [string]$AzureTenantID,
    [string]$AzureSubscriptionID,
    [string]$ODLID,
    [string]$DeploymentID,
    [string]$vmAdminUsername,
    [string]$vmAdminPassword,
    [string]$trainerUserName,
    [string]$trainerUserPassword,
    [string]$ResourceGroupName,
    [string]$McpGatewayAppId,
    [string]$ProvisioningIdentityClientId
)

$ErrorActionPreference = 'Stop'

New-Item -ItemType Directory -Path 'C:\WindowsAzure\Logs' -Force | Out-Null
Start-Transcript -Path 'C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt' -Append

$PSBoundParameters.GetEnumerator() | Where-Object { $_.Key -notmatch 'Password' } |
    Sort-Object Key | Format-Table -AutoSize

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$projectBlob = 'https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent'

try {
    <# ---- Shared CloudLabs library: baked copy first, then CSE layouts, then the blob. #>
    $path = (Get-Location).Path
    $commonCandidates = @(
        'C:\CloudLabs\cloudlabs-common\cloudlabs-windows-functions.ps1',
        (Join-Path $path 'cloudlabs-common\cloudlabs-windows-functions.ps1'),
        (Join-Path $path 'cloudlabs-windows-functions.ps1')
    )
    $common = $commonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $common) {
        New-Item -ItemType Directory -Path 'C:\LabFiles' -Force | Out-Null
        $common = 'C:\LabFiles\cloudlabs-windows-functions.ps1'
        Invoke-WebRequest -Uri 'https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/cloudlabs-windows-functions.ps1' `
                          -OutFile $common -UseBasicParsing
    }
    if (-not (Test-Path $common)) { throw "cloudlabs-windows-functions.ps1 not found (probed: $($commonCandidates -join '; ') + blob fallback)" }
    . $common

    <# ---- Mandatory CloudLabs sequence, in this order. #>
    WindowsServerCommon
    CloudLabsManualAgent Install
    CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID
    Enable-CloudLabsEmbeddedShadow $vmAdminUsername $trainerUserName $trainerUserPassword
    InstallModernVmValidator

    New-Item -ItemType Directory -Path 'C:\LabFiles' -Force | Out-Null
    if ($common -ne 'C:\LabFiles\cloudlabs-windows-functions.ps1') {
        Copy-Item $common 'C:\LabFiles\cloudlabs-windows-functions.ps1' -Force
    }

    <# ---- Machine-scope state for the logon task and for the participants' own sessions. #>
    [Environment]::SetEnvironmentVariable('DeploymentID', $DeploymentID, 'Machine')
    [Environment]::SetEnvironmentVariable('AzureSubscriptionID', $AzureSubscriptionID, 'Machine')
    [Environment]::SetEnvironmentVariable('LabResourceGroup', $ResourceGroupName, 'Machine')
    # One Azure CLI extension folder for SYSTEM (provisioning) and the lab user (exercises).
    New-Item -ItemType Directory -Path 'C:\LabFiles\azext' -Force | Out-Null
    [Environment]::SetEnvironmentVariable('AZURE_EXTENSION_DIR', 'C:\LabFiles\azext', 'Machine')
    $env:AZURE_EXTENSION_DIR = 'C:\LabFiles\azext'

    <# ---- Lab tooling. Install-ChocoPackage only; check every result. #>
    if (-not (Install-ChocoPackage -PackageName 'git')) { throw 'git install failed' }
    if (-not (Install-ChocoPackage -PackageName 'vscode')) { throw 'vscode install failed' }
    if (-not (Install-ChocoPackage -PackageName 'python' -AdditionalArgs '--version=3.12.10 --allow-downgrade')) { throw 'python install failed' }
    if (-not (Install-ChocoPackage -PackageName 'powershell-core')) { throw 'PowerShell 7 install failed' }
    InstallAzCLI

    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')

    az extension add --name containerapp --upgrade --yes --only-show-errors
    if ($LASTEXITCODE) { throw 'az extension add containerapp failed' }

    <# ---- Lab files: provisioning scripts, seed generator, search tooling. #>
    $zipPath = 'C:\LabFiles\msp-labfiles.zip'
    Invoke-WebRequest -Uri "$projectBlob/assets/msp-labfiles.zip" -OutFile $zipPath -UseBasicParsing
    $tmp = 'C:\LabFiles\__extract_tmp'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
    $items = Get-ChildItem $tmp
    if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
        Get-ChildItem -LiteralPath $items[0].FullName -Force | Copy-Item -Destination 'C:\LabFiles' -Recurse -Force
    } else {
        $items | Copy-Item -Destination 'C:\LabFiles' -Recurse -Force
    }
    Remove-Item $tmp, $zipPath -Recurse -Force -ErrorAction SilentlyContinue

    <# ---- Finish the team environment (PowerShell 7). Resource Manager work runs as the VM's
         provisioning identity; Power Platform and Dataverse work runs as the team user, whose
         password travels in a process-scoped environment variable, never on a command line or
         in a file. #>
    $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
    if (-not (Test-Path $pwsh)) { throw 'PowerShell 7 not found after install' }
    if (-not $ProvisioningIdentityClientId) { throw 'ProvisioningIdentityClientId was not passed by the VM userData' }
    $env:MSPLAB_SIGNIN_SECRET = $AzurePassword
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File 'C:\LabFiles\provision\Provision-ServiceDesk.ps1' `
        -DeploymentID $DeploymentID -ResourceGroupName $ResourceGroupName -AzureUserName $AzureUserName `
        -AzureTenantID $AzureTenantID -AzureSubscriptionID $AzureSubscriptionID -McpGatewayAppId $McpGatewayAppId `
        -ProvisioningIdentityClientId $ProvisioningIdentityClientId
    $provisionExit = $LASTEXITCODE
    Remove-Item Env:\MSPLAB_SIGNIN_SECRET -ErrorAction SilentlyContinue
    if ($provisionExit) { throw "Provision-ServiceDesk.ps1 failed ($provisionExit); see C:\WindowsAzure\Logs\MspProvisioning.txt" }

    <# ---- Stage the logon task and a one-shot autologon (user-context work and final status). #>
    Invoke-WebRequest -Uri "$projectBlob/scripts/logontask-01.ps1" -OutFile 'C:\LabFiles\logontask-01.ps1' -UseBasicParsing

    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty $winlogon -Name AutoAdminLogon  -Value '1' -Type String
    Set-ItemProperty $winlogon -Name DefaultUsername -Value "$env:ComputerName\$vmAdminUsername" -Type String
    Set-ItemProperty $winlogon -Name DefaultPassword -Value $vmAdminPassword -Type String
    Set-ItemProperty $winlogon -Name AutoLogonCount  -Value 1 -Type DWord

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $action  = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
               -Argument '-ExecutionPolicy Unrestricted -WindowStyle Hidden -File C:\LabFiles\logontask-01.ps1'
    Register-ScheduledTask -TaskName 'Setup' -Trigger $trigger -Action $action `
        -User "$env:ComputerName\$vmAdminUsername" -RunLevel Highest -Force

    if (-not (Get-ChocoInstallReport)) { throw 'One or more package installs failed - see C:\WindowsAzure\Logs\cloudlabscommoninstaller.txt' }

    $Validstatus  = 'Pending'
    $Validmessage = 'Post Deployment is Pending'
    CloudLabsManualAgent setStatus
}
catch {
    $Validstatus  = 'Failed'
    $Validmessage = $_.Exception.Message
    try { CloudLabsManualAgent setStatus } catch {}
    Write-Error $_.Exception.Message
    throw
}
finally {
    Stop-Transcript
}

if (Get-ScheduledTask -TaskName 'runuserdata' -ErrorAction SilentlyContinue) {
    Disable-ScheduledTask -TaskName 'runuserdata'
}

Restart-Computer -Force
