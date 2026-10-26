' Starts the NightLock background checker with no visible window.
Set sh = CreateObject("WScript.Shell")
folder = Replace(WScript.ScriptFullName, WScript.ScriptName, "")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "nightlock.ps1"" daemon", 0, False
