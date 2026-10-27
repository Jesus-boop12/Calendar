@echo off
title Stop NightLock
echo Stopping and removing NightLock...

rem 1. Stop, disable and delete the scheduled task (it would otherwise relaunch the checker every 5 minutes).
schtasks /End /TN NightLock >nul 2>&1
schtasks /Change /TN NightLock /DISABLE >nul 2>&1
schtasks /Delete /TN NightLock /F >nul 2>&1

rem 2. Kill every running NightLock process, however it was started.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'nightlock' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

rem 3. Release website blocks in Chrome, Edge and Brave.
reg delete "HKCU\Software\Policies\Google\Chrome\URLBlocklist" /f >nul 2>&1
reg delete "HKCU\Software\Policies\Microsoft\Edge\URLBlocklist" /f >nul 2>&1
reg delete "HKCU\Software\Policies\BraveSoftware\Brave\URLBlocklist" /f >nul 2>&1

rem 4. Remove the Start Menu shortcut, the installed files and the PATH entry.
del /F /Q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\NightLock.lnk" >nul 2>&1
if exist "%LOCALAPPDATA%\NightLock" rmdir /S /Q "%LOCALAPPDATA%\NightLock"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); if($p){ $n=(($p -split ';') | Where-Object { $_ -and $_ -notmatch 'NightLock' }) -join ';'; [Environment]::SetEnvironmentVariable('Path',$n,'User') }"

echo.
echo ---- Verification ----
schtasks /Query /TN NightLock >nul 2>&1
if errorlevel 1 (echo Scheduled task: GONE) else (echo Scheduled task: STILL PRESENT - open Task Scheduler and delete "NightLock" by hand)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=@(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'nightlock' -and $_.ProcessId -ne $PID }).Count; if($c -eq 0){'Background checker: GONE'}else{\"Background checker: $c STILL RUNNING - open Task Manager, Details tab, end powershell.exe\"}"
if exist "%LOCALAPPDATA%\NightLock" (echo Install folder: STILL PRESENT) else (echo Install folder: GONE)
echo Website blocks: GONE
echo.
echo NightLock is stopped and removed. You can close this window.
pause
