$text = Get-Content -Path 'c:\projects\win-ics-rpi\Toggle-ICS.ps1' -Raw
[System.IO.File]::WriteAllText('c:\projects\win-ics-rpi\Toggle-ICS.ps1', $text, [System.Text.Encoding]::UTF8)
Stop-Process -Name 'Toggle-ICS' -Force -ErrorAction SilentlyContinue
Invoke-ps2exe -inputFile 'c:\projects\win-ics-rpi\Toggle-ICS.ps1' -outputFile 'c:\projects\win-ics-rpi\Toggle-ICS.exe'
