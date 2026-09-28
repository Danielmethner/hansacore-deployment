#Requires -RunAsAdministrator
<#
  Points the DEV hostnames at the Multipass VM in the Windows hosts file.
  LOCAL MULTIPASS DEV CLUSTER ONLY. The VM's IP is DHCP-assigned by Hyper-V and
  changes on host sleep/reboot/network switch — re-run this script afterwards.
  Only the block between the hansacore-dev markers is rewritten.

  Usage (elevated PowerShell):
    .\update-hosts.ps1 [-VmName k3s-lab]
#>
param(
    [string]$VmName = 'k3s-lab'
)
$ErrorActionPreference = 'Stop'

# Keep in sync with k8s/overlays/local-vm/hansacore-env.properties.
$hostnames = @('dev.hansacore.com', 'dev.erp.hansacore.com', 'dev.auth.hansacore.com')
$beginMarker = '# BEGIN hansacore-dev (managed by hansacore-deployment/vm/update-hosts.ps1)'
$endMarker = '# END hansacore-dev'

$info = multipass info $VmName --format json | ConvertFrom-Json
$ip = $info.info.$VmName.ipv4 | Select-Object -First 1
if (-not $ip) {
    throw "Could not determine the IPv4 address of VM '$VmName' (is it running?)"
}

$hostsFile = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$lines = [System.Collections.Generic.List[string]](Get-Content -Path $hostsFile)

$begin = $lines.IndexOf($beginMarker)
$end = $lines.IndexOf($endMarker)
if ($begin -ge 0 -and $end -gt $begin) {
    $lines.RemoveRange($begin, $end - $begin + 1)
}

$lines.Add($beginMarker)
$lines.Add("$ip`t$($hostnames -join ' ')")
$lines.Add($endMarker)

Set-Content -Path $hostsFile -Value $lines -Encoding ascii
ipconfig /flushdns | Out-Null

Write-Host "hosts file updated: $ip -> $($hostnames -join ', ')" -ForegroundColor Green
