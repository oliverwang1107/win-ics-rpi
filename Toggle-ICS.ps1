<#
.SYNOPSIS
    Toggle-ICS.ps1 - Toggle ICS (Internet Connection Sharing)
.DESCRIPTION
    Toggle Windows ICS on/off. Must run as Administrator.
    If Public/Private are not specified, lists available interfaces interactively.
#>

#Requires -RunAsAdministrator

param(
    [string]$Public = "",
    [string]$Private = "",
    [string]$FixedMac = "",
    [string]$FixedIp = ""
)

$ConfigFile = Join-Path $PSScriptRoot "ics-config.json"

try {
    $ics = New-Object -ComObject HNetCfg.HNetShare
}
catch {
    Write-Error "Failed to create HNetCfg.HNetShare COM object. Check ICS service."
    exit 1
}

function Get-AllConnections {
    $list = @()
    foreach ($c in $ics.EnumEveryConnection) {
        $props = $ics.NetConnectionProps($c)
        $list += [PSCustomObject]@{ Name = $props.Name; Conn = $c }
    }
    return $list
}

function Select-Interface($prompt, $connections) {
    Write-Host "`n$prompt" -ForegroundColor Cyan
    for ($i = 0; $i -lt $connections.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $connections[$i].Name)
    }
    do {
        $input = Read-Host "Enter number"
        $idx = [int]$input - 1
    } while ($idx -lt 0 -or $idx -ge $connections.Count)
    return $connections[$idx].Name
}

function Get-Cfg($name, $connections) {
    foreach ($item in $connections) {
        $n = $item.Name
        if ($n -eq $name -or $n -like "$name*" -or $name -like "$n*" -or $n -replace '\s?\d+$', '' -eq $name) {
            return $ics.INetSharingConfigurationForINetConnection($item.Conn)
        }
    }
    throw "Network interface not found: $name"
}

# Load saved config if exists
if (Test-Path $ConfigFile) {
    $saved = Get-Content $ConfigFile | ConvertFrom-Json
    if (-not $Public)  { $Public  = $saved.Public }
    if (-not $Private) { $Private = $saved.Private }
}

# Interactive selection if still empty
$connections = Get-AllConnections
if (-not $Public -or -not $Private) {
    Write-Host "No interface config found. Please select interfaces:" -ForegroundColor Yellow

    if (-not $Public)  { $Public  = Select-Interface "Select PUBLIC interface (the one WITH internet, e.g. Wi-Fi):" $connections }
    if (-not $Private) { $Private = Select-Interface "Select PRIVATE interface (the one TO share to, e.g. Ethernet):" $connections }

    $save = Read-Host "`nSave this selection for next time? (Y/N)"
    if ($save -match '^[Yy]') {
        @{ Public = $Public; Private = $Private } | ConvertTo-Json | Set-Content $ConfigFile
        Write-Host "Saved to $ConfigFile" -ForegroundColor Green
    }
}

Write-Host "`nPublic: [$Public]  Private: [$Private]" -ForegroundColor Cyan

try {
    $pub  = Get-Cfg $Public $connections
    $priv = Get-Cfg $Private $connections

    if ($pub.SharingEnabled) {
        Write-Host "ICS is currently ENABLED, disabling..." -ForegroundColor Yellow
        $pub.DisableSharing()
        $priv.DisableSharing()
        Write-Host "ICS disabled. $Private back to normal." -ForegroundColor Green
    }
    else {
        Write-Host "ICS is currently DISABLED, enabling..." -ForegroundColor Yellow
        $pub.EnableSharing(0)
        $priv.EnableSharing(1)
        Write-Host "ICS enabled. $Private -> 192.168.137.1" -ForegroundColor Green

        if ($FixedMac -and $FixedIp) {
            $cleanMac = ($FixedMac -replace '[:\-]', '').ToUpper()
            Write-Host "Setting static DHCP: MAC [$cleanMac] -> IP [$FixedIp]..." -ForegroundColor Cyan
            $dhcpPath = "HKLM:\System\CurrentControlSet\Services\SharedAccess\Parameters"
            try {
                if (-not (Test-Path $dhcpPath)) { New-Item -Path $dhcpPath -Force | Out-Null }
                $ipBytes = [System.Net.IPAddress]::Parse($FixedIp).GetAddressBytes()
                $ipVal   = [System.BitConverter]::ToInt32($ipBytes, 0)
                Set-ItemProperty -Path $dhcpPath -Name $cleanMac -Value $ipVal -Type DWord -Force
                Restart-Service SharedAccess -Force
                Write-Host "Static IP set. Service restarted." -ForegroundColor Green
            }
            catch { Write-Warning "Failed to set static IP: $_" }
        }

        Write-Host "`nScanning for connected devices..." -ForegroundColor Cyan
        Write-Host "Waiting 5 seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 5

        $neighbors = Get-NetNeighbor -InterfaceAlias $Private -AddressFamily IPv4 |
            Where-Object { $_.State -ne "Incomplete" -and $_.IPAddress -ne "192.168.137.1" }

        if ($neighbors) {
            Write-Host "Found devices on [$Private]:" -ForegroundColor Green
            $neighbors | ForEach-Object {
                Write-Host (" >> IP: {0}  (MAC: {1})" -f $_.IPAddress, $_.LinkLayerAddress) -ForegroundColor White
            }
        }
        else {
            Write-Host "No devices found yet. Try 'arp -a' in CMD manually." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Error "Error: $_"
}

Write-Host "`nPress Enter to close..." -ForegroundColor Gray
$null = Read-Host
