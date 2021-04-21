 <#
    Script : SyncLoginsToReplica.ps1
    Author : Andreas Schubert (http://www.linkedin.com/in/schubertandreas)
    Purpose: Sync logins between all replicas in an Availability Group automatically.
    --------------------------------------------------------------------------------------------
    The script will connect to the listener name of the Availability Group
    and read all replica instances to determine the current primary replica and all secondaries.
    It will then connect directly to the current primary, query all Logins and create them on each
    secondary.
    
    Attention:
    The script is provided so that no action is actually executed against the secondaries (switch -WhatIf).
    Change that line according to your logic, you might want to exclude other logins or decide to not drop
        any existing ones.
    --------------------------------------------------------------------------------------------
    Usage: Save the script in your file system, change the name of the AG Listener (AGListenerName in this template) 
           and schedule it to run at your prefered schedule. I usually sync logins once per hour, although 
           on more volatile environments it may run as often as every minute
#>
import-module dbatools
# define the AG name
    $AvailabilityGroupName = 'ITDataLSN.ds.tssn.services,1435'

# internal variables
    $ClientName = 'AG Login Sync helper'
    $primaryInstance = $null
    $secondaryInstances = @{}


try {
    # connect to the AG listener, get the name of the primary and all secondaries
        $replicas = Get-DbaAgReplica -SqlInstance $AvailabilityGroupName 
        $primaryInstance = $replicas | Where-Object Role -eq Primary | Select-Object -ExpandProperty name
        $secondaryInstances = $replicas | Where-Object Role -ne Primary | Select-Object -ExpandProperty name
    # create a connection object to the primary
        $primaryInstanceConnection = Connect-DbaInstance $primaryInstance -ClientName $ClientName
    # loop through each secondary replica and sync the logins
        $secondaryInstances | ForEach-Object {
            $secondaryInstanceConnection = Connect-DbaInstance $_ -ClientName $ClientName
            Copy-DbaLogin -Source $primaryInstanceConnection -Destination $secondaryInstanceConnection -ExcludeSystemLogins
        }
}
catch {
    $msg = $_.Exception.Message
    Write-Error "Error while syncing logins for Availability Group '$($AvailabilityGroupName): $msg'"
} 
