Import-Module failoverclusters
function Test-PendingReboot {
    param (
        $Server
    )
        $pendingRebootTests = @(
        @{
            Name = 'RebootPending'
            Test = { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'  -Name 'RebootPending' -ErrorAction Ignore }
            TestType = 'ValueExists'
        }
        @{
            Name = 'RebootRequired'
            Test = { Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'  -Name 'RebootRequired' -ErrorAction Ignore }
            TestType = 'ValueExists'
        }
        @{
            Name = 'PendingFileRenameOperations'
            Test = { Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Ignore }
            TestType = 'NonNullValue'
        }
    )
    $Reboot = foreach ($test in $pendingRebootTests) {
        $result = Invoke-Command -Computername $Server -ScriptBlock $test.Test
        if ($test.TestType -eq 'ValueExists' -and $result) {
            $true
        } elseif ($test.TestType -eq 'NonNullValue' -and $result -and $result.($test.Name)) {
            $true
        } else {
            $false
        }
    }
    [bool]$Reboot
}
function Reboot-FileClusterNode {
    param (
        $NodeList
    )
    Write-Host "Virtual Disks and Storage Spaces are healthy on $($Nodelist.Cluster)" -ForegroundColor Green

    Write-Host "Suspending $($Nodelist.Name) on $($NodeList.Cluster) at $(Get-Date)"
    Suspend-ClusterNode -Cluster $NodeList.Cluster -Name $NodeList.Name -Drain
    try {
        Write-Host "Restarting $Nodelist at $(Get-date)"
        Restart-Computer -ComputerName $NodeList.Name -Wait -For PowerShell -Force
    }
    catch {
        Write-Host "Unable to restart $Nodelist"
        break
    }
    Write-Host "Reboot of $NodeList Complete, attempting to resume"
    try {
        Write-Host "Resuming $Nodelist at $(Get-Date) $($NodeList.Cluster)"
        Resume-ClusterNode -Cluster $NodeList.Cluster -Name $NodeList.Name
    }
    catch {
        Write-Host "Unable to resume $Nodelist"
        break
    }
}
#region FileCluster Reboot
#Selects only nodes that have File Server role on them, assuming they are Storage Spaces direct File Server Cluster
[System.Collections.ArrayList]$NodeList = (Get-Cluster -Domain $env:USERDOMAIN | Get-ClusterResource | Where-Object {$_.Name -like "File Server*"}).Cluster | Get-ClusterNode
Do {
    if (!(Invoke-Command -ComputerName $NodeList[0].Name -ScriptBlock {Get-VirtualDisk | Where-Object {$_.HealthStatus -ne "Healthy" -or $_.OperationalStatus -ne "OK"}})) {
        Reboot-FileClusterNode -NodeList $NodeList[0]
    }
    elseif ([Bool](Invoke-Command -ComputerName $NodeList[0].Name -ScriptBlock {Get-StorageJob | Where-Object {$_.JobState -eq "Running" -or $_.JobState -eq "Suspended"}})) {
        Write-Host "StorageJob is running"
        do {
            Write-Host "Pausing for 30 seconds to all storage job to complete`nStart Time: $(Get-Date)"
            Start-Sleep 30
            $StorJob = (Invoke-Command -ComputerName $NodeList[0].Name -ScriptBlock {Get-StorageJob | Where-Object {$_.JobState -eq "Running" -or $_.JobState -eq "Suspended"}})
            if (($StorJob.Count -gt 0) -and (($StorJob | Where-Object {$_.JobState -ne "Suspended"}).Count -eq 0)) {
                Write-Host "Storage Jobs appear to be hung all at suspended, attempting to optimize storage pool to resolve"
                Get-StoragePool | Where-Object {$_.IsPrimordial -eq $false} | Optimize-StoragePool
            }
        } until ($StorJob.Count -eq 0)
        Reboot-FileClusterNode -NodeList $NodeList[0]
    }
    else {
        Write-Host "Storage Nodes not healthy, and no storage repairs running"
        break
    }
    $NodeList.Remove($NodeList[0])
} until ($Nodelist.count -eq 0)
#regionend