$web = New-Object System.Net.WebClient
$Webr = Invoke-WebRequest https://www.connectwise.com/platform/unified-management/control/download/archive
$href = ($Webr.links | Where-Object {$_.OuterText -like "*Stable*Windows*"} | Select-Object -First 1).href
$file = $href.split('/')[3]
$web.DownloadFile($href,"\\tssn-file\System\Installers\ScreenConnect\$file")


& "\\tssn-file\System\Installers\ScreenConnect\$file" /qn