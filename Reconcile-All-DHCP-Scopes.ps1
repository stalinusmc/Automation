#Reconcile All Scopes Automagically
Get-DhcpServerv4Scope -ComputerName 'tssn-dhcp.ds.tssn.services' | Repair-DhcpServerv4IPRecord -ComputerName 'tssn-dhcp.ds.tssn.services' -ErrorAction SilentlyContinue -Force
