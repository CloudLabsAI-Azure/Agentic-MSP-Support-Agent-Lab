<#
    psscript-01.ps1: bootstrap entry script (stage 1 of 2) of the Agentic MSP Support Agent Guided Lab.

    Delivered by the VM userData of setup/deploy-01.json on the Spektra cloudlabs-windows-jumpvm
    image: the baked 'runuserdata' task runs it as SYSTEM at first boot, in Windows PowerShell 5.1.

    Stage 1:
      1. The mandatory CloudLabs sequence (common functions, manual agent, credential file, shadow
         session, VM validator).
      2. Lab tooling: Git, Visual Studio Code, Python 3.12, PowerShell 7, Azure CLI with the
         containerapp extension, and the ExchangeOnlineManagement module for PowerShell 7.
      3. The lab files archive (msp-labfiles.zip) into C:\LabFiles.
      4. Provision-ServiceDesk.ps1 in PowerShell 7: the tenant and environment configuration, which
         reports every step in C:\LabFiles\provision-status.json and ends by removing the lab user's
         Global Administrator role. The lab user's password reaches it in a process environment
         variable (MSPLAB_SIGNIN_SECRET), never on a command line or in a file, and is removed after.
      5. The logon task and one autologon of the VM administrator, then a restart. Stage 2
         (logontask-01.ps1) prepares the desktop, runs the readiness check and reports the final
         Succeeded or Failed status to CloudLabs. A provisioning failure does not stop stage 2: the
         readiness check reports it, so CloudLabs sees Failed with the reason.

    The argument names match the userData expression in setup/bicep/main.bicep exactly (the ten
    CloudLabs arguments plus -ProvisioningIdentityClientId, the client ID of id-prov).
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
    [string]$ProvisioningIdentityClientId
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path 'C:\WindowsAzure\Logs' -Force | Out-Null
Start-Transcript -Path 'C:\WindowsAzure\Logs\CloudLabsCustomScriptExtension.txt' -Append

$PSBoundParameters.GetEnumerator() | Where-Object { $_.Key -notmatch 'Password' } | Sort-Object Key | Format-Table -AutoSize
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$projectBlob = 'https://experienceazure.blob.core.windows.net/templates/agentic-msp-support-agent'
$pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'

try {
    # ==== CloudLabs common functions: the baked copy first, then the blob
    $path = (Get-Location).Path
    $candidates = @('C:\CloudLabs\cloudlabs-common\cloudlabs-windows-functions.ps1',
                    (Join-Path $path 'cloudlabs-common\cloudlabs-windows-functions.ps1'),
                    (Join-Path $path 'cloudlabs-windows-functions.ps1'))
    $common = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    New-Item -ItemType Directory -Path 'C:\LabFiles' -Force | Out-Null
    if (-not $common) {
        $common = 'C:\LabFiles\cloudlabs-windows-functions.ps1'
        Invoke-WebRequest -Uri 'https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/cloudlabs-windows-functions.ps1' -OutFile $common -UseBasicParsing
    }
    . $common

    # ==== Mandatory CloudLabs sequence, in this order
    WindowsServerCommon
    CloudLabsManualAgent Install
    CreateCredFile $AzureUserName $AzurePassword $AzureTenantID $AzureSubscriptionID $DeploymentID
    Enable-CloudLabsEmbeddedShadow $vmAdminUsername $trainerUserName $trainerUserPassword
    InstallModernVmValidator
    if ($common -ne 'C:\LabFiles\cloudlabs-windows-functions.ps1') { Copy-Item $common 'C:\LabFiles\cloudlabs-windows-functions.ps1' -Force }

    # ==== Machine settings shared by provisioning (SYSTEM) and the lab user
    [Environment]::SetEnvironmentVariable('DeploymentID', $DeploymentID, 'Machine')
    New-Item -ItemType Directory -Path 'C:\LabFiles\azext' -Force | Out-Null
    [Environment]::SetEnvironmentVariable('AZURE_EXTENSION_DIR', 'C:\LabFiles\azext', 'Machine')
    $env:AZURE_EXTENSION_DIR = 'C:\LabFiles\azext'

    # ==== Lab tooling (Install-ChocoPackage; every result checked)
    if (-not (Install-ChocoPackage -PackageName 'git')) { throw 'Git install failed' }
    if (-not (Install-ChocoPackage -PackageName 'vscode')) { throw 'Visual Studio Code install failed' }
    if (-not (Install-ChocoPackage -PackageName 'python' -AdditionalArgs '--version=3.12.10 --allow-downgrade')) { throw 'Python 3.12 install failed' }
    if (-not (Install-ChocoPackage -PackageName 'powershell-core')) { throw 'PowerShell 7 install failed' }
    InstallAzCLI
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Test-Path $pwsh)) { throw 'PowerShell 7 is not installed' }

    & az extension add --name containerapp --upgrade --yes --only-show-errors
    if ($LASTEXITCODE) { throw 'az extension add containerapp failed' }
    & $pwsh -NoProfile -NonInteractive -Command ("Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; " +
        "Install-Module -Name ExchangeOnlineManagement -RequiredVersion 3.9.2 -Scope AllUsers -Force -AllowClobber -ErrorAction Stop")
    if ($LASTEXITCODE) { throw 'ExchangeOnlineManagement 3.9.2 install failed' }

    # ==== Lab files
    $zipPath = 'C:\LabFiles\msp-labfiles.zip'
    Invoke-WebRequest -Uri "$projectBlob/assets/msp-labfiles.zip" -OutFile $zipPath -UseBasicParsing
    $tmp = 'C:\LabFiles\__extract'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $tmp -Force
    $items = @(Get-ChildItem $tmp)
    $source = if ($items.Count -eq 1 -and $items[0].PSIsContainer) { $items[0].FullName } else { $tmp }
    Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination 'C:\LabFiles' -Recurse -Force
    Remove-Item $tmp, $zipPath -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path 'C:\LabFiles\provision\Provision-ServiceDesk.ps1')) { throw 'The lab files archive has no provision\Provision-ServiceDesk.ps1' }
    if (-not $ProvisioningIdentityClientId) { throw 'ProvisioningIdentityClientId was not passed by the VM userData' }

    # ==== Provisioning (PowerShell 7). Its result is reported by the logon task's readiness check.
    $env:MSPLAB_SIGNIN_SECRET = $AzurePassword
    try {
        & $pwsh -NoProfile -ExecutionPolicy Bypass -File 'C:\LabFiles\provision\Provision-ServiceDesk.ps1' `
            -DeploymentID $DeploymentID -AzureUserName $AzureUserName -AzureTenantID $AzureTenantID `
            -AzureSubscriptionID $AzureSubscriptionID -ProvisioningIdentityClientId $ProvisioningIdentityClientId
        $provisionExit = $LASTEXITCODE
    }
    finally { Remove-Item Env:\MSPLAB_SIGNIN_SECRET -ErrorAction SilentlyContinue }
    Write-Output "Provision-ServiceDesk.ps1 exit code: $provisionExit (details: C:\LabFiles\provision-status.json and C:\WindowsAzure\Logs\MspProvisioning.txt)"
    # The provisioning identity's Azure CLI profile is not needed after provisioning.
    Remove-Item 'C:\LabFiles\.azure-provisioning' -Recurse -Force -ErrorAction SilentlyContinue

    # ==== The lab user can edit the MCP server working copy and write reports and evidence
    foreach ($folder in 'C:\LabFiles\mcp-server', 'C:\LabFiles\readiness', 'C:\LabFiles\evidence', 'C:\LabFiles\search', 'C:\LabFiles\tools') {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        & icacls.exe $folder /grant "$($vmAdminUsername):(OI)(CI)M" /T /Q | Out-Null
    }
    if (Test-Path 'C:\LabFiles\lab-settings.json') { & icacls.exe 'C:\LabFiles\lab-settings.json' /grant "$($vmAdminUsername):R" /Q | Out-Null }

    # ==== Stage 2: logon task and one autologon
    Invoke-WebRequest -Uri "$projectBlob/scripts/logontask-01.ps1" -OutFile 'C:\LabFiles\logontask-01.ps1' -UseBasicParsing
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty $winlogon -Name AutoAdminLogon -Value '1' -Type String
    Set-ItemProperty $winlogon -Name DefaultUsername -Value "$env:ComputerName\$vmAdminUsername" -Type String
    Set-ItemProperty $winlogon -Name DefaultPassword -Value $vmAdminPassword -Type String
    Set-ItemProperty $winlogon -Name AutoLogonCount -Value 1 -Type DWord
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -Argument '-ExecutionPolicy Unrestricted -WindowStyle Hidden -File C:\LabFiles\logontask-01.ps1'
    Register-ScheduledTask -TaskName 'Setup' -Trigger $trigger -Action $action -User "$env:ComputerName\$vmAdminUsername" -RunLevel Highest -Force | Out-Null

    if (-not (Get-ChocoInstallReport)) { throw 'One or more package installs failed: see C:\WindowsAzure\Logs\cloudlabscommoninstaller.txt' }
    $Validstatus = 'Pending'
    $Validmessage = 'Post Deployment is Pending'
    CloudLabsManualAgent setStatus
}
catch {
    $Validstatus = 'Failed'
    $Validmessage = "Lab VM bootstrap failed: $($_.Exception.Message)"
    try { CloudLabsManualAgent setStatus } catch { }
    Write-Error $_.Exception.Message
    throw
}
finally {
    Stop-Transcript
}

if (Get-ScheduledTask -TaskName 'runuserdata' -ErrorAction SilentlyContinue) { Disable-ScheduledTask -TaskName 'runuserdata' | Out-Null }
Restart-Computer -Force
