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