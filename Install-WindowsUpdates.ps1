$Updates = Start-WUScan
Write-Host "Updates Found: " $Updates.Count
if ($Updates.Count -gt 0) {
	Install-WUUpdates -Updates $Updates
}