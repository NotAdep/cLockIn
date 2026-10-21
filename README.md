# cLockIn

A macOS clock app that lives in the MacBook notch and expands like the iPhone's Dynamic Island.

- **Timer**: presets, ±1 minute buttons, scroll on the ring to set the duration, +1 min while running.
- **Focus (Pomodoro)**: focus, short break and long break phases with a round counter and optional auto-advance.
- **Live activity**: while something runs, the notch widens to show a progress ring and the time remaining.
- **Hover** over the notch to peek and **click** to open the full panel. When time is up, the notch shows an alert with a chime.
- Backup controls in the menu bar. On displays without a notch it draws a virtual one.

Requires macOS 14+ and Xcode 16 command line tools. No Homebrew needed.

## Build & run

```bash
./scripts/run.sh          # build, sign, and launch build/cLockIn.app
./scripts/build-app.sh    # just build
swift test                # engine unit tests
```

The app is signed with the `NotAdep Code Signing` certificate when it's in the keychain, otherwise ad hoc
(override with `CODESIGN_IDENTITY=...`). Copy `build/cLockIn.app` to `/Applications` before turning on
"Launch at login".

Debug builds can render every notch state to PNGs:

```bash
CONFIG=debug ./scripts/build-app.sh && build/cLockIn.app/Contents/MacOS/cLockIn --render-snapshots /tmp/notch-shots
```

## Layout

- `Sources/CLockInCore`: the timer and Pomodoro engines (UI-free and unit tested). They store end dates rather than counting ticks, so they stay accurate across sleep.
- `Sources/cLockIn/Notch`: the notch panel, its shape, the state machine (closed, compact, alert, expanded) and the views.
- `Sources/cLockIn/Features`: the Timer and Focus panels.
- `Sources/cLockIn/App`, `Services` and `Settings`: app wiring, notifications, sounds and settings.
