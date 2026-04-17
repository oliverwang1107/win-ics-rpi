<#
.SYNOPSIS
    Toggle-ICS.ps1 - Toggle ICS (Internet Connection Sharing)
.DESCRIPTION
    Toggle Windows ICS on/off. Must run as Administrator.
#>

#Requires -RunAsAdministrator

param(
    [string]$Public = "Wi-Fi 3",
    [string]$Private = "Ethernet",
    [string]$FixedMac = "",
    [string]$FixedIp = ""
)

try {
    $ics = New-Object -ComObject HNetCfg.HNetShare
}
catch {
    Write-Error "Failed to create HNetCfg.HNetShare COM object. Check ICS service."
    exit 1
}

function Get-Cfg($name) {
    Write-Host "Searching for interface: $name" -ForegroundColor Gray
    $allNames = @()
    foreach ($c in $ics.EnumEveryConnection) {
        $props = $ics.NetConnectionProps($c)
        $n = $props.Name
        $allNames += $n
        # Fuzzy match: exact, or name starts with/contains (ignoring numbers/spaces)
        if ($n -eq $name -or $n -like "$name*" -or $name -like "$n*" -or $n -replace '\s?\d+$', '' -eq $name) {
            Write-Host "Found match: '$n'" -ForegroundColor Gray
            return $ics.INetSharingConfigurationForINetConnection($c)
        }
    }
    
    Write-Host "Available connections found:" -ForegroundColor DarkGray
    $allNames | ForEach-Object { Write-Host " - '$_'" -ForegroundColor DarkGray }
    throw "Network interface not found: $name"
}

try {
    Write-Host "Getting config for [$Public] and [$Private]..." -ForegroundColor Cyan
    $pub = Get-Cfg $Public
    $priv = Get-Cfg $Private

    if ($pub.SharingEnabled) {
        Write-Host "ICS is currently ENABLED, disabling..." -ForegroundColor Yellow
        $pub.DisableSharing()
        $priv.DisableSharing()
        Write-Host "ICS disabled. $Private back to normal." -ForegroundColor Green
    }
    else {
        Write-Host "ICS is currently DISABLED, enabling..." -ForegroundColor Yellow
        # 0 = ICSSHARINGTYPE_PUBLIC, 1 = ICSSHARINGTYPE_PRIVATE
        $pub.EnableSharing(0)
        $priv.EnableSharing(1)
        Write-Host "ICS enabled. $Private -> 192.168.137.1" -ForegroundColor Green

        # Static IP assignment via registry if MAC and IP are provided
        if ($FixedMac -and $FixedIp) {
            $cleanMac = ($FixedMac -replace '[:\-]', '').ToUpper()

            Write-Host "Setting static DHCP: MAC [$cleanMac] -> IP [$FixedIp]..." -ForegroundColor Cyan
            $dhcpPath = "HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters"

            try {
                if (-not (Test-Path $dhcpPath)) {
                    New-Item -Path $dhcpPath -Force | Out-Null
                }

                $ipBytes = [System.Net.IPAddress]::Parse($FixedIp).GetAddressBytes()
                $ipVal = [System.BitConverter]::ToInt32($ipBytes, 0)

                Set-ItemProperty -Path $dhcpPath -Name $cleanMac -Value $ipVal -Type DWord -Force
                Restart-Service SharedAccess -Force
                Write-Host "Static IP set. Service restarted." -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to set static IP: $_"
            }
        }

        # --- IP Discovery Section ---
        Write-Host "`nScanning for connected devices (RPi)..." -ForegroundColor Cyan
        Write-Host "Waiting 5 seconds for devices to initialize..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
        
        $neighbors = Get-NetNeighbor -InterfaceAlias $Private -AddressFamily IPv4 | Where-Object { $_.State -ne "Incomplete" -and $_.IPAddress -ne "192.168.137.1" }
        
        if ($neighbors) {
            Write-Host "Found the following devices on [$Private]:" -ForegroundColor Green
            $neighbors | ForEach-Object {
                Write-Host (" >> IP: {0}  (MAC: {1})" -f $_.IPAddress, $_.LinkLayerAddress) -ForegroundColor White
            }
        }
        else {
            Write-Host "No devices found yet. If your RPi just plugged in, it might take a minute." -ForegroundColor Yellow
            Write-Host "You can also run 'arp -a' in CMD to check manually." -ForegroundColor Gray
        }
    }
}
catch {
    Write-Error "Error: $_"
}

Write-Host "Press Enter to close..." -ForegroundColor Gray
$null = Read-Host