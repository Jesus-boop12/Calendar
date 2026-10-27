# NightLock

Quits distracting Mac apps during a nightly window so you can't drift into them.
Runs in the background as a user LaunchAgent, checks every 20 seconds, and needs
nothing installed beyond stock macOS.

## Install

```sh
cd NightLock/macos
./install.sh
nightlock edit        # set your window and the apps to block
```

Add `~/.local/bin` to your PATH if `nightlock` is not found:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

The first time the lock fires, macOS may ask whether `bash` or `osascript` may
control an app or send notifications. Click **Allow**. If you deny it, the app
is force-quit instead of asked to quit politely, so the lock still works.

## Configure

`~/.config/nightlock/config` (see `config.example`):

| Key | Meaning | Default |
| --- | --- | --- |
| `start` / `end` | Lock window in 24-hour `HH:MM`. May cross midnight. | `22:00` / `06:00` |
| `days` | Nights the lock applies to, by the day the window starts on. | every day |
| `warn_minutes` | Notification this many minutes before `start`. `0` disables. | `10` |
| `allow_pause` | Whether `nightlock pause` is allowed. `no` removes the escape hatch. | `yes` |
| `max_pause_minutes` | Longest pause allowed. | `15` |
| `grace_seconds` | Time an app gets to quit cleanly before being force-killed. | `5` |
| `notify` | Show a notification when apps are closed. | `yes` |
| `app` | One line per app, using the name shown in the Dock or Activity Monitor. | Safari, Google Chrome, Discord, Slack |

Changes take effect on the next check. No restart needed.

## Commands

```
nightlock status           window, apps, and whether the lock is active now
nightlock add "Netflix"    block another app
nightlock remove "Slack"   stop blocking an app
nightlock pause 10         lift the lock for 10 minutes (if allowed)
nightlock resume           end a pause early
nightlock edit             open the config file
nightlock log              recent activity
```

## How it works

1. `launchd` runs `nightlock check` every 20 seconds (`com.nightlock.agent`).
2. If the current time is inside the window and the lock isn't paused, each
   configured app that is running is asked to quit via AppleScript.
3. After `grace_seconds` any survivor is killed, so relaunching an app only buys
   you until the next check.
4. A heads-up notification goes out `warn_minutes` before the window starts.

## Making it harder to bypass

You can always disable it with `./uninstall.sh` or by editing the config. To add
friction, set `allow_pause = no`, and consider changing the config file to
read-only (`chmod 444 ~/.config/nightlock/config`) so you have to go out of your
way to loosen it. A stricter version that runs as root (so disabling needs your
admin password) is possible but is not part of this setup.

## Uninstall

```sh
./uninstall.sh          # keeps your config
./uninstall.sh --purge  # removes config and logs too
```

## Testing without waiting for night

```sh
NIGHTLOCK_DRY_RUN=1 NIGHTLOCK_NOW="23:00 Mon" nightlock check
```

`NIGHTLOCK_NOW` fakes the clock and `NIGHTLOCK_DRY_RUN=1` prints what would be
closed instead of closing it.
