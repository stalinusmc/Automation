function Decom-Server {
[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
        [alias("decomserver")]
		[string[]]$ServerList,
        # Parameter asking if would like to cleanup DNS (primarily used to exclude, as it is default enabled)
        [Parameter(Mandatory=$false)]
        [bool]
        $DNSCleanup = $true,
        # Parameter asking if would like to cleanup DHCP (primarily used to exclude, as it is default enabled)
        [Parameter(Mandatory=$false)]
        [bool]
        $DHCPCleanup = $true,
        # Parameter asking if would like to cleanup DHCP (primarily used to exclude, as it is default enabled)
        [Parameter(Mandatory=$false)]
        [bool]
        $VMwareCleanup = $true,
        # Parameter asking if would like to cleanup DHCP (primarily used to exclude, as it is default enabled)
        [Parameter(Mandatory=$false)]
        [bool]
        $AzureCleanup = $true,
        # Parameter asking if would like to cleanup Active Directory (primarily used to exclude, as it is default enabled)
        [Parameter(Mandatory=$false)]
        [bool]
        $ADCleanup = $true,
        # Parameter Asking if you would like to cleanup Microsoft Endpoint configuration Manager (formerly SCCM)
        [Parameter(Mandatory=$false)]
        [bool]
        $MECMCleanup = $true
	)
#Below are the variables
foreach ($decomserver in $Serverlist) {
#Starts by clearing errors and Parameters to ensure carryover errors do not affect runtime
$ErrorActionPreference = 'Stop'
$error.clear()
$title = "Decom of $decomserver"
$vcserver = "vcenter.tssn.services"
$MECMServer = "TSSN-MECM-P01.ds.tssn.services"
$color = '15105570'
$time = Get-date -Date (Get-Date).ToUniversalTime()  -Format yyyy-MM-ddTHH:mm:ss.fffZ
$DHCPServer = "TSSN-DHCP.ds.tssn.services"
$totalDNS = @()
$VM = $null
$DNSObjectExist = $null
$DHCPObjectExist = $null
$ADObjectExist = $null
$AzureObjectExist = $null
$ADObject = $null
$DHCPObject = $null
$description = $null
$MECMObject = $null

$webHookUrl = "https://discord.com/api/webhooks/811280996723982396/mOwQD-Z0sof8n9FbFuUIXqvZf8DqYg47JRIbxJM1tfAqIIDr_wrusknx0UzbNJLYqvHG"
#region Collect Objects to be cleaned up
Import-Module VMware.VimAutomation.Core
# Connect to vCenter server.
if (($global:DefaultVIServer.Name -ne $vcserver) -or ($global:DefaultVIServer.IsConnected -ne $true)) {
    Connect-VIServer $vcserver
}
else {
    Write-Verbose "$vcserver is already connected"
}
try {
    Write-Host "Finding VM $decomserver"
    $VM = Get-VM -Name $decomserver
    Write-Verbose "Get-VM Completed"
}
catch {
    if ($_.Exception.Message.ToLower().Contains('was not found')) {
        Write-Host "VM $decomserver not found under that name" -ForegroundColor Yellow
        $VMObjectExist = $false
    }
}
Write-Verbose "$VM Exists $([bool]$VM)"

if ([bool]$VM) {
    $VMObjectExist = $true
    if (($VM.Guest.ExtensionData.GuestFamily -eq 'linuxGuest') -or ($VM.ExtensionData.Guest.GuestFullName -like "*Linux*")) {
        Write-Verbose "$($VM.name) is a linux VM"
        if (Get-ADComputer -Filter {Name -eq "$($VM.name)"}) {
            $ADObjectExist = $true
            Write-Verbose "Linux $VM found in Active Directory"
        }
    }
    elseif ($VM.Guest.ExtensionData.GuestFamily -eq 'windowsGuest') {
        Write-Verbose "$($VM.Name) is a Windows VM"
        if (Get-ADComputer -Filter {Name -eq "$($VM.name)"}) {
            $ADObject = Get-ADComputer -Properties ipv4Address, ipv6Address -Filter {Name -eq "$($VM.name)"}
            Write-Verbose "ADComputer Object Found for $($VM.Name) = $($ADObject.DistinguishedName)"
            $ADObjectExist = $true
        }
        else {
            #Active Directory Object not found on primary domain, even though it is a Windows VM checking if in trust
            foreach ($TrustedDomain in (Get-ADTrust -Filter *).Name) {
                $ADObject += Get-ADComputer -Properties ipv4Address, ipv6Address -Server $TrustedDomain -Filter {Name -eq "$($VM.name)"}
            }
            if ($ADObject.count -gt 1) {
                Write-Warning "Multiple Computer Objects found"
                $Stop = $true
            }
            else {
                $ADObjectExist = $false
                Write-Verbose "$($decomserver) does not exist in AD"
            }
        }
    }
}
else {
    Write-Verbose "Trying to find $DecomServer"
    if (Get-ADComputer -Filter {Name -eq $DecomServer}) {
        $ADObject = Get-ADComputer -Properties ipv4Address, ipv6Address -Filter {Name -eq $DecomServer}
        $ADObjectExist = $true
        Write-Verbose "$Decomserver found in Active Directory"
    }
    else {
        #Active Directory Object not found on primary domain, even though it is a Windows VM checking if in trust
        foreach ($TrustedDomain in (Get-ADTrust -Filter *).Name) {
            $ADObject += Get-ADComputer -Properties ipv4Address, ipv6Address -Server $TrustedDomain -Filter {Name -eq $DecomServer}
        }
        if ($ADObject.count -gt 1) {
            Write-Warning "Multiple Computer Objects found"
            $Stop = $true
        }
        else {
            $ADObjectExist = $false
            Write-Verbose "$($decomserver) does not exist in AD"
        }
    }
}
#region Search for and collect other objects to determine if anything is going to be missed
$ADDC = Get-ADDomainController -Verbose
$DNSZones = Get-DnsServerZone -ComputerName $ADDC.name
$DHCPLeases = Get-DhcpServerv4Scope -ComputerName $DHCPServer | Get-DhcpServerv4Lease -ComputerName $DHCPServer

if ($ADObjectExist) {
    foreach ($Zone in $DNSZones) {
        $DNSRecords = ""
        $DNSRecords = Get-DnsServerResourceRecord -ComputerName $ADDC.Hostname -ZoneName $Zone.ZoneName | Where-Object {$_.RecordType -eq 'PTR' -or $_.RecordType -eq 'A' -or $_.RecordType -eq 'CNAME'} | Where-Object {$_.Hostname -eq $ADObject.Name -or $_.RecordData.HostNameAlias -eq "$($ADObject.DNSHostName)." -or $_.RecordData.PtrDomainName -eq "$($ADObject.DNSHostName)."}
        foreach ($DNS in $DNSRecords) {
            Add-Member -InputObject $DNS -NotePropertyName Zone -NotePropertyValue $Zone.ZoneName
            $totalDNS += $DNS
        }
    }
    $DHCPObject = $DHCPLeases | Where-Object {$_.HostName -eq $ADObject.DNSHostName}
    $MECMObject = Invoke-Command -ComputerName $MECMServer -Scriptblock {
        Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1)
        $SiteCode = Get-PSDrive -PSProvider CMSITE
        Set-Location -Path "$($SiteCode.Name):\"
        try {
            Get-CMDevice -Name $using:ADObject.Name
        }
        catch {
            Write-Host "Unable to find $($using:ADObject.Name)"
        }
    }
}
elseif ($VMWareObjectExists) {
    foreach ($Zone in $DNSZones) {
        $DNSRecords = ""
        $DNSRecords = Get-DnsServerResourceRecord -ComputerName $ADDC.Hostname -ZoneName $Zone.ZoneName | Where-Object {$_.RecordType -eq 'PTR' -or $_.RecordType -eq 'A' -or $_.RecordType -eq 'CNAME'} | Where-Object {$_.Hostname -eq ($VM.ExtensionData.Guest.HostName).Split('.')[0] -or $_.RecordData.HostNameAlias -eq "$($VM.ExtensionData.Guest.HostName)." -or $_.RecordData.PtrDomainName -eq "$($VM.ExtensionData.Guest.HostName)."}
        foreach ($DNS in $DNSRecords) {
            Add-Member -InputObject $DNS -NotePropertyName Zone -NotePropertyValue $Zone.ZoneName
            $totalDNS += $DNS
        }
    }
    $DHCPObject = $DHCPLeases | Where-Object {$_.HostName -eq $VM.ExtensionData.Guest.HostName}
    $MECMObject = Invoke-Command -ComputerName $MECMServer -Scriptblock {
        Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1)
        $SiteCode = Get-PSDrive -PSProvider CMSITE
        Set-Location -Path "$($SiteCode.Name):\"
        try {
            Get-CMDevice -Name $using:ADObject.Name
        }
        catch {
            Write-Host "Unable to find $($using:VM.ExtensionData.Guest.Hostname)"
        }
    }
}
elseif ($DNSCleanup -or $DHCPCleanup) {
    foreach ($Zone in $DNSZones) {
        $DNSRecords = ""
        $DNSRecords = Get-DnsServerResourceRecord -ComputerName $ADDC.Hostname -ZoneName $Zone.ZoneName | Where-Object {$_.RecordType -eq 'PTR' -or $_.RecordType -eq 'A' -or $_.RecordType -eq 'CNAME'} | Where-Object {$_.Hostname -like "*$decomserver*" -or $_.RecordData.HostNameAlias  -like "*$decomserver*." -or $_.RecordData.PtrDomainName  -like "*$decomserver*."}
        foreach ($DNS in $DNSRecords) {
            Add-Member -InputObject $DNS -NotePropertyName Zone -NotePropertyValue $Zone.ZoneName
            $totalDNS += $DNS
        }
    }
    $DHCPObject = $DHCPLeases | Where-Object {$_.HostName -like "*$decomserver*"}
    $MECMObject = Invoke-Command -ComputerName $MECMServer -Scriptblock {
        Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1)
        $SiteCode = Get-PSDrive -PSProvider CMSITE
        Set-Location -Path "$($SiteCode.Name):\"
        try {
            Get-CMDevice -Name $using:decomserver
        }
        catch {
            Write-Host "Unable to find $using:decomserver"
        }
    }
}
if ($TotalDNS.Count -ge 1) {
    $DNSObjectExist = $true
    Write-Verbose "DNS Objects Found"
}
#endregion
#region Collect and Parse DHCP Leases
if ($DHCPObject.IPAddress.Count -ge 1) {
    $DHCPObjectExist = $true
    Write-Verbose "DHCP Objects Found"
}
#endregion
if ([bool]$MECMObject) {
    $MECMObjectExists = $true
}

#region Manage Defender ATP offboarding
if ($AzureCleanup) {
    # This script acquires the App Context Token and stores it in the variable $token for later use in the script.
    # Paste your Tenant ID, App ID, and App Secret (App key) into the indicated quotes below.
    Write-Verbose "Collecting Azure Defender ATP Machines"
    $tenantId = '39dc55a0-aeca-44c8-825c-2e5be9d02563' ### Paste your tenant ID here
    $appId = '9e23a38e-ff5f-43c9-bb80-e42d024d1566' ### Paste your Application ID here
    $appSecret = '_xP_-iK5ybO7Cm7Za6MwK2iQrZgMUdd_62' ### Paste your Application key here

    $resourceAppIdUri = 'https://api.securitycenter.microsoft.com'
    $oAuthUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $authBody = [Ordered] @{
        resource = "$resourceAppIdUri"
        client_id = "$appId"
        client_secret = "$appSecret"
        grant_type = 'client_credentials'
    }
    $authResponse = Invoke-RestMethod -Method Post -Uri $oAuthUri -Body $authBody -ErrorAction Stop
    $token = $authResponse.access_token

    # This will connect via above context to authenticate to Defender ATP and collect computers currently connected
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $token")
    $headers.Add("Content-Type", "text/plain")

    $body = ""

    $response = Invoke-RestMethod 'https://api.securitycenter.microsoft.com/api/machines' -Method 'GET' -Headers $headers

    #This will connect and offboard the computer that matches the DNS Host Name

    $removeheaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $removeheaders.Add("Authorization", "Bearer $token")
    $removeheaders.Add("Content-Type", "text/plain")

    $body = "{`n`n`"Comment`": `"Offboard machine by automation`"`n`n}"
    if ($ADObjectExist) {
        $machineid = ($response.value | Where-Object {$_.ComputerDNSname -eq $ADObject.DNSHostName}).id
    }
    elseif ($VMObjectExist) {
        $machineid = ($response.value | Where-Object {$_.ComputerDNSname -eq $VM.ExtensionData.Guest.HostName}).id
    }
    else {
        $machineid = ($response.value | Where-Object {$_.ComputerDNSname -like "*$decomserver*"}).id
    }
    if (![string]::IsNullOrEmpty($machineid)) {
        $AzureObjectExist = $true
    }
}

#endregion



#region Validating cleanup actions if objects exist that were not asked to be cleaned
if (!$VMwareCleanup -and $VMObjectExist) {
    do {
        $i++
        $VMwareCleanup = Read-Host -Prompt "There are components detected in VMware that match the server being decommed, ignore? (yes/no)"
    } until (($VMwareCleanup.ToLower() -ne 'yes' -or 'no' -or 'y' -or 'n') -or $i -ge 3)
    if ($VMwareCleanup.ToLower() -eq 'no' -or 'n') {
        $VMwareCleanup = $true
    }
}
if (!$ADCleanup -and $ADObjectExist) {
    do {
        $i++
        $ADCleanup = Read-Host -Prompt "There are components detected in Active Directory that match the server being decommed, ignore? (yes/no)"
    } until (($ADCleanup.ToLower() -ne 'yes' -or 'no' -or 'y' -or 'n') -or $i -ge 3)
    if ($ADCleanup.ToLower() -eq 'no' -or 'n') {
        $ADCleanup = $true
    }
}
if (!$DNSCleanup -and $DNSObjectExist) {
    do {
        $i++
        $DNSCleanup = Read-Host -Prompt "There are components detected in DNS that match the server being decommed, ignore? (yes/no)"
    } until (($DNSCleanup.ToLower() -ne 'yes' -or 'no' -or 'y' -or 'n') -or $i -ge 3)
    if ($DNSCleanup.ToLower() -eq 'no' -or 'n') {
        $DNSCleanup = $true
    }
}
if (!$DHCPCleanup -and $DHCPObjectExist) {
    do {
        $i++
        $DHCPCleanup = Read-Host -Prompt "There are components detected in DHCP that match the server being decommed, ignore? (yes/no)"
    } until (($DHCPCleanup.ToLower() -ne 'yes' -or 'no' -or 'y' -or 'n') -or $i -ge 3)
    if ($DHCPCleanup.ToLower() -eq 'no' -or 'n') {
        $DHCPCleanup = $true
    }
}
if (!$MECMCleanup -and $MECMObjectExists) {
    do {
        $i++
        $MECMCleanup = Read-Host -Prompt "There are components detected in VMware that match the server being decommed, ignore? (yes/no)"
    } until (($MECMCleanup.ToLower() -ne 'yes' -or 'no' -or 'y' -or 'n') -or $i -ge 3)
    if ($MECMCleanup.ToLower() -eq 'no' -or 'n') {
        $MECMCleanup = $true
    }
}
if (!$AzureCleanup -and $AzureObjectExist) {
    do {
        $i++
        $AzureCleanup = Read-Host -Prompt "There are components detected in Azure that match the server being decommed, ignore? (yes/no)"
    } until (($AzureCleanup.ToLower() -ne 'yes' -or 'no' -or 'y' -or 'n') -or $i -ge 3)
    if ($AzureCleanup.ToLower() -eq 'no' -or 'n') {
        $AzureCleanup = $true
    }
}
if ($Stop) {
    Write-Error "There was an error finding Objects requested to cleanup"
    break
}
#endregion

#Starting to do work
if ($AzureObjectExist -and $AzureCleanup) {
    Write-Verbose "Working to cleanup Azure"
    foreach ($AzureObject in $machineid) {
        try {
            $removeresponse = Invoke-RestMethod "https://api.security.microsoft.com/api/machines/$($AzureObject)/offboard" -Method 'POST' -Headers $headers -Body $body -ErrorAction SilentlyContinue
        }
        catch {
            Write-verbose "$($removeresponse.value)"
            Add-Member -InputObject $AzureCleanup -NotePropertyName Error -NotePropertyValue $true
            if ($_ -like "*Action is already in progress*") {
                Add-Member -InputObject $AzureObject -NotePropertyName ErrorMessage -NotePropertyValue "Offboarding already in progress"
            }
            else {
                Add-Member -InputObject $AzureObject -NotePropertyName ErrorMessage -NotePropertyValue $_
            }
            Write-Verbose "Azure Error - $($AzureObject.Error) - $($AzureObject.ErrorMessage)"
        }
    }
    Write-Verbose "Azure Cleaned up"
    $description += "**Windows Defender Offboarded**`n"
}
if ($ADObjectExist -and $ADCleanup) {
    Write-Verbose "Working to cleanup AD"
    try {
        Remove-ADObject $ADObject -Confirm:$false
        if (Get-ADGroup -Filter {Name -eq "$($ADObject.Name) Servers"}) {
            Get-ADGroup -Filter {Name -eq "$($ADObject.Name) Servers"} | Remove-ADObject -Confirm:$false
        }
    }
    catch {
        Add-Member -InputObject $ADObject -NotePropertyName Error -NotePropertyValue $true
        Add-Member -InputObject $ADObject -NotePropertyName ErrorMessage -NotePropertyValue $_.Exception.Message
        Write-Verbose "Active Directory Error - $($ADObject.Error) - $($ADObject.ErrorMessage)"
    }
    $description += "**Active Directory Object Removed**`n"
    Write-Verbose "AD Cleanup Complete"
}
if ($DNSObjectExist -and $DNSCleanup) {
    Write-Verbose "Working to cleanup DNS`n$totalDNS"
    foreach ($DNSObject in $totalDNS) {
        try {
                Write-Verbose "Removing $($DNSobject.Hostname)`nRecord $($DNSObject.RecordType)`nFrom $($DNSObject.Zone)"
                Remove-DnsServerResourceRecord -ZoneName $DNSObject.Zone -ComputerName $ADDC.Name -RRType $DNSObject.RecordType -Name $DNSObject.HostName -Force -Confirm:$false
            }
        catch {
            Add-Member -InputObject $DNSObject -NotePropertyName Error -NotePropertyValue $true
            Add-Member -InputObject $DNSObject -NotePropertyName ErrorMessage -NotePropertyValue $_.Exception.Message
            Write-Verbose "DNS Error - $($DNSObject.Error) - $($DNSObject.ErrorMessage)"
        }
    }
    $description += "**DNS Records Removed**`n"
    Write-Verbose "DNS Cleanup Complete"
}
if ($DHCPObjectExist -and $DHCPCleanup) {
    Write-Verbose "Working to cleanup DHCP"
    foreach ($Lease in $DHCPObject) {
        try {    
            if ($Lease.AddressState -like "*Reservation*") {
                Remove-DHCPServerv4reservation -ScopeID $Lease.ScopeID -ClientID $Lease.ClientID -ComputerName $DHCPServer -Confirm:$false
            }
            else {
                $Lease | Remove-DHCPServerv4Lease -ScopeID $Lease.ScopeID -ComputerName $DHCPServer -Confirm:$false
            }
        }
        catch {
            Add-Member -InputObject $ -NotePropertyName Error -NotePropertyValue $true
            Add-Member -InputObject $Lease -NotePropertyName ErrorMessage -NotePropertyValue $_.Exception.Message
            Write-Verbose "DHCP Error - $($Lease.Error) - $($Lease.ErrorMessage)"
        }
    }
    $description += "**DHCP Leases Removed**`n"
    Write-Verbose "DHCP Cleanup Complete"
}
if ($MECMCleanup -and $MECMObjectExists) {
    $MECMSuccess = Invoke-Command -ComputerName $MECMServer -Scriptblock {
        Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1)
        $SiteCode = Get-PSDrive -PSProvider CMSITE
        Set-Location -Path "$($SiteCode.Name):\"
        try {
            Remove-CMDevice -Name $using:MECMObject.Name -Force
            $true
        }
        catch {
            Write-Host "Unable to Remove $($using:MECMObject.Name)"
            $false
        }
    }
    if ($MECMSuccess) {
        $description += "**MECM Device Removed**"
    }
}
#Stop VM
if ($VMwareCleanup -and $VMObjectExist) {
    Write-Verbose "Working to cleanup VMware"
    if ($VM.Powerstate -eq 'PoweredOn') {
        $VM | Stop-VM -Confirm:$false
    }
    try {
        $VM | Remove-VM -DeletePermanently:$true -Confirm:$false
    }
    catch {
        Add-Member -InputObject $VM -NotePropertyName Error -NotePropertyValue $true
        Add-Member -InputObject $VM -NotePropertyName ErrorMessage -NotePropertyValue $_.Exception.Message
        Write-Verbose "VMware Error - $($VM.Error) - $($VM.ErrorMessage)"
    }
    $description += "**VM Removed**`n"
    Write-Verbose "VMware Cleanup Complete"
}
    $embedObject = [PSCustomObject]@{
            title = $title
            description = $description
            timestamp = $time
            color = $color
        }
        [System.Collections.ArrayList]$embedArray = @()
        $embedArray.Add($embedObject)

        $payload = [PSCustomObject]@{
            embeds = $embedArray
        }
    if (![string]::IsNullOrEmpty($description)) {
        Invoke-RestMethod -Uri $webHookUrl -Body ($payload | ConvertTo-Json -Depth 4) -Method Post -ContentType 'application/json'
    }
    else {
        Write-Host "No items found for $decomserver"
    }
}
}