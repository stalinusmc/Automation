$web = New-Object System.Net.WebClient

$web.DownloadFile("https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US","C:\TSSN\Firefox.exe")

$InstallLocation = (Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe").Path

(Get-Content "C:\TSSN\firefoxdl.txt") | ForEach-Object { $_ -replace '^.*releases.([0-9][0-9]).*$','$1' } | Set-Content "C:\TSSN\firefoxdl.txt"

$LatestFFVersion = ""

