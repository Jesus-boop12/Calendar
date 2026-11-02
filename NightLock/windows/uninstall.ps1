# Removes the NightLock scheduled task, background checker, website blocks, shortcut and files.
# Keeps config.txt and the log unless -Purge is given.
param([switch]$Purge)
$ErrorActionPreference = 'SilentlyContinue'
$dest = Join-Path $env:LOCALAPPDATA 'NightLock'

Unregister-ScheduledTask -TaskName 'NightLock' -Confirm:$false
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'nightlock' -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# Release website blocks (only keys NightLock created).
foreach ($key in 'HKCU:\Software\Policies\Google\Chrome\URLBlocklist', 'HKCU:\Software\Policies\Microsoft\Edge\URLBlocklist', 'HKCU:\Software\Policies\BraveSoftware\Brave\URLBlocklist') {
    if ((Test-Path $key) -and (Get-ItemProperty -Path $key -Name 'NightLock')) { Remove-Item -Path $key -Recurse -Force }
}

Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\NightLock.lnk') -Force

foreach ($f in 'nightlock.ps1', 'nightlock-ui.ps1', 'nightlock.cmd', 'launcher.vbs', 'NightLock.cmd', 'install.ps1', 'uninstall.ps1', 'STOP-NightLock.cmd', 'config.example.txt') {
    Remove-Item (Join-Path $dest $f) -Force
}
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
