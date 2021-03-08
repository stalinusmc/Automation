#Create NEW Customer
function New-Customer {
[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$NewCustomerName
	)

Import-Module VMware.VimAutomation.Core -Force
$vcserver = "vcenter.tssn.services"
# Connect to vCenter server.
Connect-VIServer $vcserver

$OURoot = "OU=Organizations,DC=ds,DC=tssn,DC=services"
$NewCustomerOURoot = "OU="+$NewCustomerName+","+$OURoot
$NewCustomerUsersOU = "OU=Users,"+$NewCustomerOURoot
$NewCustomerGroupsOU = "OU=Groups,"+$NewCustomerUsersOU
$NewCustomerWorkstationAdminsGroup = $NewCustomerName + " Admins"
$NewCustomerAdminsGroup = $NewCustomerName+" Workstation Admins"
$NewCustomerVMAdminsGroup = $NewCustomerName+" VM Admins"
$VMRoleName = 'Admin'
$VMRole = Get-VIRole -Name $VMRoleName

#Creating AD OU's for customer
New-ADOrganizationalUnit -Name $NewCustomerName -Path $OURoot -ProtectedFromAccidentalDeletion $True
New-ADOrganizationalUnit -Name "Computers" -Path $NewCustomerOURoot -ProtectedFromAccidentalDeletion $True
New-ADOrganizationalUnit -Name "Users" -Path $NewCustomerOURoot -ProtectedFromAccidentalDeletion $True
New-ADOrganizationalUnit -Name "Groups" -Path $NewCustomerUsersOU -ProtectedFromAccidentalDeletion $True

#Creating AD Groups for Customer
New-ADGroup -Name $NewCustomerAdminsGroup -SamAccountName $NewCustomerAdminsGroup -GroupCategory Security -GroupScope Global -DisplayName $NewCustomerAdminsGroup -Path $NewCustomerGroupsOU 
New-ADGroup -Name $NewCustomerWorkstationAdminsGroup -SamAccountName $NewCustomerWorkstationAdminsGroup -GroupCategory Security -GroupScope Global -DisplayName $NewCustomerWorkstationAdminsGroup -Path $NewCustomerGroupsOU
New-ADGroup -Name $NewCustomerVMAdminsGroup -SamAccountName $NewCustomerVMAdminsGroup -GroupCategory Security -GroupScope Global -DisplayName $NewCustomerVMAdminsGroup -Path $NewCustomerGroupsOU

#Pause for AD replication
Write-Host "Pauding while AD replicated new groups"
Start-Sleep - 30

#Create New Folder in vCenter
New-Folder -Name $NewCustomerName -Location (Get-Folder "PROD" | Get-Folder "Customers")
$NewCustomerVMFolder = Get-Folder "PROD" | Get-Folder "Customers" | Get-Folder $NewCustomerName
#Create Customer Tags in vCenter
New-Tag -Name $NewCustomerName -Category "Customer Name"

#Assign VM Permissions  
New-VIPermission -Entity $NewCustomerVMFolder -Principal "TSSN\$NewCustomerVMAdminsGroup" -Role $VMRole -Propagate $True -Confirm:$false
}