Import-Module failoverclusters
function Test-PendingReboot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [pscredential]$Credential
    )
    
    $ErrorActionPreference = 'Stop'
    
    $scriptBlock = {
    
        $VerbosePreference = $using:VerbosePreference
        function Test-RegistryKey {
            [OutputType('bool')]
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Key
            )
        
            $ErrorActionPreference = 'Stop'
    
            if (Get-Item -Path $Key -ErrorAction Ignore) {
                $true
            }
        }
    
        function Test-RegistryValue {
            [OutputType('bool')]
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Key,
    
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Value
            )
        
            $ErrorActionPreference = 'Stop'
    
            if (Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) {
                $true
            }
        }
    
        function Test-RegistryValueNotNull {
            [OutputType('bool')]
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Key,
    
                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$Value
            )
        
            $ErrorActionPreference = 'Stop'
    
            if (($regVal = Get-ItemProperty -Path $Key -Name $Value -ErrorAction Ignore) -and $regVal.($Value)) {
                $true
            }
        }
    
        # Added "test-path" to each test that did not leverage a custom function from above since
        # an exception is thrown when Get-ItemProperty or Get-ChildItem are passed a nonexistant key path
        $tests = @(
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' }
            { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress' }
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' }
            { Test-RegistryKey -Key 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending' }
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\PostRebootReporting' }
            { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations' }
            { Test-RegistryValueNotNull -Key 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Value 'PendingFileRenameOperations2' }
            { 
                # Added test to check first if key exists, using "ErrorAction ignore" will incorrectly return $true
                'HKLM:\SOFTWARE\Microsoft\Updates' | Where-Object { test-path $_ -PathType Container } | ForEach-Object {            
                    (Get-ItemProperty -Path $_ -Name 'UpdateExeVolatile' | Select-Object -ExpandProperty UpdateExeVolatile) -ne 0 
                }
            }
            { Test-RegistryValue -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' -Value 'DVDRebootSignal' }
            { Test-RegistryKey -Key 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttemps' }
            { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'JoinDomain' }
            { Test-RegistryValue -Key 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon' -Value 'AvoidSpnSet' }
            {
                # Added test to check first if keys exists, if not each group will return $Null
                # May need to evaluate what it means if one or both of these keys do not exist
                ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' | Where-Object { test-path $_ } | %{ (Get-ItemProperty -Path $_ ).ComputerName } ) -ne 
                ( 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' | Where-Object { Test-Path $_ } | %{ (Get-ItemProperty -Path $_ ).ComputerName } )
            }
            {
                # Added test to check first if key exists
                'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending' | Where-Object { 
                    (Test-Path $_) -and (Get-ChildItem -Path $_) } | ForEach-Object { $true }
            }
        )
    
        foreach ($test in $tests) {
            Write-Verbose "Running scriptblock: [$($test.ToString())]"
            if (& $test) {
                $true
                break
            }
        }
    }
    
    foreach ($computer in $ComputerName) {
        try {
            $connParams = @{
                'ComputerName' = $computer
            }
            if ($PSBoundParameters.ContainsKey('Credential')) {
                $connParams.Credential = $Credential
            }
    
            $output = @{
                ComputerName    = $computer
                IsPendingReboot = $false
            }
    
            $psRemotingSession = New-PSSession @connParams
            
            if (-not ($output.IsPendingReboot = Invoke-Command -Session $psRemotingSession -ScriptBlock $scriptBlock)) {
                $output.IsPendingReboot = $false
            }
            [pscustomobject]$output
        } catch {
            Write-Error -Message $_.Exception.Message
        } finally {
            if (Get-Variable -Name 'psRemotingSession' -ErrorAction Ignore) {
                $psRemotingSession | Remove-PSSession
            }
        }
    }
}
function Reboot-FileClusterNode {
    param (
        $Node
    )
    Write-Host "Virtual Disks and Storage Spaces are healthy on $($Node.Cluster)" -ForegroundColor Green

    Write-Host "Suspending $($Node.Name) on $($Node.Cluster) at $(Get-Date)"
    Suspend-ClusterNode -Cluster $Node.Cluster -Name $Node.Name -Drain
    do {
        Start-Sleep 5
    } until ($Node.State -eq "Paused")
    try {
        Write-Host "Restarting $Node at $(Get-date)"
        Restart-Computer -ComputerName $Node.Name -Wait -For PowerShell -Force
    }
    catch {
        Write-Host "Unable to restart $Node"
        break
    }
    Start-Sleep 10
    Write-Host "Reboot of $Node Complete, waiting to join Cluster"
    do {
        Start-Sleep 5
    } until ((Get-ClusterNode -Cluster $Node.Cluster -Name $Node.Name).State -ne "Down")
    Write-Host "$Node has now re-joined the cluster, attempting to resume $Node"
    try {
        Write-Host "Resuming $Node at $(Get-Date) $($Node.Cluster)"
        Resume-ClusterNode -Cluster $Node.Cluster -Name $Node.Name
    }
    catch {
        Write-Host "Unable to resume $Node"
        break
    }
}
#region FileCluster Reboot
#Selects only nodes that have File Server role on them, assuming they are Storage Spaces direct File Server Cluster
[System.Collections.ArrayList]$NodeList = (Get-Cluster -Domain $env:USERDOMAIN | Get-ClusterResource | Where-Object {$_.Name -like "File Server*"}).Cluster | Get-ClusterNode

foreach ($node in $NodeList) {
    $result = Test-PendingReboot $node.Name
    if ($result.IsPendingReboot -eq $true) {
        if (!(Invoke-Command -ComputerName $Node.Name -ScriptBlock {Get-VirtualDisk | Where-Object {$_.HealthStatus -ne "Healthy" -or $_.OperationalStatus -ne "OK"}})) {
            Reboot-FileClusterNode -Node $Node
        }
        elseif ([Bool](Invoke-Command -ComputerName $Node.Name -ScriptBlock {Get-StorageJob | Where-Object {$_.JobState -eq "Running" -or $_.JobState -eq "Suspended"}})) {
            Write-Host "StorageJob is running"
            do {
                Write-Host "Pausing for 30 seconds to all storage job to complete`nStart Time: $(Get-Date)"
                Start-Sleep 30
                $StorJob = (Invoke-Command -ComputerName $Node.Name -ScriptBlock {Get-StorageJob | Where-Object {$_.JobState -eq "Running" -or $_.JobState -eq "Suspended"}})
                if (($StorJob.Count -gt 0) -and (($StorJob | Where-Object {$_.JobState -ne "Suspended"}).Count -eq 0)) {
                    $i++
                    if ($i -eq 4) {
                        Write-Host "Storage Jobs appear to be hung all at suspended, attempting to optimize storage pool to resolve"
                        Invoke-Command -ComputerName $Node.Name -ScriptBlock {Get-StoragePool | Where-Object {$_.IsPrimordial -eq $false} | Optimize-StoragePool}
                    }
                }
            } until ($StorJob.Count -eq 0)
            Reboot-FileClusterNode -Node $Node.Name
        }
        else {
            Write-Host "Storage Nodes not healthy, and no storage repairs running"
            break
        }
    }
    else {
        Write-Host "$($Node.name) did not have pending reboot moving to next node" -ForegroundColor Gray
    }
}
#regionend