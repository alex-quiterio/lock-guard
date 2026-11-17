# Lock Guard

Tells you if someone touched your Mac while the screen was locked.

It only watches while the screen is locked. When you unlock, if someone else touched it, you get a notification like:

> While locked 14:02:10–14:40:31: input at 14:15:02–14:15:20; 2 wrong passwords (14:15:08, 14:15:14)

## Use

```sh
./guard on        # build, start now, and start again after every login
./guard off       # stop, and stop starting at login
./guard status    # on or off
./guard log       # the reports of every lock (also the quiet ones)
./guard check     # self-test: idle counter, wrong passwords in the last 10 min, and a test notification
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

- `Sources/main.swift`: the agent. It listens for the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications.
- `bin/notify.applescript`: shows the notification.
- `guard`: builds the agent and installs it as a launchd agent (`~/Library/LaunchAgents/com.alex-quiterio.lock-guard.plist`).
- Reports go to `~/Library/Logs/lock-guard.log`.

## Limits

- Someone who knows your password can unlock it. Lock Guard sees the input, but if they unlock it themselves, the burst before the unlock looks like you.
- If the Mac sleeps (lid closed), nothing is polled until it wakes. Opening the lid counts as input.
