# Lock Guard

Tells you if someone touched your Mac while the screen was locked.

It only watches while the screen is locked. When you unlock, if someone else touched it, you get a notification like:

> While locked 14:02:10–14:40:31: input at 14:15:02–14:15:20; 2 wrong passwords (14:15:08, 14:15:14)

## Use

A shield in the menu bar. Click it:

- **Guard while locked**: the on/off toggle. Filled shield = on, slashed shield = off.
- The last report, and **Show log…** for every lock (also the quiet ones).
- **Open at login**: start the app when you log in.
- The shield starts just left of the battery. Cmd-drag it to move it; it remembers where.
- A shield with **!** means something happened while it was locked. It clears when you open the menu.

```sh
./guard install     # build, copy to ~/Applications, and open
./guard uninstall   # quit, remove the app and the login item
./guard log         # the last reports
./guard check       # self-test: idle counter and wrong passwords in the last 10 min
```

Needs the Xcode command line tools (`swiftc`). The first notification may ask for permission (it comes from Script Editor / osascript).

## What it watches

- **Input:** any key press or mouse/trackpad movement. macOS keeps an idle counter (`HIDIdleTime`) that resets on any input, even at the lock screen. The agent reads it every second while locked. It can't tell keyboard from mouse.
- **Wrong passwords:** the lock screen logs `authFailWithMessage… INCORRECT password` for each wrong attempt. On unlock, the agent reads those lines from the system log for the locked window.

## What it ignores

- Input in the first 5 seconds after the lock (you walking away).
- Input and wrong passwords in the last 30 seconds before the unlock: that is probably you. They still show in `./guard log`, marked "probably you".

A lock with nothing else to report is written to the log only, with no notification.

## How it works

- `Sources/Guard.swift`: the guard. It listens for the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications.
- `Sources/main.swift`: the menu bar app (AppKit, no Xcode project). "Open at login" writes `~/Library/LaunchAgents/com.alex-quiterio.lock-guard.login.plist`.
- `Resources/notify.applescript`: shows the notification.
- `Resources/AppIcon.icns`: the app icon, drawn by `Resources/make-icon.swift` (`swift Resources/make-icon.swift /tmp/AppIcon.iconset && iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns`).
- `guard`: builds `build/Lock Guard.app` with `swiftc` and installs it.
- Reports go to `~/Library/Logs/lock-guard.log`.

## Limits

- Someone who knows your password can unlock it. Lock Guard sees the input, but if they unlock it themselves, the burst before the unlock looks like you.
- If the Mac sleeps (lid closed), nothing is polled until it wakes. Opening the lid counts as input.
