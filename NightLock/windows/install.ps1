# Installs NightLock for the current Windows user (no admin rights needed):
#   %LOCALAPPDATA%\NightLock\        scripts and your config.txt
#   Scheduled task "NightLock"       starts the hidden background checker at logon
#                                    and relaunches it every 5 minutes if it is not running
#   Start Menu > NightLock           opens the settings window
#   %LOCALAPPDATA%\NightLock on PATH so "nightlock status" works from any terminal
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'NightLock'
$taskName = 'NightLock'
$files = 'nightlock.ps1', 'nightlock-ui.ps1', 'nightlock.cmd', 'launcher.vbs', 'NightLock.cmd', 'install.ps1', 'uninstall.ps1', 'STOP-NightLock.cmd', 'config.example.txt'

New-Item -ItemType Directory -Force -Path $dest | Out-Null
if ((Resolve-Path $src).Path.TrimEnd('\') -ne $dest.TrimEnd('\')) {
    foreach ($f in $files) {
        $from = Join-Path $src $f
        if (Test-Path $from) { Copy-Item $from (Join-Path $dest $f) -Force }
    }
}
if (-not (Test-Path (Join-Path $dest 'config.txt'))) {
    Copy-Item (Join-Path $dest 'config.example.txt') (Join-Path $dest 'config.txt')
}

# Replace any checker from a previous install.
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -match 'nightlock\.ps1' -and $_.CommandLine -match '\bdaemon\b' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

$launcher = Join-Path $dest 'launcher.vbs'
$action   = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"{0}" daemon' -f $launcher)
$atLogon  = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$every5   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
$settings.ExecutionTimeLimit = 'PT0S'
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($atLogon, $every5) -Settings $settings `
    -Description 'NightLock: closes distracting apps and blocks websites during your lock window. Open NightLock from the Start Menu to change it or press Stop.' -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

# Start Menu shortcut to the settings window.
$programs = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut((Join-Path $programs 'NightLock.lnk'))
$sc.TargetPath = 'wscript.exe'
$sc.Arguments = ('"{0}" ui' -f $launcher)
$sc.WorkingDirectory = $dest
$sc.IconLocation = "$env:SystemRoot\System32\shell32.dll,47"
$sc.Description = 'NightLock settings'
$sc.Save()

# PATH for the command line.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
if (($userPath -split ';') -notcontains $dest) {
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $dest).TrimStart(';'), 'User')
}
$env:Path = "$env:Path;$dest"

if (-not $Quiet) {
    Write-Host ''
    Write-Host 'NightLock installed.' -ForegroundColor Green
    Write-Host ''
    Start-Sleep -Seconds 2
    & (Join-Path $dest 'nightlock.ps1') status
    Write-Host ''
    Write-Host 'Open "NightLock" from the Start Menu to pick apps, websites and times.'
    Write-Host 'From a new terminal: nightlock status | nightlock stop | nightlock start'
}
