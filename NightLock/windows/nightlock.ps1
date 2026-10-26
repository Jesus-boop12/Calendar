<#
NightLock - closes distracting apps during a nightly time window on Windows.

  nightlock check            run one enforcement pass
  nightlock daemon           run forever, checking every 20 seconds (the scheduled task runs this)
  nightlock status           show the window, blocked apps and whether the lock is active
  nightlock add chrome       add an app by process name (as shown in Task Manager > Details, without .exe)
  nightlock remove chrome    remove an app
  nightlock pause 10         temporarily lift the lock for 10 minutes (only if the config allows it)
  nightlock resume           end a pause early
  nightlock edit             open the config file in Notepad
  nightlock log              show recent log lines

Config lives in %LOCALAPPDATA%\NightLock\config.txt (see config.example.txt).
Test without waiting for night:
  $env:NIGHTLOCK_DRY_RUN=1; $env:NIGHTLOCK_NOW="23:00 Mon"; nightlock check
#>
param(
    [Parameter(Position = 0)] [string]$Command = 'help',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'

if ($env:NIGHTLOCK_CONFIG_DIR) { $ConfigDir = $env:NIGHTLOCK_CONFIG_DIR } else { $ConfigDir = Join-Path $env:LOCALAPPDATA 'NightLock' }
$ConfigFile = Join-Path $ConfigDir 'config.txt'
$StateDir   = Join-Path $ConfigDir 'state'
$LogFile    = Join-Path $ConfigDir 'nightlock.log'
$PauseFile  = Join-Path $StateDir 'pause_until.txt'
$WarnedFile = Join-Path $StateDir 'warned_on.txt'
$DryRun     = ($env:NIGHTLOCK_DRY_RUN -eq '1')
$CheckIntervalSeconds = 20

New-Item -ItemType Directory -Force -Path $ConfigDir, $StateDir | Out-Null

$DefaultConfig = @'
# NightLock configuration. Times are 24-hour HH:MM in your PC's local time.
# The window may cross midnight (start=22:00, end=06:00 is a normal night).

start = 22:00
end = 06:00

# Nights the lock applies to, by the day the window STARTS on.
# Weeknights only would be: days = Sun,Mon,Tue,Wed,Thu
days = Mon,Tue,Wed,Thu,Fri,Sat,Sun

# Minutes before `start` to show a heads-up notification (0 disables).
warn_minutes = 10

# Allow `nightlock pause <minutes>`? Set to no for a lock with no escape hatch.
allow_pause = yes
max_pause_minutes = 15

# Seconds to let an app close politely before it is force-killed.
grace_seconds = 5

# Show a Windows notification when an app is closed.
notify = yes

# Apps to block, by process name as shown in Task Manager > Details (without .exe).
# One per line. Common ones: chrome, msedge, firefox, Discord, steam, Spotify, Netflix.
app = chrome
app = msedge
app = Discord
app = steam
'@

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Fail([string]$Message) {
    throw $Message
}

function Ensure-Config {
    if (-not (Test-Path $ConfigFile)) {
        Set-Content -Path $ConfigFile -Value $DefaultConfig -Encoding UTF8
        Write-Log "created default config at $ConfigFile"
    }
}

function Read-Config {
    $cfg = @{
        start = '22:00'; end = '06:00'
        days = 'Mon,Tue,Wed,Thu,Fri,Sat,Sun'
        warn_minutes = 10; allow_pause = 'yes'; max_pause_minutes = 15
        grace_seconds = 5; notify = 'yes'
        apps = New-Object System.Collections.ArrayList
    }
    Ensure-Config
    foreach ($raw in Get-Content -Path $ConfigFile -Encoding UTF8) {
        $line = ($raw -split '#', 2)[0].Trim()
        if (-not $line) { continue }
        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) { continue }
        $key = $parts[0].Trim().ToLower()
        $value = $parts[1].Trim()
        switch ($key) {
            'start'             { $cfg.start = $value }
            'end'               { $cfg.end = $value }
            'days'              { $cfg.days = $value }
            'warn_minutes'      { $cfg.warn_minutes = [int]$value }
            'allow_pause'       { $cfg.allow_pause = $value.ToLower() }
            'max_pause_minutes' { $cfg.max_pause_minutes = [int]$value }
            'grace_seconds'     { $cfg.grace_seconds = [int]$value }
            'notify'            { $cfg.notify = $value.ToLower() }
            'app'               { if ($value) { [void]$cfg.apps.Add(($value -replace '\.exe$', '')) } }
            default             { Write-Log "config: unknown key '$key' ignored" }
        }
    }
    return $cfg
}

# ---------- time helpers ----------
function ConvertTo-Minutes([string]$Time) {
    if ($Time -notmatch '^\d{1,2}:\d{2}$') { Fail "bad time '$Time' in config (use HH:MM)" }
    $h, $m = $Time -split ':'
    return [int]$h * 60 + [int]$m
}

# $env:NIGHTLOCK_NOW = "HH:MM Day" fakes the clock for testing.
function Get-NowMinutes {
    if ($env:NIGHTLOCK_NOW) { return ConvertTo-Minutes (($env:NIGHTLOCK_NOW -split ' ')[0]) }
    $n = Get-Date
    return $n.Hour * 60 + $n.Minute
}

function Get-TodayName {
    if ($env:NIGHTLOCK_NOW) { return ($env:NIGHTLOCK_NOW -split ' ')[1] }
    return (Get-Date).DayOfWeek.ToString().Substring(0, 3)
}

function Get-YesterdayName([string]$Day) {
    $order = 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
    $i = [array]::IndexOf($order, $Day)
    if ($i -lt 0) { return 'Sun' }
    return $order[($i + 6) % 7]
}

function Test-DayEnabled($cfg, [string]$Day) {
    $enabled = $cfg.days -split ',' | ForEach-Object { $_.Trim() }
    return ($enabled -contains $Day)
}

# True when the lock window is active right now (ignoring pauses).
function Test-InWindow($cfg) {
    $now = Get-NowMinutes
    $start = ConvertTo-Minutes $cfg.start
    $end = ConvertTo-Minutes $cfg.end
    $today = Get-TodayName
    if ($start -lt $end) {
        return ($now -ge $start -and $now -lt $end -and (Test-DayEnabled $cfg $today))
    } elseif ($start -gt $end) {
        if ($now -ge $start) { return (Test-DayEnabled $cfg $today) }
        if ($now -lt $end)   { return (Test-DayEnabled $cfg (Get-YesterdayName $today)) }
        return $false
    }
    return $false   # start == end: zero-length window, never lock
}

function Test-InWarningPeriod($cfg) {
    if ($cfg.warn_minutes -le 0) { return $false }
    $now = Get-NowMinutes
    $start = ConvertTo-Minutes $cfg.start
    if (-not (Test-DayEnabled $cfg (Get-TodayName))) { return $false }
    return ($now -lt $start -and ($start - $now) -le $cfg.warn_minutes)
}

function Get-MinutesUntilEnd($cfg) {
    $now = Get-NowMinutes
    $end = ConvertTo-Minutes $cfg.end
    if ($now -lt $end) { return $end - $now }
    return 1440 - $now + $end
}

function Get-PauseUntil {
    if (-not (Test-Path $PauseFile)) { return $null }
    try {
        $until = [DateTime]::ParseExact((Get-Content $PauseFile -Raw).Trim(), 'o', $null)
        if ($until -gt (Get-Date)) { return $until }
    } catch { }
    Remove-Item $PauseFile -Force -ErrorAction SilentlyContinue
    return $null
}

# ---------- Windows actions ----------
function Send-Toast([string]$Title, [string]$Body, $cfg) {
    if ($cfg.notify -ne 'yes') { return }
    if ($DryRun) { Write-Host "[dry-run] notify: $Title - $Body"; return }
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $t = [System.Security.SecurityElement]::Escape($Title)
        $b = [System.Security.SecurityElement]::Escape($Body)
        $xml = "<toast><visual><binding template='ToastGeneric'><text>$t</text><text>$b</text></binding></visual></toast>"
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
    } catch {
        Write-Log "notification failed: $($_.Exception.Message)"
    }
}

function Get-AppProcesses([string]$App) {
    return @(Get-Process -Name $App -ErrorAction SilentlyContinue)
}

function Stop-App([string]$App, $cfg) {
    if ($DryRun) { Write-Host "[dry-run] would close: $App"; return }
    # Ask windows to close first so the app can save state, then force it.
    foreach ($p in Get-AppProcesses $App) {
        try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } } catch { }
    }
    $deadline = (Get-Date).AddSeconds($cfg.grace_seconds)
    while ((Get-Date) -lt $deadline -and (Get-AppProcesses $App).Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }
    $left = Get-AppProcesses $App
    if ($left.Count -gt 0) {
        $left | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# True when a NightLock daemon other than this process is running.
function Test-DaemonRunning {
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop
        foreach ($p in $procs) {
            if ($p.ProcessId -eq $PID) { continue }
            if ($p.CommandLine -and $p.CommandLine -match 'nightlock\.ps1' -and $p.CommandLine -match '\bdaemon\b') { return $true }
        }
    } catch { }
    return $false
}

# ---------- commands ----------
function Invoke-Check {
    $cfg = Read-Config
    if ($cfg.apps.Count -eq 0) { Write-Log 'no apps configured'; return }

    if (Test-InWindow $cfg) {
        Remove-Item $WarnedFile -Force -ErrorAction SilentlyContinue
        if (Get-PauseUntil) { return }
        $closed = @()
        foreach ($app in $cfg.apps) {
            if ((Get-AppProcesses $app).Count -gt 0) {
                Stop-App $app $cfg
                $closed += $app
                Write-Log "closed $app (window $($cfg.start)-$($cfg.end))"
            }
        }
        if ($closed.Count -gt 0) {
            Send-Toast 'NightLock' ("Closed {0}. Unlocks at {1}." -f ($closed -join ', '), $cfg.end) $cfg
        }
    } elseif (Test-InWarningPeriod $cfg) {
        $today = Get-Date -Format 'yyyy-MM-dd'
        $warned = ''
        if (Test-Path $WarnedFile) { $warned = (Get-Content $WarnedFile -Raw).Trim() }
        if ($warned -ne $today) {
            Send-Toast 'NightLock' "Distracting apps lock at $($cfg.start). Wrap up what you're doing." $cfg
            Write-Log "sent warning for $($cfg.start) lock"
            if (-not $DryRun) { Set-Content -Path $WarnedFile -Value $today }
        }
    }
}

function Start-Daemon {
    if (Test-DaemonRunning) { return }   # another checker is already running
    Write-Log "daemon started (pid $PID)"
    while ($true) {
        try { Invoke-Check } catch { Write-Log "check failed: $($_.Exception.Message)" }
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
}

function Show-Status {
    $cfg = Read-Config
    Write-Host 'NightLock'
    Write-Host "  window : $($cfg.start) -> $($cfg.end)  (nights: $($cfg.days))"
    Write-Host "  config : $ConfigFile"
    Write-Host "  log    : $LogFile"
    if (Test-InWindow $cfg) {
        $until = Get-PauseUntil
        if ($until) { Write-Host "  state  : PAUSED until $($until.ToString('HH:mm'))" }
        else        { Write-Host "  state  : LOCKED ($(Get-MinutesUntilEnd $cfg) min left)" }
    } else {
        Write-Host '  state  : unlocked'
    }
    $task = Get-ScheduledTask -TaskName 'NightLock' -ErrorAction SilentlyContinue
    if (-not $task) { $taskState = 'NOT installed (run install.cmd)' }
    elseif (Test-DaemonRunning) { $taskState = 'installed, background checker running' }
    else { $taskState = 'installed, but background checker is NOT running (run: Start-ScheduledTask NightLock)' }
    Write-Host "  task   : $taskState"
    Write-Host '  apps   :'
    foreach ($app in $cfg.apps) {
        if ((Get-AppProcesses $app).Count -gt 0) { Write-Host "    - $app (running)" } else { Write-Host "    - $app" }
    }
}

function Add-App([string[]]$Names) {
    if (-not $Names -or $Names.Count -eq 0) { Fail 'usage: nightlock add <processname>' }
    $cfg = Read-Config
    foreach ($n in $Names) {
        $name = $n -replace '\.exe$', ''
        if ($cfg.apps -contains $name) { Write-Host "$name is already blocked"; continue }
        $raw = Get-Content -Path $ConfigFile -Raw -Encoding UTF8
        if ($raw -and -not $raw.EndsWith("`n")) { Add-Content -Path $ConfigFile -Value '' -Encoding UTF8 }
        Add-Content -Path $ConfigFile -Value "app = $name" -Encoding UTF8
        [void]$cfg.apps.Add($name)
        Write-Host "added $name"
    }
}

function Remove-App([string[]]$Names) {
    if (-not $Names -or $Names.Count -eq 0) { Fail 'usage: nightlock remove <processname>' }
    Ensure-Config
    foreach ($n in $Names) {
        $name = $n -replace '\.exe$', ''
        $pattern = '^\s*app\s*=\s*' + [regex]::Escape($name) + '(\.exe)?\s*$'
        $lines = @(Get-Content -Path $ConfigFile -Encoding UTF8)
        $kept = @($lines | Where-Object { $_ -notmatch $pattern })
        if ($kept.Count -eq $lines.Count) { Write-Host "$name was not in the list"; continue }
        Set-Content -Path $ConfigFile -Value $kept -Encoding UTF8
        Write-Host "removed $name"
    }
}

function Set-Pause([string[]]$Args2) {
    $cfg = Read-Config
    if ($cfg.allow_pause -ne 'yes') { Fail "pausing is disabled in $ConfigFile (allow_pause = no)" }
    $minutes = 0
    if (-not $Args2 -or -not [int]::TryParse($Args2[0], [ref]$minutes) -or $minutes -lt 1) { Fail 'usage: nightlock pause <minutes>' }
    if ($minutes -gt $cfg.max_pause_minutes) { Fail "max pause is $($cfg.max_pause_minutes) minutes (max_pause_minutes in config)" }
    Set-Content -Path $PauseFile -Value (Get-Date).AddMinutes($minutes).ToString('o')
    Write-Log "paused for $minutes min"
    Write-Host "NightLock paused for $minutes minutes."
}

function Clear-Pause {
    Remove-Item $PauseFile -Force -ErrorAction SilentlyContinue
    Write-Log 'pause ended manually'
    Write-Host 'NightLock resumed.'
}

function Show-Help {
    $text = Get-Content -Path $PSCommandPath -Raw
    if ($text -match '(?s)<#(.*?)#>') { Write-Host $Matches[1].Trim() }
}

try {
switch ($Command.ToLower()) {
    'check'   { Invoke-Check }
    'daemon'  { Start-Daemon }
    'status'  { Show-Status }
    'add'     { Add-App $Rest }
    'remove'  { Remove-App $Rest }
    'rm'      { Remove-App $Rest }
    'pause'   { Set-Pause $Rest }
    'resume'  { Clear-Pause }
    'unpause' { Clear-Pause }
    'edit'    { Ensure-Config; Start-Process notepad.exe $ConfigFile }
    'log'     { Ensure-Config; if (Test-Path $LogFile) { Get-Content $LogFile -Tail 40 } else { Write-Host '(no log yet)' } }
    'help'    { Show-Help }
    default   { Fail "unknown command '$Command' (try: nightlock help)" }
}
} catch {
    Write-Host "nightlock: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
