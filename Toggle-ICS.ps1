<# Toggle-ICS.ps1 ─ 一鍵開關 ICS #>
param(
    [string]$Public  = "Wi-Fi",
    [string]$Private = "Ethernet"
)
$ics = New-Object -ComObject HNetCfg.HNetShare
function Get-Cfg($name) {
    foreach ($c in $ics.EnumEveryConnection()) {
        if ($ics.NetConnectionProps($c).Name -eq $name) {
            return $ics.INetSharingConfigurationForINetConnection($c)
        }
    }
    throw "Interface $name not found"
}
$pub  = Get-Cfg $Public
$priv = Get-Cfg $Private

if ($pub.SharingEnabled) {
    $pub.DisableSharing(); $priv.DisableSharing()
    Write-Host "ICS disabled. $Private back to normal."
} else {
    $pub.EnableSharing(0); $priv.EnableSharing(1)
    Write-Host "ICS enabled. $Private -> 192.168.137.1/24"
}