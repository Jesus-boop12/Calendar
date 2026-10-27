@echo off
title Stop NightLock
echo Stopping NightLock...

rem 1. Stop, disable and delete the scheduled task (it would otherwise relaunch the checker every 5 minutes).
schtasks /End /TN NightLock >nul 2>&1
schtasks /Change /TN NightLock /DISABLE >nul 2>&1
schtasks /Delete /TN NightLock /F >nul 2>&1

rem 2. Kill every running NightLock checker, however it was started.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'nightlock' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

rem 3. Remove the installed files so nothing can start it again.
if exist "%LOCALAPPDATA%\NightLock" rmdir /S /Q "%LOCALAPPDATA%\NightLock"

rem 4. Remove it from the user PATH.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); if($p){ $n=(($p -split ';') | Where-Object { $_ -and $_ -notmatch 'NightLock' }) -join ';'; [Environment]::SetEnvironmentVariable('Path',$n,'User') }"

echo.
echo ---- Verification ----
schtasks /Query /TN NightLock >nul 2>&1
if errorlevel 1 (echo Scheduled task: GONE) else (echo Scheduled task: STILL PRESENT - open Task Scheduler and delete "NightLock" by hand)
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=@(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'nightlock' -and $_.ProcessId -ne $PID }).Count; if($c -eq 0){'Background checker: GONE'}else{\"Background checker: $c STILL RUNNING - open Task Manager, Details tab, end powershell.exe\"}"
if exist "%LOCALAPPDATA%\NightLock" (echo Install folder: STILL PRESENT) else (echo Install folder: GONE)
echo.
echo NightLock is stopped. You can close this window.
pause
