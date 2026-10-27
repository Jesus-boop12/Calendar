<#
NightLock - closes distracting apps and blocks websites during your nightly lock windows.

  nightlock ui                 open the settings window
  nightlock start              turn the background checker on (installs it if needed)
  nightlock stop               turn it off: apps and websites are released immediately
  nightlock status             show schedules, blocked apps and sites, and the current state
  nightlock pause 10           lift the lock for 10 minutes (only if the config allows it)
  nightlock resume             end a pause early
  nightlock add chrome         block an app by process name (Task Manager > Details, without .exe)
  nightlock remove chrome      stop blocking an app
  nightlock site-add youtube.com      block a website in Chrome, Edge and Brave
  nightlock site-remove youtube.com   stop blocking a website
  nightlock release            remove website blocks right now (used by stop/uninstall)
  nightlock edit               open the config file in Notepad
  nightlock log                show recent log lines
  nightlock check / daemon     one enforcement pass / run forever (the scheduled task runs daemon)

Config lives in %LOCALAPPDATA%\NightLock\config.txt (see config.example.txt).
Test without waiting for night:  $env:NIGHTLOCK_DRY_RUN=1; $env:NIGHTLOCK_NOW="23:00 Mon"; nightlock check
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
$TaskName   = 'NightLock'
$CheckIntervalSeconds = 20
$DayOrder = 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'

# Browser policy keys that hold the URL blocklist. HKCU needs no admin rights.
$BrowserPolicyKeys = @(
    'HKCU:\Software\Policies\Google\Chrome\URLBlocklist',
    'HKCU:\Software\Policies\Microsoft\Edge\URLBlocklist',
    'HKCU:\Software\Policies\BraveSoftware\Brave\URLBlocklist'
)

New-Item -ItemType Directory -Force -Path $ConfigDir, $StateDir | Out-Null

$DefaultConfig = @'
# NightLock configuration. Times are 24-hour HH:MM, local time. A window may cross
# midnight: start 22:00 and end 06:00 means "until six the next morning".
# A night belongs to the day it starts on.

# Weeknights: nights that start on Sunday, Monday, Tuesday, Wednesday or Thursday.
weekday_enabled = yes
weekday_start = 22:00
weekday_end = 06:00

# Weekend nights: nights that start on Friday or Saturday.
weekend_enabled = yes
weekend_start = 23:30
weekend_end = 08:00

# Minutes before a lock starts to show a heads-up notification (0 disables).
warn_minutes = 10

# Allow "nightlock pause <minutes>" (or the Pause button)? no = no escape hatch.
allow_pause = yes
max_pause_minutes = 15

# Seconds an app gets to close politely before it is force-killed.
grace_seconds = 5

# Windows notification when apps are closed.
notify = yes

# Apps to block, by process name as in Task Manager > Details (without .exe).
app = Discord
app = steam

# Websites to block in Chrome, Edge and Brave during the lock window.
# A bare domain covers all its subdomains. Paths work too: reddit.com/r/all
site = youtube.com
site = tiktok.com
'@

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Fail([string]$Message) { throw $Message }

function Ensure-Config {
    if (-not (Test-Path $ConfigFile)) {
        Set-Content -Path $ConfigFile -Value $DefaultConfig -Encoding UTF8
        Write-Log "created default config at $ConfigFile"
    }
}

function Normalize-Site([string]$Site) {
    $s = $Site.Trim()
    $s = $s -replace '^[a-zA-Z]+://', ''
    $s = $s -replace '^www\.', ''
    $s = $s.TrimEnd('/')
    $slash = $s.IndexOf('/')
    if ($slash -ge 0) { $s = $s.Substring(0, $slash).ToLower() + $s.Substring($slash) } else { $s = $s.ToLower() }
    return $s
}

function Read-Config {
    $cfg = @{
        weekday_enabled = 'yes'; weekday_start = '22:00'; weekday_end = '06:00'
        weekend_enabled = 'yes'; weekend_start = '23:30'; weekend_end = '08:00'
        warn_minutes = 10; allow_pause = 'yes'; max_pause_minutes = 15
        grace_seconds = 5; notify = 'yes'
        apps = New-Object System.Collections.ArrayList
        sites = New-Object System.Collections.ArrayList
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
            'weekday_enabled'   { $cfg.weekday_enabled = $value.ToLower() }
            'weekday_start'     { $cfg.weekday_start = $value }
            'weekday_end'       { $cfg.weekday_end = $value }
            'weekend_enabled'   { $cfg.weekend_enabled = $value.ToLower() }
            'weekend_start'     { $cfg.weekend_start = $value }
            'weekend_end'       { $cfg.weekend_end = $value }
            # Keys from older configs: one window for every night.
            'start'             { $cfg.weekday_start = $value; $cfg.weekend_start = $value }
            'end'               { $cfg.weekday_end = $value; $cfg.weekend_end = $value }
            'days'              { }
            'warn_minutes'      { $cfg.warn_minutes = [int]$value }
            'allow_pause'       { $cfg.allow_pause = $value.ToLower() }
            'max_pause_minutes' { $cfg.max_pause_minutes = [int]$value }
            'grace_seconds'     { $cfg.grace_seconds = [int]$value }
            'notify'            { $cfg.notify = $value.ToLower() }
            'app'               { if ($value) { [void]$cfg.apps.Add(($value -replace '\.exe$', '')) } }
            'site'              { if ($value) { $n = Normalize-Site $value; if ($n) { [void]$cfg.sites.Add($n) } } }
            default             { Write-Log "config: unknown key '$key' ignored" }
        }
    }
    return $cfg
}

# Each schedule: name, enabled, start, end, and the days (by night start) it covers.
function Get-Schedules($cfg) {
    $list = @()
    $list += @{ name = 'weeknight'; enabled = ($cfg.weekday_enabled -eq 'yes'); start = $cfg.weekday_start; end = $cfg.weekday_end; days = @('Sun', 'Mon', 'Tue', 'Wed', 'Thu') }
    $list += @{ name = 'weekend';   enabled = ($cfg.weekend_enabled -eq 'yes'); start = $cfg.weekend_start; end = $cfg.weekend_end; days = @('Fri', 'Sat') }
    return $list
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

function Get-DayOffset([string]$Day, [int]$Offset) {
    $i = [array]::IndexOf($DayOrder, $Day)
    if ($i -lt 0) { $i = 0 }
    return $DayOrder[(($i + $Offset) % 7 + 7) % 7]
}

# True when this schedule's window is active right now.
function Test-ScheduleActive($s) {
    if (-not $s.enabled) { return $false }
    $now = Get-NowMinutes
    $start = ConvertTo-Minutes $s.start
    $end = ConvertTo-Minutes $s.end
    $today = Get-TodayName
    if ($start -lt $end) {
        return ($now -ge $start -and $now -lt $end -and ($s.days -contains $today))
    } elseif ($start -gt $end) {
        if ($now -ge $start) { return ($s.days -contains $today) }
        if ($now -lt $end)   { return ($s.days -contains (Get-DayOffset $today -1)) }
        return $false
    }
    return $false
}

function Get-ActiveSchedule($cfg) {
    foreach ($s in @(Get-Schedules $cfg)) { if (Test-ScheduleActive $s) { return $s } }
    return $null
}

function Test-InWindow($cfg) { return ($null -ne (Get-ActiveSchedule $cfg)) }

# The schedule that starts within warn_minutes from now, or $null.
function Get-WarningSchedule($cfg) {
    if ($cfg.warn_minutes -le 0) { return $null }
    $now = Get-NowMinutes
    $today = Get-TodayName
    foreach ($s in @(Get-Schedules $cfg)) {
        if (-not $s.enabled) { continue }
        if (-not ($s.days -contains $today)) { continue }
        $start = ConvertTo-Minutes $s.start
        if ($now -lt $start -and ($start - $now) -le $cfg.warn_minutes) { return $s }
    }
    return $null
}

function Get-MinutesUntilEnd($s) {
    $now = Get-NowMinutes
    $end = ConvertTo-Minutes $s.end
    if ($now -lt $end) { return $end - $now }
    return 1440 - $now + $end
}

# Human text for the next lock start, e.g. "Tonight at 22:00" or "Friday at 23:30".
function Get-NextLockText($cfg) {
    $now = Get-NowMinutes
    $today = Get-TodayName
    $best = $null
    for ($offset = 0; $offset -le 7; $offset++) {
        $day = Get-DayOffset $today $offset
        foreach ($s in @(Get-Schedules $cfg)) {
            if (-not $s.enabled) { continue }
            if (-not ($s.days -contains $day)) { continue }
            $start = ConvertTo-Minutes $s.start
            if ($offset -eq 0 -and $start -le $now) { continue }
            if ($null -eq $best -or $offset -lt $best.offset -or ($offset -eq $best.offset -and $start -lt $best.start)) {
                $best = @{ offset = $offset; start = $start; text = $s.start; day = $day }
            }
        }
        if ($best) { break }
    }
    if (-not $best) { return 'No schedule enabled' }
    if ($best.offset -eq 0) { if ($best.start -ge 720) { return "Tonight at $($best.text)" } else { return "Today at $($best.text)" } }
    if ($best.offset -eq 1) { return "Tomorrow at $($best.text)" }
    $full = @{ Mon = 'Monday'; Tue = 'Tuesday'; Wed = 'Wednesday'; Thu = 'Thursday'; Fri = 'Friday'; Sat = 'Saturday'; Sun = 'Sunday' }
    return "$($full[$best.day]) at $($best.text)"
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
    foreach ($p in Get-AppProcesses $App) {
        try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void]$p.CloseMainWindow() } } catch { }
    }
    $deadline = (Get-Date).AddSeconds($cfg.grace_seconds)
    while ((Get-Date) -lt $deadline -and (Get-AppProcesses $App).Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }
    $left = Get-AppProcesses $App
    if ($left.Count -gt 0) { $left | Stop-Process -Force -ErrorAction SilentlyContinue }
}

# --- website blocking through browser URLBlocklist policies ---
function Get-KeySites([string]$Key) {
    $props = Get-ItemProperty -Path $Key -ErrorAction SilentlyContinue
    if (-not $props) { return @() }
    $pairs = @()
    foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -match '^\d+$') { $pairs += @{ n = [int]$p.Name; v = [string]$p.Value } }
    }
    return @($pairs | Sort-Object { $_.n } | ForEach-Object { $_.v })
}

function Test-OurKey([string]$Key) {
    $m = Get-ItemProperty -Path $Key -Name 'NightLock' -ErrorAction SilentlyContinue
    return ($null -ne $m)
}

function Set-SiteBlocks([string[]]$Sites) {
    if ($DryRun) { Write-Host "[dry-run] would block sites: $($Sites -join ', ')"; return }
    foreach ($key in $BrowserPolicyKeys) {
        if (Test-Path $key) {
            if (-not (Test-OurKey $key)) { Write-Log "skipping $key - managed by something else"; continue }
            $current = Get-KeySites $key
            if (($current -join "`n") -eq ($Sites -join "`n")) { continue }
            Remove-Item -Path $key -Recurse -Force
        }
        New-Item -Path $key -Force | Out-Null
        New-ItemProperty -Path $key -Name 'NightLock' -Value 1 -PropertyType DWord -Force | Out-Null
        $i = 1
        foreach ($s in $Sites) {
            New-ItemProperty -Path $key -Name "$i" -Value $s -PropertyType String -Force | Out-Null
            $i++
        }
        Write-Log "blocked $($Sites.Count) site(s) via $key"
    }
}

function Clear-SiteBlocks {
    if ($DryRun) { Write-Host '[dry-run] would release site blocks'; return }
    foreach ($key in $BrowserPolicyKeys) {
        if ((Test-Path $key) -and (Test-OurKey $key)) {
            Remove-Item -Path $key -Recurse -Force
            Write-Log "released site blocks at $key"
        }
    }
}

function Test-SitesBlocked {
    foreach ($key in $BrowserPolicyKeys) { if ((Test-Path $key) -and (Test-OurKey $key)) { return $true } }
    return $false
}

# --- background checker process management ---
function Get-DaemonProcesses {
    $found = @()
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction Stop
        foreach ($p in $procs) {
            if ($p.ProcessId -eq $PID) { continue }
            if ($p.CommandLine -and $p.CommandLine -match 'nightlock\.ps1' -and $p.CommandLine -match '\bdaemon\b') { $found += $p }
        }
    } catch { }
    return $found
}

function Test-DaemonRunning { return ((Get-DaemonProcesses).Count -gt 0) }

function Stop-Daemons {
    foreach ($p in Get-DaemonProcesses) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
}

# ---------- commands ----------
function Invoke-Check {
    $cfg = Read-Config
    $active = Get-ActiveSchedule $cfg

    if ($active) {
        Remove-Item $WarnedFile -Force -ErrorAction SilentlyContinue
        if (Get-PauseUntil) { Clear-SiteBlocks; return }

        if ($cfg.sites.Count -gt 0) { Set-SiteBlocks $cfg.sites } else { Clear-SiteBlocks }

        $closed = @()
        foreach ($app in $cfg.apps) {
            if ((Get-AppProcesses $app).Count -gt 0) {
                Stop-App $app $cfg
                $closed += $app
                Write-Log "closed $app ($($active.name) window $($active.start)-$($active.end))"
            }
        }
        if ($closed.Count -gt 0) {
            Send-Toast 'NightLock' ("Closed {0}. Unlocks at {1}." -f ($closed -join ', '), $active.end) $cfg
        }
        return
    }

    Clear-SiteBlocks

    $warn = Get-WarningSchedule $cfg
    if ($warn) {
        $today = Get-Date -Format 'yyyy-MM-dd'
        $warned = ''
        if (Test-Path $WarnedFile) { $warned = (Get-Content $WarnedFile -Raw).Trim() }
        if ($warned -ne $today) {
            Send-Toast 'NightLock' "Distracting apps and sites lock at $($warn.start). Wrap up what you're doing." $cfg
            Write-Log "sent warning for $($warn.start) lock"
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

function Get-State {
    $cfg = Read-Config
    $active = Get-ActiveSchedule $cfg
    $pause = Get-PauseUntil
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    $pausedUntil = $null
    if ($pause) { $pausedUntil = $pause.ToString('HH:mm') }
    $activeEnd = $null
    $activeName = $null
    if ($active) { $activeEnd = $active.end; $activeName = $active.name }
    $taskEnabled = $false
    if ($task) { $taskEnabled = ($task.State -ne 'Disabled') }
    return @{
        locked         = [bool]$active
        active_end     = $activeEnd
        active_name    = $activeName
        paused_until   = $pausedUntil
        next_lock      = (Get-NextLockText $cfg)
        task_installed = [bool]$task
        task_enabled   = $taskEnabled
        daemon_running = (Test-DaemonRunning)
        sites_blocked  = (Test-SitesBlocked)
        allow_pause    = ($cfg.allow_pause -eq 'yes')
        max_pause      = $cfg.max_pause_minutes
        apps           = $cfg.apps.Count
        sites          = $cfg.sites.Count
    }
}

function Show-Status {
    $cfg = Read-Config
    $st = Get-State
    Write-Host 'NightLock'
    foreach ($s in @(Get-Schedules $cfg)) {
        $flag = 'off'
        if ($s.enabled) { $flag = "$($s.start) -> $($s.end)" }
        Write-Host ("  {0,-10}: {1}  (nights starting {2})" -f $s.name, $flag, ($s.days -join ','))
    }
    Write-Host "  config    : $ConfigFile"
    Write-Host "  log       : $LogFile"
    if ($st.locked) {
        if ($st.paused_until) { Write-Host "  state     : PAUSED until $($st.paused_until)" }
        else { Write-Host "  state     : LOCKED ($(Get-MinutesUntilEnd (Get-ActiveSchedule $cfg)) min left)" }
    } else {
        Write-Host "  state     : unlocked. Next lock: $($st.next_lock)"
    }
    if (-not $st.task_installed) { $checker = 'NOT installed (run: nightlock start)' }
    elseif (-not $st.task_enabled) { $checker = 'STOPPED (run: nightlock start)' }
    elseif ($st.daemon_running) { $checker = 'running' }
    else { $checker = 'enabled but not running yet (starts within 5 min, or run: nightlock start)' }
    Write-Host "  checker   : $checker"
    Write-Host '  apps      :'
    foreach ($app in $cfg.apps) {
        if ((Get-AppProcesses $app).Count -gt 0) { Write-Host "    - $app (running)" } else { Write-Host "    - $app" }
    }
    Write-Host "  sites     : $($cfg.sites -join ', ')"
}

function Add-ConfigLine([string]$Line) {
    Ensure-Config
    $raw = Get-Content -Path $ConfigFile -Raw -Encoding UTF8
    if ($raw -and -not $raw.EndsWith("`n")) { Add-Content -Path $ConfigFile -Value '' -Encoding UTF8 }
    Add-Content -Path $ConfigFile -Value $Line -Encoding UTF8
}

function Remove-ConfigLines([string]$Pattern) {
    Ensure-Config
    $lines = @(Get-Content -Path $ConfigFile -Encoding UTF8)
    $kept = @($lines | Where-Object { $_ -notmatch $Pattern })
    if ($kept.Count -eq $lines.Count) { return $false }
    Set-Content -Path $ConfigFile -Value $kept -Encoding UTF8
    return $true
}

function Add-App([string[]]$Names) {
    if (-not $Names -or $Names.Count -eq 0) { Fail 'usage: nightlock add <processname>' }
    $cfg = Read-Config
    foreach ($n in $Names) {
        $name = $n -replace '\.exe$', ''
        if ($cfg.apps -contains $name) { Write-Host "$name is already blocked"; continue }
        Add-ConfigLine "app = $name"
        [void]$cfg.apps.Add($name)
        Write-Host "added $name"
    }
}

function Remove-App([string[]]$Names) {
    if (-not $Names -or $Names.Count -eq 0) { Fail 'usage: nightlock remove <processname>' }
    foreach ($n in $Names) {
        $name = $n -replace '\.exe$', ''
        $pattern = '^\s*app\s*=\s*' + [regex]::Escape($name) + '(\.exe)?\s*$'
        if (Remove-ConfigLines $pattern) { Write-Host "removed $name" } else { Write-Host "$name was not in the list" }
    }
}

function Add-Site([string[]]$Sites) {
    if (-not $Sites -or $Sites.Count -eq 0) { Fail 'usage: nightlock site-add <domain>' }
    $cfg = Read-Config
    foreach ($raw in $Sites) {
        $site = Normalize-Site $raw
        if (-not $site) { continue }
        if ($cfg.sites -contains $site) { Write-Host "$site is already blocked"; continue }
        Add-ConfigLine "site = $site"
        [void]$cfg.sites.Add($site)
        Write-Host "added $site"
    }
}

function Remove-Site([string[]]$Sites) {
    if (-not $Sites -or $Sites.Count -eq 0) { Fail 'usage: nightlock site-remove <domain>' }
    foreach ($raw in $Sites) {
        $site = Normalize-Site $raw
        $pattern = '^\s*site\s*=\s*(https?://)?(www\.)?' + [regex]::Escape($site) + '/?\s*$'
        if (Remove-ConfigLines $pattern) { Write-Host "removed $site" } else { Write-Host "$site was not in the list" }
    }
}

function Set-Pause([string[]]$Args2) {
    $cfg = Read-Config
    if ($cfg.allow_pause -ne 'yes') { Fail "pausing is disabled in $ConfigFile (allow_pause = no)" }
    $minutes = 0
    if (-not $Args2 -or -not [int]::TryParse($Args2[0], [ref]$minutes) -or $minutes -lt 1) { Fail 'usage: nightlock pause <minutes>' }
    if ($minutes -gt $cfg.max_pause_minutes) { Fail "max pause is $($cfg.max_pause_minutes) minutes (max_pause_minutes in config)" }
    Set-Content -Path $PauseFile -Value (Get-Date).AddMinutes($minutes).ToString('o')
    Clear-SiteBlocks
    Write-Log "paused for $minutes min"
    Write-Host "NightLock paused for $minutes minutes."
}

function Clear-Pause {
    Remove-Item $PauseFile -Force -ErrorAction SilentlyContinue
    Write-Log 'pause ended manually'
    Write-Host 'NightLock resumed.'
}

function Start-NightLock {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $task) {
        $installer = Join-Path $PSScriptRoot 'install.ps1'
        if (-not (Test-Path $installer)) { Fail "install.ps1 was not found next to nightlock.ps1 ($PSScriptRoot)" }
        & $installer -Quiet
    } else {
        Enable-ScheduledTask -TaskName $TaskName | Out-Null
        Start-ScheduledTask -TaskName $TaskName
    }
    Write-Log 'started by user'
    Write-Host 'NightLock started. The background checker is on.'
}

function Stop-NightLock {
    Disable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Out-Null
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Stop-Daemons
    Clear-SiteBlocks
    Write-Log 'stopped by user'
    Write-Host 'NightLock stopped. Apps and websites are no longer blocked. Run "nightlock start" to turn it back on.'
}

function Open-UI {
    $ui = Join-Path $PSScriptRoot 'nightlock-ui.ps1'
    if (-not (Test-Path $ui)) { Fail "nightlock-ui.ps1 was not found next to nightlock.ps1" }
    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$ui`"")
}

function Show-Help {
    $text = Get-Content -Path $PSCommandPath -Raw
    if ($text -match '(?s)<#(.*?)#>') { Write-Host $Matches[1].Trim() }
}

try {
    switch ($Command.ToLower()) {
        'check'       { Invoke-Check }
        'daemon'      { Start-Daemon }
        'state'       { Get-State | ConvertTo-Json -Compress }
        'status'      { Show-Status }
        'start'       { Start-NightLock }
        'stop'        { Stop-NightLock }
        'ui'          { Open-UI }
        'add'         { Add-App $Rest }
        'remove'      { Remove-App $Rest }
        'rm'          { Remove-App $Rest }
        'site-add'    { Add-Site $Rest }
        'site-remove' { Remove-Site $Rest }
        'release'     { Clear-SiteBlocks; Write-Host 'Website blocks released.' }
        'pause'       { Set-Pause $Rest }
        'resume'      { Clear-Pause }
        'unpause'     { Clear-Pause }
        'edit'        { Ensure-Config; Start-Process notepad.exe $ConfigFile }
        'log'         { Ensure-Config; if (Test-Path $LogFile) { Get-Content $LogFile -Tail 40 } else { Write-Host '(no log yet)' } }
        'help'        { Show-Help }
        default       { Fail "unknown command '$Command' (try: nightlock help)" }
    }
} catch {
    Write-Host "nightlock: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
