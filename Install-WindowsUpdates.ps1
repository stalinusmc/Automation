$Updates = Start-WUScan
Write-Host "Updates Found: " $Updates.Count
Write-Host $Updates
if ($Updates.Count -gt 0) {
	Install-WUUpdates -Updates $Updates
}