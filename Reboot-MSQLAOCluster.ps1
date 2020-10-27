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
#Selecting other nodes that are NOT File Server Clusters
[System.Collections.ArrayList]$NodeList = ($Clusters | Get-ClusterResource | Where-Object {$_.Name -notlike "File Server*"}).Cluster | Get-ClusterNode
Do {
    Invoke-Command -ComputerName $NodeList[0].Name -ScriptBlock {Suspend-ClusterNode}
    do {
        Get-ClusterNode $NodeList[0].Name
        Start-Sleep 2
    } until ($NodeList[0].State -eq "Paused")
    Restart-Computer -ComputerName $NodeList[0].Name -Force -Wait -For PowerShell -Timeout 300 -Delay 2
    Invoke-Command -ComputerName $NodeList[0].Name -ScriptBlock {Resume-ClusterNode -Failback Immediate}
    do {
        Start-Sleep 2
    } until ($NodeList[0].State -eq "Up")
    else {
        break
    }
    $NodeList.Remove($NodeList[0])
} until ($Nodelist.count -eq 0)
#regionend