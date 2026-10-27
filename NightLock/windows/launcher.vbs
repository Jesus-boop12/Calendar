' Starts NightLock with no visible console window.
'   wscript launcher.vbs daemon   -> background checker (used by the scheduled task)
'   wscript launcher.vbs ui       -> settings window
Set sh = CreateObject("WScript.Shell")
folder = Replace(WScript.ScriptFullName, WScript.ScriptName, "")
mode = "daemon"
If WScript.Arguments.Count > 0 Then
    mode = LCase(WScript.Arguments(0))
End If
If mode = "ui" Then
    cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "nightlock-ui.ps1"""
Else
    cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "nightlock.ps1"" daemon"
End If
sh.Run cmd, 0, False
