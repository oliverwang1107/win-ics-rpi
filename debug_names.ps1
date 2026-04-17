$ics = New-Object -ComObject HNetCfg.HNetShare
Write-Host "--- Debugging ICS Interfaces ---" -ForegroundColor Yellow
$count = 0
foreach ($c in $ics.EnumEveryConnection) {
    $count++
    $p = $ics.NetConnectionProps($c)
    $name = $p.Name
    Write-Host ("Found Index {0}: '{1}' (Length: {2})" -f $count, $name, $name.Length)
    
    # Compare with expected values
    if ($name -eq "Wi-Fi 3") { Write-Host ">> MATCHED 'Wi-Fi 3'!" -ForegroundColor Green }
    if ($name -like "*Wi-Fi*") { Write-Host ">> Partial match found!" -ForegroundColor Cyan }
}

if ($count -eq 0) {
    Write-Warning "No connections found by ICS COM object. This usually happens if not running with enough permissions or service issue."
}
