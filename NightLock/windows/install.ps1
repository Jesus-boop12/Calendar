# Installs NightLock for the current Windows user:
#   %LOCALAPPDATA%\NightLock\            the script, launcher and your config.txt
#   Scheduled task "NightLock"           starts the hidden background checker at logon
#   %LOCALAPPDATA%\NightLock on PATH     so `nightlock status` works from any terminal
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'NightLock'
$taskName = 'NightLock'

New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($f in 'nightlock.ps1', 'nightlock.cmd', 'launcher.vbs') {
    Copy-Item (Join-Path $src $f) (Join-Path $dest $f) -Force
}
if (-not (Test-Path (Join-Path $dest 'config.txt'))) {
    Copy-Item (Join-Path $src 'config.example.txt') (Join-Path $dest 'config.txt')
}

# Stop any checker from a previous install so the new copy takes over.
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'nightlock\.ps1' -and $_.CommandLine -match '\bdaemon\b' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$action   = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}"' -f (Join-Path $dest 'launcher.vbs'))
# Start at logon, and re-launch every 5 minutes as a safety net (the checker is
# single-instance, so this is a no-op while it is already running).
$atLogon  = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$every5   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew
$settings.ExecutionTimeLimit = 'PT0S'
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($atLogon, $every5) -Settings $settings `
    -Description 'NightLock: closes distracting apps during your nightly lock window.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

# Put the install folder on the user's PATH.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
if (($userPath -split ';') -notcontains $dest) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $dest).TrimStart(';'), 'User')
}
$env:Path = "$env:Path;$dest"

Write-Host ''
Write-Host 'NightLock installed.' -ForegroundColor Green
Write-Host ''
Start-Sleep -Seconds 2
& (Join-Path $dest 'nightlock.ps1') status
Write-Host ''
Write-Host 'Edit your lock window and app list:   nightlock edit'
Write-Host '(open a new terminal first so PATH is refreshed)'
