# Removes the NightLock scheduled task, background checker and files.
# Keeps config.txt and the log unless -Purge is given.
param([switch]$Purge)
$ErrorActionPreference = 'SilentlyContinue'
$dest = Join-Path $env:LOCALAPPDATA 'NightLock'

Unregister-ScheduledTask -TaskName 'NightLock' -Confirm:$false
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'nightlock\.ps1' -and $_.CommandLine -match '\bdaemon\b' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

foreach ($f in 'nightlock.ps1', 'nightlock.cmd', 'launcher.vbs') { Remove-Item (Join-Path $dest $f) -Force }
if ($Purge) {
    Remove-Item $dest -Recurse -Force
    Write-Host 'NightLock removed, including config and logs.'
} else {
    Write-Host "NightLock removed. Config kept at $dest\config.txt (run uninstall.ps1 -Purge to delete it)."
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $newPath = (($userPath -split ';') | Where-Object { $_ -and $_ -ne $dest }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}
