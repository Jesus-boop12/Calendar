# NightLock for Windows

Closes distracting apps during a nightly window so you can't drift into them.
A hidden background checker starts at logon, looks every 20 seconds, and needs
nothing installed beyond Windows 10/11 (uses built-in Windows PowerShell).

## Install

1. Copy this `windows` folder to your PC.
2. Double-click **`install.cmd`**. It copies NightLock to `%LOCALAPPDATA%\NightLock`,
   registers a scheduled task named *NightLock*, starts it, and adds the folder
   to your PATH.
3. Open a new terminal (Windows Terminal, PowerShell or cmd) and run:

```
nightlock edit      # set your window and the apps to block
nightlock status    # confirm "background checker running"
```

If Windows shows a SmartScreen or "unknown publisher" prompt, choose *Run anyway*.
The scripts run only under your own user account and need no admin rights.

## Configure

`%LOCALAPPDATA%\NightLock\config.txt` (see `config.example.txt`):

| Key | Meaning | Default |
| --- | --- | --- |
| `start` / `end` | Lock window in 24-hour `HH:MM`. May cross midnight. | `22:00` / `06:00` |
| `days` | Nights the lock applies to, by the day the window starts on. | every day |
| `warn_minutes` | Notification this many minutes before `start`. `0` disables. | `10` |
| `allow_pause` | Whether `nightlock pause` is allowed. `no` removes the escape hatch. | `yes` |
| `max_pause_minutes` | Longest pause allowed. | `15` |
| `grace_seconds` | Time an app gets to close cleanly before being force-killed. | `5` |
| `notify` | Show a Windows notification when apps are closed. | `yes` |
| `app` | One line per app, by process name as shown in Task Manager > Details, without `.exe`. | chrome, msedge, Discord, steam |

Changes take effect on the next check. No restart needed.

Finding a process name: open Task Manager, go to the **Details** tab, and use the
name in the first column without `.exe`. Examples: `chrome`, `msedge`, `firefox`,
`Discord`, `steam`, `Spotify`, `Netflix`, `WhatsApp`, `Telegram`.

## Commands

```
nightlock status           window, apps, and whether the lock is active now
nightlock add Spotify      block another app
nightlock remove steam     stop blocking an app
nightlock pause 10         lift the lock for 10 minutes (if allowed)
nightlock resume           end a pause early
nightlock edit             open the config in Notepad
nightlock log              recent activity
```

## How it works

1. The *NightLock* scheduled task launches `nightlock.ps1 daemon` hidden at logon,
   and re-launches it every 5 minutes in case it was closed. The checker is
   single-instance, so the re-launch is a no-op while it is running.
2. Every 20 seconds it reads the config. Inside the window, and not paused, each
   blocked app that is running is asked to close its windows.
3. After `grace_seconds` any survivor is force-killed, so relaunching an app only
   buys you until the next check.
4. A heads-up toast goes out `warn_minutes` before the window starts.

## Making it harder to bypass

You can always run `uninstall.cmd` or edit the config. For more friction, set
`allow_pause = no` and mark the config read-only (right-click, Properties,
Read-only). Ending the `powershell.exe` checker in Task Manager only works for
up to 5 minutes before the scheduled task restarts it.

## Uninstall

Double-click `uninstall.cmd` (keeps your config), or run
`powershell -ExecutionPolicy Bypass -File uninstall.ps1 -Purge` to remove
config and logs too.

## Testing without waiting for night

In PowerShell:

```powershell
$env:NIGHTLOCK_DRY_RUN = '1'
$env:NIGHTLOCK_NOW = '23:00 Mon'
nightlock check
Remove-Item Env:NIGHTLOCK_DRY_RUN, Env:NIGHTLOCK_NOW
```

`NIGHTLOCK_NOW` fakes the clock and `NIGHTLOCK_DRY_RUN=1` prints what would be
closed instead of closing it.
