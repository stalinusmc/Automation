$mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
$WID = ($mma.getcloudworkspaces() | Select WorkspaceId).workspaceid
$mma.RemoveCloudWorkspace($workspaceId)

stop-service healthservice

Get-Item HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker\* | Remove-Item -Recurse

gci 'C:\Program Files\Microsoft Monitoring Agent\Agent\Health Service State\' | Remove-Item -Recurse

Write-Host "Go to the Azure Portal and open the Automation Account`n
Under System Hybrid Worker groups, find the virtual machine you having issues with`n
Delete that System Hybrid worker group"
pause

Start-Service healthservice

$workspaceId = Read-Host "Enter Workspace ID"
$workspaceKey = Read-Host "Enter Workspace Key"
$mma = New-Object -ComObject 'AgentConfigManager.MgmtSvcCfg'
$mma.AddCloudWorkspace($workspaceId, $workspaceKey)
$mma.ReloadConfiguration()

