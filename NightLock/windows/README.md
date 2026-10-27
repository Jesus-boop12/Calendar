# NightLock for Windows

Closes distracting apps and blocks websites during your nightly lock windows, with
separate times for weeknights and weekend nights. A settings window lets you pick apps
by icon, type the sites to block, set the times, and press Start or Stop. Needs nothing
installed beyond Windows 10/11 and no admin rights.

## Get started

1. Copy this `windows` folder somewhere permanent, for example `Documents\NightLock`.
2. Double-click **`NightLock.cmd`**. The settings window opens.
3. On the **Apps** tab, tick the apps to close. On **Websites**, type the sites to block.
   On **Schedule**, set your weeknight and weekend windows.
4. Press **Start**. The first Start installs NightLock into `%LOCALAPPDATA%\NightLock`,
   creates a scheduled task that runs the hidden background checker, and adds a
   **NightLock** entry to your Start Menu for next time.

If Windows shows a SmartScreen or "unknown publisher" prompt, choose *Run anyway*.

## Stopping it

- **Stop button** in the NightLock window. Apps and websites are released immediately
  and nothing restarts until you press Start again.
- From a terminal: `nightlock stop` (and `nightlock start` to turn it back on).
- **Remove completely**: double-click `STOP-NightLock.cmd`. It deletes the scheduled
  task, kills the checker, releases website blocks, removes the files and prints a
  verification summary.

## The window

| Area | What it does |
| --- | --- |
| Header | Current state (OFF, ON, LOCKED until, Paused until), plus Start, Stop and Pause buttons. |
| Apps | Apps found in your Start Menu, the Microsoft Store and running programs, with icons. Tick to block. Search box, Rescan, and a field to add any process name by hand. |
| Websites | One site per line. Blocked in Chrome, Edge and Brave while a lock is active. `youtube.com` covers all subdomains; `reddit.com/r/all` blocks a section. |
| Schedule | Weeknights (nights starting Sun to Thu) and Weekend nights (nights starting Fri and Sat), each with On/Off, start and end time. Options for the warning, pausing and notifications. |
| Save changes | Writes the config. The checker picks it up within 20 seconds. |

## How it works

- The *NightLock* scheduled task launches the hidden checker at logon and relaunches
  it every 5 minutes if it is not running. The checker is single-instance.
- Every 20 seconds it reads the config. Inside a window and not paused, it asks each
  blocked app to close, force-kills survivors after a few seconds, and writes the
  browsers' URL blocklist policy for your account. Outside the window, or on Stop or
  Pause, it removes that policy again.
- Website blocking uses the `URLBlocklist` policy under your user registry hive for
  Chrome, Edge and Brave. Chrome may show "managed by your organization" while a lock
  is active. Pages already open keep working until you navigate or reload. Other
  browsers are not covered. Block the browser itself on the Apps tab if you need that.
- A toast warns you before each lock and confirms what was closed.

## Command line

After the first Start, open a new terminal:

```
nightlock status                 state, schedules, apps and sites
nightlock start | stop           turn the checker on or off
nightlock pause 10               lift the lock for 10 minutes (if allowed)
nightlock resume                 end a pause early
nightlock add Spotify            block an app      (nightlock remove Spotify)
nightlock site-add reddit.com    block a website   (nightlock site-remove reddit.com)
nightlock ui                     open the settings window
nightlock edit                   open config.txt in Notepad
nightlock log                    recent activity
```

Config lives in `%LOCALAPPDATA%\NightLock\config.txt` (see `config.example.txt`).

## Making it harder to bypass

Untick *Allow the Pause button* on the Schedule tab for no escape hatch. Ending the
checker in Task Manager only works for up to 5 minutes before the scheduled task
restarts it. Stop, the uninstaller and `STOP-NightLock.cmd` remain available on purpose.

## Testing without waiting for night

```powershell
$env:NIGHTLOCK_DRY_RUN = '1'; $env:NIGHTLOCK_NOW = '23:00 Mon'
nightlock check
Remove-Item Env:NIGHTLOCK_DRY_RUN, Env:NIGHTLOCK_NOW
```

`NIGHTLOCK_NOW` fakes the clock (Monday night here) and `NIGHTLOCK_DRY_RUN` prints what
would be closed or blocked instead of doing it.
