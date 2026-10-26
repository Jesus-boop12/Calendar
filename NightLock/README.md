# NightLock

Locks distracting apps on your computer during a nightly window so you stop
getting pulled into them. Pick the folder for your OS:

- [`windows/`](windows/README.md) for Windows 10/11. Double-click `install.cmd`.
- [`macos/`](macos/README.md) for macOS. Run `./install.sh`.

Both versions share the same config format, commands and behavior: a background
checker runs every 20 seconds, closes the configured apps inside the window
(which may cross midnight), warns you before the lock starts, and offers an
optional capped pause you can disable.
