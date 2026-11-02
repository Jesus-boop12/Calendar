# NightLock settings window. Opened by NightLock.cmd, the Start Menu shortcut, or "nightlock ui".
# Reads and writes %LOCALAPPDATA%\NightLock\config.txt and talks to nightlock.ps1 for start/stop/state.
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Drawing

$CoreScript = Join-Path $PSScriptRoot 'nightlock.ps1'
$Installer  = Join-Path $PSScriptRoot 'install.ps1'
if ($env:NIGHTLOCK_CONFIG_DIR) { $ConfigDir = $env:NIGHTLOCK_CONFIG_DIR } else { $ConfigDir = Join-Path $env:LOCALAPPDATA 'NightLock' }
$ConfigFile = Join-Path $ConfigDir 'config.txt'
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

# A bindable row for the app list.
Add-Type -TypeDefinition @'
using System.ComponentModel;
public class AppEntry : INotifyPropertyChanged
{
    public string Name { get; set; }
    public string ProcessName { get; set; }
    public string Path { get; set; }
    public string Source { get; set; }
    public object Icon { get; set; }
    private bool _running;
    public bool IsRunning { get { return _running; } set { _running = value; Status = value ? "Running now" : ""; } }
    public string Status { get; set; }
    private bool _blocked;
    public bool Blocked { get { return _blocked; } set { if (_blocked != value) { _blocked = value; Raise("Blocked"); } } }
    public event PropertyChangedEventHandler PropertyChanged;
    private void Raise(string name) { var h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(name)); }
}
'@

# ---------- config ----------
function Read-Config {
    $cfg = @{
        weekday_enabled = 'yes'; weekday_start = '22:00'; weekday_end = '06:00'
        weekend_enabled = 'yes'; weekend_start = '23:30'; weekend_end = '08:00'
        warn_minutes = 10; allow_pause = 'yes'; max_pause_minutes = 15; grace_seconds = 5; notify = 'yes'
        apps = New-Object System.Collections.ArrayList
        sites = New-Object System.Collections.ArrayList
    }
    if (-not (Test-Path $ConfigFile)) {
        # Let the core script create its default config.
        & $CoreScript state | Out-Null
    }
    if (-not (Test-Path $ConfigFile)) { return $cfg }
    foreach ($raw in Get-Content -Path $ConfigFile -Encoding UTF8) {
        $line = ($raw -split '#', 2)[0].Trim()
        if (-not $line) { continue }
        $parts = $line -split '=', 2
        if ($parts.Count -ne 2) { continue }
        $key = $parts[0].Trim().ToLower(); $value = $parts[1].Trim()
        switch ($key) {
            'app'   { if ($value) { [void]$cfg.apps.Add(($value -replace '\.exe$', '')) } }
            'site'  { if ($value) { [void]$cfg.sites.Add($value) } }
            'start' { $cfg.weekday_start = $value; $cfg.weekend_start = $value }
            'end'   { $cfg.weekday_end = $value; $cfg.weekend_end = $value }
            'days'  { }
            default { if ($cfg.ContainsKey($key)) { $cfg[$key] = $value } }
        }
    }
    foreach ($k in 'warn_minutes', 'max_pause_minutes', 'grace_seconds') { $cfg[$k] = [int]$cfg[$k] }
    return $cfg
}

function Write-Config($cfg) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# NightLock configuration. Edit here or in the NightLock window. Times are 24-hour HH:MM.')
    [void]$sb.AppendLine('# A window may cross midnight. A night belongs to the day it starts on.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Weeknights: nights starting Sunday to Thursday.')
    [void]$sb.AppendLine("weekday_enabled = $($cfg.weekday_enabled)")
    [void]$sb.AppendLine("weekday_start = $($cfg.weekday_start)")
    [void]$sb.AppendLine("weekday_end = $($cfg.weekday_end)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Weekend nights: nights starting Friday or Saturday.')
    [void]$sb.AppendLine("weekend_enabled = $($cfg.weekend_enabled)")
    [void]$sb.AppendLine("weekend_start = $($cfg.weekend_start)")
    [void]$sb.AppendLine("weekend_end = $($cfg.weekend_end)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("warn_minutes = $($cfg.warn_minutes)")
    [void]$sb.AppendLine("allow_pause = $($cfg.allow_pause)")
    [void]$sb.AppendLine("max_pause_minutes = $($cfg.max_pause_minutes)")
    [void]$sb.AppendLine("grace_seconds = $($cfg.grace_seconds)")
    [void]$sb.AppendLine("notify = $($cfg.notify)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Apps to block, by process name (Task Manager > Details, without .exe).')
    foreach ($a in $cfg.apps) { [void]$sb.AppendLine("app = $a") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('# Websites blocked in Chrome, Edge and Brave during the lock window.')
    foreach ($s in $cfg.sites) { [void]$sb.AppendLine("site = $s") }
    Set-Content -Path $ConfigFile -Value $sb.ToString() -Encoding UTF8
}

# ---------- icons ----------
function Get-IconFromExe([string]$ExePath) {
    try {
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($ExePath)
        if (-not $ico) { return $null }
        $bmp = $ico.ToBitmap()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $ms.Position = 0
        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit()
        $img.StreamSource = $ms
        $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $img.EndInit()
        $img.Freeze()
        $bmp.Dispose(); $ico.Dispose()
        return $img
    } catch { return $null }
}

function Get-IconFromImageFile([string]$ImagePath) {
    try {
        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit()
        $img.UriSource = New-Object System.Uri $ImagePath
        $img.DecodePixelWidth = 32
        $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $img.EndInit()
        $img.Freeze()
        return $img
    } catch { return $null }
}

# ---------- app discovery ----------
$SkipExe = '^(unins|uninst|setup|install|update|updater|crash|report|helper|repair|launcher_helper|vcredist|dxsetup)'
$SkipNames = @('powershell', 'pwsh', 'cmd', 'explorer', 'wscript', 'cscript', 'conhost', 'notepad', 'taskmgr', 'regedit', 'mmc', 'control')

function Add-Found($found, [string]$Name, [string]$ExePath, [string]$Source, $Icon) {
    if (-not $ExePath) { return }
    $proc = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    if (-not $proc) { return }
    if ($proc -match $SkipExe) { return }
    if ($SkipNames -contains $proc.ToLower()) { return }
    if ($ExePath -like "$env:windir\*") { return }
    $key = $proc.ToLower()
    if ($found.ContainsKey($key)) {
        $e = $found[$key]
        if (-not $e.Icon -and $Icon) { $e.Icon = $Icon }
        if ($Source -eq 'Start Menu' -and $e.Source -ne 'Start Menu') { $e.Name = $Name; $e.Source = $Source }
        return
    }
    $e = New-Object AppEntry
    $e.Name = $Name; $e.ProcessName = $proc; $e.Path = $ExePath; $e.Source = $Source; $e.Icon = $Icon
    $found[$key] = $e
}

function Find-StartMenuApps($found) {
    $dirs = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
    )
    $shell = New-Object -ComObject WScript.Shell
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($lnk in Get-ChildItem -Path $dir -Filter *.lnk -Recurse -ErrorAction SilentlyContinue) {
            try {
                $target = $shell.CreateShortcut($lnk.FullName).TargetPath
                if (-not $target) { continue }
                $target = [Environment]::ExpandEnvironmentVariables($target)
                if ($target -notmatch '\.exe$') { continue }
                if (-not (Test-Path $target)) { continue }
                if ($lnk.BaseName -match '(?i)uninstall|readme|help|documentation|website') { continue }
                Add-Found $found $lnk.BaseName $target 'Start Menu' (Get-IconFromExe $target)
            } catch { }
        }
    }
}

function Find-StoreApps($found) {
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) { return }
    try { $pkgs = @(Get-AppxPackage -ErrorAction Stop | Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage -and $_.SignatureKind -eq 'Store' }) } catch { return }
    foreach ($pkg in $pkgs) {
        try {
            $manifestPath = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
            if (-not (Test-Path $manifestPath)) { continue }
            [xml]$m = Get-Content -Path $manifestPath -Raw
            $app = $m.Package.Applications.Application
            if ($app -is [array]) { $app = $app[0] }
            if (-not $app -or -not $app.Executable) { continue }
            $exe = Join-Path $pkg.InstallLocation $app.Executable
            $name = $m.Package.Properties.DisplayName
            if (-not $name -or $name -like 'ms-resource:*') { $name = ($pkg.Name -split '\.')[-1] }
            $icon = $null
            $logo = $m.Package.Properties.Logo
            if ($app.VisualElements -and $app.VisualElements.Square44x44Logo) { $logo = $app.VisualElements.Square44x44Logo }
            if ($logo) {
                $logoDir = Join-Path $pkg.InstallLocation ([System.IO.Path]::GetDirectoryName($logo))
                $base = [System.IO.Path]::GetFileNameWithoutExtension($logo)
                $candidates = @(Get-ChildItem -Path $logoDir -Filter "$base*.png" -ErrorAction SilentlyContinue | Sort-Object Length)
                if ($candidates.Count -gt 0) {
                    $pick = $candidates | Where-Object { $_.Name -match 'scale-100|targetsize-48' } | Select-Object -First 1
                    if (-not $pick) { $pick = $candidates[[int]($candidates.Count / 2)] }
                    $icon = Get-IconFromImageFile $pick.FullName
                }
            }
            if (-not $icon -and (Test-Path $exe)) { $icon = Get-IconFromExe $exe }
            Add-Found $found $name $exe 'Microsoft Store' $icon
        } catch { }
    }
}

function Find-RunningApps($found) {
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            if ($p.MainWindowHandle -eq [IntPtr]::Zero) { continue }
            $path = $p.Path
            if (-not $path) { continue }
            $name = $p.Description
            if (-not $name) { $name = $p.ProcessName }
            Add-Found $found $name $path 'Running' (Get-IconFromExe $path)
        } catch { }
    }
}

function Discover-Apps($cfg) {
    $found = @{}
    Find-StartMenuApps $found
    Find-StoreApps $found
    Find-RunningApps $found
    $running = @{}
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) { $running[$p.ProcessName.ToLower()] = $true }
    foreach ($a in $cfg.apps) {
        $k = $a.ToLower()
        if (-not $found.ContainsKey($k)) {
            $e = New-Object AppEntry
            $e.Name = $a; $e.ProcessName = $a; $e.Source = 'Added by you'
            $found[$k] = $e
        }
        $found[$k].Blocked = $true
    }
    foreach ($e in $found.Values) { $e.IsRunning = $running.ContainsKey($e.ProcessName.ToLower()) }
    return @($found.Values)
}

# ---------- window ----------
[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NightLock" Width="900" Height="640" MinWidth="760" MinHeight="540"
        WindowStartupLocation="CenterScreen" Background="#F3F4F6" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="White" CornerRadius="8" Padding="16" Margin="0,0,0,12" BorderBrush="#E5E7EB" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Name="StateText" FontSize="22" FontWeight="SemiBold" Text="NightLock"/>
          <TextBlock Name="DetailText" Foreground="#4B5563" Margin="0,4,0,0" Text="Loading..." TextWrapping="Wrap"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Button Name="StartButton" Content="Start" Width="100" Height="36" Margin="0,0,8,0" Background="#16A34A" Foreground="White" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand"/>
          <Button Name="StopButton" Content="Stop" Width="100" Height="36" Margin="0,0,8,0" Background="#DC2626" Foreground="White" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand"/>
          <Button Name="PauseButton" Content="Pause 15 min" Width="120" Height="36" Cursor="Hand"/>
        </StackPanel>
      </Grid>
    </Border>

    <TabControl Grid.Row="1" Name="Tabs" Padding="0" BorderBrush="#E5E7EB">
      <TabItem Header="  Apps  ">
        <Grid Margin="12">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" TextWrapping="Wrap" Foreground="#4B5563" Margin="0,0,0,8"
                     Text="Tick the apps NightLock should close during the lock window. Apps are found from your Start Menu, the Microsoft Store and what is running now."/>
          <DockPanel Grid.Row="1">
            <Button Name="RefreshButton" Content="Rescan" Width="90" Height="30" DockPanel.Dock="Right" Margin="8,0,0,0"/>
            <TextBox Name="SearchBox" Height="30" VerticalContentAlignment="Center" Padding="6,0" ToolTip="Type to search"/>
          </DockPanel>
          <ListView Name="AppList" Grid.Row="2" Margin="0,8,0,8" BorderBrush="#E5E7EB">
            <ListView.View>
              <GridView>
                <GridViewColumn Header="Block" Width="56">
                  <GridViewColumn.CellTemplate>
                    <DataTemplate>
                      <CheckBox IsChecked="{Binding Blocked, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </DataTemplate>
                  </GridViewColumn.CellTemplate>
                </GridViewColumn>
                <GridViewColumn Header="" Width="40">
                  <GridViewColumn.CellTemplate>
                    <DataTemplate>
                      <Image Source="{Binding Icon}" Width="24" Height="24" Margin="2"/>
                    </DataTemplate>
                  </GridViewColumn.CellTemplate>
                </GridViewColumn>
                <GridViewColumn Header="App" Width="320" DisplayMemberBinding="{Binding Name}"/>
                <GridViewColumn Header="Process" Width="170" DisplayMemberBinding="{Binding ProcessName}"/>
                <GridViewColumn Header="Status" Width="110" DisplayMemberBinding="{Binding Status}"/>
                <GridViewColumn Header="Found in" Width="120" DisplayMemberBinding="{Binding Source}"/>
              </GridView>
            </ListView.View>
          </ListView>
          <DockPanel Grid.Row="3">
            <Button Name="AddAppButton" Content="Add" Width="90" Height="30" DockPanel.Dock="Right" Margin="8,0,0,0"/>
            <TextBlock Text="Not listed? Type its process name:" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#4B5563"/>
            <TextBox Name="ManualAppBox" Height="30" VerticalContentAlignment="Center" Padding="6,0" ToolTip="e.g. chrome (Task Manager > Details, without .exe)"/>
          </DockPanel>
        </Grid>
      </TabItem>

      <TabItem Header="  Websites  ">
        <Grid Margin="12">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Grid.Row="0" TextWrapping="Wrap" Foreground="#4B5563"
                     Text="Websites blocked in Chrome, Edge and Brave during the lock window. One per line. A domain such as youtube.com also covers its subdomains. You can paste full links, or block a section: reddit.com/r/all"/>
          <TextBox Name="SitesBox" Grid.Row="1" Margin="0,10,0,10" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="14" Padding="8"/>
          <TextBlock Grid.Row="2" TextWrapping="Wrap" Foreground="#6B7280" FontSize="12"
                     Text="How it works: during the lock, NightLock sets the browser's URL blocklist policy for your Windows account, and removes it when the lock ends or you press Stop. Chrome may show 'managed by your organization' while a lock is active. Pages already open keep working until you navigate or reload."/>
        </Grid>
      </TabItem>

      <TabItem Header="  Schedule  ">
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel Margin="12">
            <GroupBox Header="Weeknights  (nights starting Sunday, Monday, Tuesday, Wednesday, Thursday)" Padding="12" Margin="0,0,0,12">
              <StackPanel Orientation="Horizontal">
                <CheckBox Name="WeekdayEnabled" Content="On" VerticalAlignment="Center" Margin="0,0,20,0" FontWeight="SemiBold"/>
                <TextBlock Text="Lock from" VerticalAlignment="Center"/>
                <ComboBox Name="WeekdayStartH" Width="60" Margin="8,0,2,0"/>
                <TextBlock Text=":" VerticalAlignment="Center"/>
                <ComboBox Name="WeekdayStartM" Width="60" Margin="2,0,20,0"/>
                <TextBlock Text="until" VerticalAlignment="Center"/>
                <ComboBox Name="WeekdayEndH" Width="60" Margin="8,0,2,0"/>
                <TextBlock Text=":" VerticalAlignment="Center"/>
                <ComboBox Name="WeekdayEndM" Width="60" Margin="2,0,0,0"/>
              </StackPanel>
            </GroupBox>
            <GroupBox Header="Weekend nights  (nights starting Friday and Saturday)" Padding="12" Margin="0,0,0,12">
              <StackPanel Orientation="Horizontal">
                <CheckBox Name="WeekendEnabled" Content="On" VerticalAlignment="Center" Margin="0,0,20,0" FontWeight="SemiBold"/>
                <TextBlock Text="Lock from" VerticalAlignment="Center"/>
                <ComboBox Name="WeekendStartH" Width="60" Margin="8,0,2,0"/>
                <TextBlock Text=":" VerticalAlignment="Center"/>
                <ComboBox Name="WeekendStartM" Width="60" Margin="2,0,20,0"/>
                <TextBlock Text="until" VerticalAlignment="Center"/>
                <ComboBox Name="WeekendEndH" Width="60" Margin="8,0,2,0"/>
                <TextBlock Text=":" VerticalAlignment="Center"/>
                <ComboBox Name="WeekendEndM" Width="60" Margin="2,0,0,0"/>
              </StackPanel>
            </GroupBox>
            <GroupBox Header="Options" Padding="12" Margin="0,0,0,12">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <TextBlock Text="Warn me" VerticalAlignment="Center"/>
                  <TextBox Name="WarnBox" Width="50" Margin="8,0" HorizontalContentAlignment="Center"/>
                  <TextBlock Text="minutes before a lock starts (0 = no warning)" VerticalAlignment="Center"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <CheckBox Name="AllowPause" Content="Allow the Pause button, up to" VerticalAlignment="Center"/>
                  <TextBox Name="MaxPauseBox" Width="50" Margin="8,0" HorizontalContentAlignment="Center"/>
                  <TextBlock Text="minutes at a time" VerticalAlignment="Center"/>
                </StackPanel>
                <CheckBox Name="NotifyBox" Content="Show a notification when apps are closed"/>
              </StackPanel>
            </GroupBox>
            <TextBlock TextWrapping="Wrap" Foreground="#6B7280" FontSize="12"
                       Text="Times are 24-hour. A window may cross midnight: 22:00 until 06:00 locks from ten at night until six the next morning. Press Save changes to apply. The background checker picks up changes within 20 seconds."/>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
    </TabControl>

    <DockPanel Grid.Row="2" Margin="0,12,0,0">
      <Button Name="SaveButton" Content="Save changes" Width="150" Height="36" DockPanel.Dock="Right" Background="#2563EB" Foreground="White" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand"/>
      <Button Name="FolderButton" Content="Open config folder" Width="150" Height="36" DockPanel.Dock="Right" Margin="0,0,8,0"/>
      <TextBlock Name="SaveStatus" VerticalAlignment="Center" Foreground="#4B5563"/>
    </DockPanel>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

$ui = @{}
foreach ($name in 'StateText', 'DetailText', 'StartButton', 'StopButton', 'PauseButton', 'RefreshButton', 'SearchBox', 'AppList',
                  'AddAppButton', 'ManualAppBox', 'SitesBox', 'WeekdayEnabled', 'WeekdayStartH', 'WeekdayStartM', 'WeekdayEndH', 'WeekdayEndM',
                  'WeekendEnabled', 'WeekendStartH', 'WeekendStartM', 'WeekendEndH', 'WeekendEndM', 'WarnBox', 'MaxPauseBox', 'AllowPause',
                  'NotifyBox', 'SaveButton', 'FolderButton', 'SaveStatus') {
    $ui[$name] = $Window.FindName($name)
}

# ---------- helpers bound to the window ----------
$script:Apps = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$script:Config = Read-Config
$script:Scanned = $false

function Fill-TimeCombos {
    foreach ($n in 'WeekdayStartH', 'WeekdayEndH', 'WeekendStartH', 'WeekendEndH') {
        $ui[$n].Items.Clear()
        for ($h = 0; $h -lt 24; $h++) { [void]$ui[$n].Items.Add($h.ToString('00')) }
    }
    foreach ($n in 'WeekdayStartM', 'WeekdayEndM', 'WeekendStartM', 'WeekendEndM') {
        $ui[$n].Items.Clear()
        for ($m = 0; $m -lt 60; $m += 5) { [void]$ui[$n].Items.Add($m.ToString('00')) }
    }
}

function Set-TimeCombo([string]$Prefix, [string]$Time) {
    if ($Time -notmatch '^(\d{1,2}):(\d{2})$') { $Time = '22:00' }
    $h = ([int]$Matches[1]).ToString('00'); $m = ([int]$Matches[2]).ToString('00')
    $hc = $ui["${Prefix}H"]; $mc = $ui["${Prefix}M"]
    if (-not $mc.Items.Contains($m)) { [void]$mc.Items.Add($m) }
    $hc.SelectedItem = $h; $mc.SelectedItem = $m
}

function Get-TimeCombo([string]$Prefix) {
    $h = $ui["${Prefix}H"].SelectedItem; $m = $ui["${Prefix}M"].SelectedItem
    if (-not $h) { $h = '22' }
    if (-not $m) { $m = '00' }
    return "${h}:${m}"
}

function Load-ConfigIntoForm {
    $c = $script:Config
    $ui.WeekdayEnabled.IsChecked = ($c.weekday_enabled -eq 'yes')
    $ui.WeekendEnabled.IsChecked = ($c.weekend_enabled -eq 'yes')
    Set-TimeCombo 'WeekdayStart' $c.weekday_start
    Set-TimeCombo 'WeekdayEnd'   $c.weekday_end
    Set-TimeCombo 'WeekendStart' $c.weekend_start
    Set-TimeCombo 'WeekendEnd'   $c.weekend_end
    $ui.WarnBox.Text = [string]$c.warn_minutes
    $ui.AllowPause.IsChecked = ($c.allow_pause -eq 'yes')
    $ui.MaxPauseBox.Text = [string]$c.max_pause_minutes
    $ui.NotifyBox.IsChecked = ($c.notify -eq 'yes')
    $ui.SitesBox.Text = ($c.sites -join "`r`n")
}

function Get-IntBox($box, [int]$Default, [int]$Min, [int]$Max) {
    $v = 0
    if (-not [int]::TryParse($box.Text.Trim(), [ref]$v)) { $v = $Default }
    if ($v -lt $Min) { $v = $Min }
    if ($v -gt $Max) { $v = $Max }
    $box.Text = [string]$v
    return $v
}

function Save-Form {
    $c = $script:Config
    if ($ui.WeekdayEnabled.IsChecked) { $c.weekday_enabled = 'yes' } else { $c.weekday_enabled = 'no' }
    if ($ui.WeekendEnabled.IsChecked) { $c.weekend_enabled = 'yes' } else { $c.weekend_enabled = 'no' }
    $c.weekday_start = Get-TimeCombo 'WeekdayStart'
    $c.weekday_end   = Get-TimeCombo 'WeekdayEnd'
    $c.weekend_start = Get-TimeCombo 'WeekendStart'
    $c.weekend_end   = Get-TimeCombo 'WeekendEnd'
    foreach ($pair in @(@($c.weekday_enabled, $c.weekday_start, $c.weekday_end, 'Weeknights'), @($c.weekend_enabled, $c.weekend_start, $c.weekend_end, 'Weekend nights'))) {
        if ($pair[0] -eq 'yes' -and $pair[1] -eq $pair[2]) {
            [System.Windows.MessageBox]::Show("$($pair[3]): the start and end time are the same, so that window would never lock. Pick different times or turn it off.", 'NightLock', 'OK', 'Warning') | Out-Null
            return $false
        }
    }
    $c.warn_minutes = Get-IntBox $ui.WarnBox 10 0 180
    if ($ui.AllowPause.IsChecked) { $c.allow_pause = 'yes' } else { $c.allow_pause = 'no' }
    $c.max_pause_minutes = Get-IntBox $ui.MaxPauseBox 15 1 240
    if ($ui.NotifyBox.IsChecked) { $c.notify = 'yes' } else { $c.notify = 'no' }

    $c.apps.Clear()
    foreach ($e in $script:Apps) { if ($e.Blocked -and -not ($c.apps -contains $e.ProcessName)) { [void]$c.apps.Add($e.ProcessName) } }

    $c.sites.Clear()
    foreach ($line in ($ui.SitesBox.Text -split "`r?`n")) {
        $s = $line.Trim()
        if (-not $s -or $s.StartsWith('#')) { continue }
        $s = $s -replace '^[a-zA-Z]+://', ''
        $s = $s -replace '^www\.', ''
        $s = $s.TrimEnd('/')
        $slash = $s.IndexOf('/')
        if ($slash -ge 0) { $s = $s.Substring(0, $slash).ToLower() + $s.Substring($slash) } else { $s = $s.ToLower() }
        if ($s -and -not ($c.sites -contains $s)) { [void]$c.sites.Add($s) }
    }
    $ui.SitesBox.Text = ($c.sites -join "`r`n")

    Write-Config $c
    $ui.SaveStatus.Text = "Saved at $(Get-Date -Format 'HH:mm:ss'). $($c.apps.Count) app(s), $($c.sites.Count) site(s)."
    return $true
}

function Get-State {
    try {
        $json = & $CoreScript state 2>$null | Out-String
        return ($json | ConvertFrom-Json)
    } catch { return $null }
}

function Update-Status {
    $st = Get-State
    if (-not $st) { $ui.StateText.Text = 'NightLock'; $ui.DetailText.Text = 'Could not read state.'; return }
    $on = ($st.task_installed -and $st.task_enabled)
    if (-not $on) {
        $ui.StateText.Text = 'NightLock is OFF'
        $ui.StateText.Foreground = '#6B7280'
        $ui.DetailText.Text = 'Nothing is blocked. Press Start to turn on the background checker.'
    } elseif ($st.locked -and $st.paused_until) {
        $ui.StateText.Text = "Paused until $($st.paused_until)"
        $ui.StateText.Foreground = '#D97706'
        $ui.DetailText.Text = "The lock resumes automatically at $($st.paused_until)."
    } elseif ($st.locked) {
        $ui.StateText.Text = "LOCKED until $($st.active_end)"
        $ui.StateText.Foreground = '#DC2626'
        $ui.DetailText.Text = "$($st.apps) app(s) are being closed and $($st.sites) site(s) are blocked."
    } else {
        $ui.StateText.Text = 'NightLock is ON'
        $ui.StateText.Foreground = '#16A34A'
        $run = ''
        if (-not $st.daemon_running) { $run = ' The checker is starting (within 5 minutes).' }
        $ui.DetailText.Text = "Unlocked right now. Next lock: $($st.next_lock).$run"
    }
    $ui.StartButton.IsEnabled = (-not $on)
    $ui.StopButton.IsEnabled = $on
    if ($st.locked -and $st.paused_until) {
        $ui.PauseButton.Content = 'Resume now'; $ui.PauseButton.IsEnabled = $true
    } else {
        $ui.PauseButton.Content = "Pause $($st.max_pause) min"
        $ui.PauseButton.IsEnabled = ($on -and $st.locked -and $st.allow_pause)
    }
}

function Run-Core([string[]]$Arguments) {
    try {
        $out = & $CoreScript @Arguments 2>&1 | Out-String
        if ($out.Trim()) { $ui.SaveStatus.Text = $out.Trim().Split("`n")[0].Trim() }
    } catch {
        $ui.SaveStatus.Text = "Error: $($_.Exception.Message)"
    }
    Update-Status
}

function Apply-Filter {
    $view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:Apps)
    $view.Refresh()
}

function Scan-Apps {
    $ui.SaveStatus.Text = 'Scanning installed apps...'
    $ui.RefreshButton.IsEnabled = $false
    $Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    try {
        $entries = Discover-Apps $script:Config
        $script:Apps.Clear()
        foreach ($e in ($entries | Sort-Object @{ Expression = 'Blocked'; Descending = $true }, @{ Expression = 'IsRunning'; Descending = $true }, 'Name')) {
            $script:Apps.Add($e)
        }
        $ui.SaveStatus.Text = "Found $($script:Apps.Count) apps."
    } catch {
        $ui.SaveStatus.Text = "Scan failed: $($_.Exception.Message)"
    }
    $ui.RefreshButton.IsEnabled = $true
    Apply-Filter
}

# ---------- wire up ----------
Fill-TimeCombos
Load-ConfigIntoForm

$ui.AppList.ItemsSource = $script:Apps
$view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($script:Apps)
$view.Filter = [Predicate[object]]{
    param($item)
    $q = $ui.SearchBox.Text
    if (-not $q) { return $true }
    return ($item.Name -like "*$q*" -or $item.ProcessName -like "*$q*")
}
$ui.SearchBox.Add_TextChanged({ Apply-Filter })

$ui.RefreshButton.Add_Click({ Scan-Apps })

$ui.AddAppButton.Add_Click({
    $name = ($ui.ManualAppBox.Text.Trim() -replace '\.exe$', '')
    if (-not $name) { return }
    $existing = $script:Apps | Where-Object { $_.ProcessName -eq $name } | Select-Object -First 1
    if ($existing) { $existing.Blocked = $true }
    else {
        $e = New-Object AppEntry
        $e.Name = $name; $e.ProcessName = $name; $e.Source = 'Added by you'; $e.Blocked = $true
        $e.IsRunning = ((Get-Process -Name $name -ErrorAction SilentlyContinue).Count -gt 0)
        $script:Apps.Insert(0, $e)
    }
    $ui.ManualAppBox.Text = ''
    $ui.SaveStatus.Text = "$name added. Press Save changes."
})

$ui.StartButton.Add_Click({
    if (-not (Save-Form)) { return }
    $ui.SaveStatus.Text = 'Starting...'
    $Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    Run-Core @('start')
})

$ui.StopButton.Add_Click({
    $ui.SaveStatus.Text = 'Stopping...'
    $Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    Run-Core @('stop')
})

$ui.PauseButton.Add_Click({
    $st = Get-State
    if ($st -and $st.paused_until) { Run-Core @('resume') }
    else { Run-Core @('pause', [string]$script:Config.max_pause_minutes) }
})

$ui.SaveButton.Add_Click({ [void](Save-Form) })

$ui.FolderButton.Add_Click({ Start-Process explorer.exe $ConfigDir })

$Window.Add_ContentRendered({
    if ($script:Scanned) { return }
    $script:Scanned = $true
    Update-Status
    Scan-Apps
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(10)
$timer.Add_Tick({ Update-Status })
$timer.Start()

$Window.Add_Closed({ $timer.Stop() })

[void]$Window.ShowDialog()
