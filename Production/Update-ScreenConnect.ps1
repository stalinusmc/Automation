#Update the following URLS to your specific installation / Discord webHookURL
$webHookUrl = "https://discord.com/api/webhooks/822853529516769341/4u3XscVkIqWMTy_ExjF6uDjyKvvHrd77dr9AvsZNII4_CPrSRbWDot9qUqdw6O8Th3Tw"
$url = "https://support.tssn.services"



$web = New-Object System.Net.WebClient
$Webr = Invoke-WebRequest https://www.connectwise.com/platform/unified-management/control/download/archive -UseBasicParsing
$href = ($Webr.links | Where-Object {$_ -like "*Release.msi*"} | Select-Object -First 1).href
$temp = [System.Environment]::GetEnvironmentVariable('TEMP','Machine')
$file = $href.split('/')[3]
$version = $file.Split('_')[1]
$Installed = (Get-WMIObject -Query "SELECT * FROM Win32_Product Where Vendor Like '%ScreenConnect%'").Version
$parms=@("/qn", "/l*v", "$temp\ScreenConnect-$env:Computername.log";"/i";"$temp\$file") 
if ($version -gt $Installed) {

        $title       = 'ScreenConnect Update Available'
        $description = "Upgrading from $Installed to $Version on $env:Computername"
        $color       = '15105570'
        $time = Get-date -Date (Get-Date).ToUniversalTime()  -Format yyyy-MM-ddTHH:mm:ss.fffZ
        $embedObject = [PSCustomObject]@{
            title = $title
            description = $description
            url = $url
            timestamp = $time
            color = $color
        }
        [System.Collections.ArrayList]$embedArray = @()
        $embedArray.Add($embedObject)

        $payload = [PSCustomObject]@{
            embeds = $embedArray
        }
        Invoke-RestMethod -Uri $webHookUrl -Body ($payload | ConvertTo-Json -Depth 4) -Method Post -ContentType 'application/json'

    Write-Host "Newer Version Available, attempting to install"
    $web.DownloadFile($href,"$temp\$file")
    $RESULT = (Start-Process -FilePath msiexec.exe   -ArgumentList $parms -Wait -Passthru).ExitCode
    if ($RESULT -eq '0') {
        Remove-Item "$temp\$file" -Confirm:$false -Force
        $title       = 'ScreenConnect Update Complete'
        $description = "$Version is now installed on $env:Computername"
        $color       = '15105570'
        $time = Get-date -Date (Get-Date).ToUniversalTime()  -Format yyyy-MM-ddTHH:mm:ss.fffZ
        $embedObject = [PSCustomObject]@{
            title = $title
            description = $description
            url = $url
            timestamp = $time
            color = $color
        }
        [System.Collections.ArrayList]$embedArray = @()
        $embedArray.Add($embedObject)

        $payload = [PSCustomObject]@{
            embeds = $embedArray
        }
        Invoke-RestMethod -Uri $webHookUrl -Body ($payload | ConvertTo-Json -Depth 4) -Method Post -ContentType 'application/json'
    }
    else {
        $title       = '**ScreenConnect Update Failed**'
        $description = "__**Upgrade from $Installed to $Version failed**__`n**Please Remediate Immediately**"
        $color       = '15105570'
        $time = Get-date -Date (Get-Date).ToUniversalTime()  -Format yyyy-MM-ddTHH:mm:ss.fffZ
        $embedObject = [PSCustomObject]@{
            title = $title
            description = $description
            url = $url
            timestamp = $time
            color = $color
        }
        [System.Collections.ArrayList]$embedArray = @()
        $embedArray.Add($embedObject)

        $payload = [PSCustomObject]@{
            embeds = $embedArray
        }
        Invoke-RestMethod -Uri $webHookUrl -Body ($payload | ConvertTo-Json -Depth 4) -Method Post -ContentType 'application/json'
    }
} 
