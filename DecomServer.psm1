function Decom-Server {
[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$decomserver
	)
#Below are the variables
$vcserver = "vcenter.tssn.services"
$status = "DELETED"
$uri = "https://discord.com/api/webhooks/811280996723982396/mOwQD-Z0sof8n9FbFuUIXqvZf8DqYg47JRIbxJM1tfAqIIDr_wrusknx0UzbNJLYqvHG"
$body = ConvertTo-Json -Depth 6 @{
    content = $("Server Decommissioned via Script")
    embeds = @(
        @{
            title = 'Details'
            description = $decomserver
            fields = @(
                @{
                name = 'Current State'
                value = $($status)
                }            
                
            )
        }
    )
}
$enc = [system.Text.Encoding]::UTF8
$encodedBody = $enc.GetBytes($body)

Import-Module VMware.VimAutomation.Core -Force
# Connect to vCenter server.
Connect-VIServer $vcserver

$VM = Get-VM -Name $decomserver
#Stop VM
if ($VM.Powerstate -eq 'PoweredOn') {
	$VM | Stop-VM -Confirm:$false
}
#Perm Delete the VM
$VM | Remove-VM -DeletePermanently:$true -Confirm:$false
#Remove the object from AD
Get-ADComputer $decomserver | Remove-ADObject -Recursive -Confirm:$False
Invoke-RestMethod -Uri $uri -Method Post -body $encodedBody -ContentType 'application/json';
}

