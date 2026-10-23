# Changelog

## Unreleased

- **Other apps can use the notch (Island API).** Apps on your Mac can show a pill beside the notch, short alerts with buttons, and their own tab in the open panel, like apps sharing the Dynamic Island. Each app asks first. Manage them in Settings → Connected Apps. Details for developers are in `docs/island-api.md`.

## 0.4.2

- Fixes typing in other cLockIn windows: the notch could take Space, digits and Delete typed into the label field or Settings, for example after opening the notch with the keyboard shortcut.
- Opening the statistics window or Settings now closes the notch's keyboard session.

## 0.4.1

- Fixes a crash when the pointer is on a display without a notch (such as an external monitor) while "Show on displays without a notch" is off. cLockIn could crash on every launch in that setup.

## 0.4.0

- **Two at once in the notch.** When several things run, the island shows the two most important, one on each side of the notch.
- **Multiple timers.** Run up to five timers at the same time and switch between them in the Timer tab.
- **Focus labels.** Tag focus rounds ("Thesis", "Code") to see where your time goes.
- **Focus statistics.** Today's time, a 7-day chart and your streak in the Focus tab. The full picture is in a statistics window, with charts by label, every session and CSV export.
- **Do Not Disturb during focus (optional).** Turns Do Not Disturb on and off with two shortcuts you make once in the Shortcuts app. Off by default.
- **Lighter open panel.** Rolling digits can be turned off in Settings → Notch, and are skipped automatically in Low Power Mode or with Reduce Motion. Off, the open panel uses about 3% CPU instead of about 15–20%.
- **Firmer hover haptic,** with a Try It button in Settings.
- **Lighter menu bar.** The menu bar icon and menu no longer redraw every second.

## 0.3.1

- Much lighter on battery: a running timer now uses about 1% CPU instead of about 28%, and the stopwatch about 0.7% instead of 18%. Idle stays at 0%.
- The notch redraws only when a displayed number changes, and the hidden panel no longer updates in the background.
- Memory stays steady while timers run.

## 0.3.0

- Download cLockIn as a DMG from GitHub Releases. It runs on Apple silicon and Intel.
- Update check: once a day cLockIn looks for a new release and offers it in the menu bar and Settings, with Download, Release Notes and Skip This Version. You can turn it off.
- Settings sidebar shows full section names.

## 0.2.0

- Stopwatch with laps, fastest and slowest highlighted.
- World Clock with analog or digital faces and city search.
- Alarms, one-off or repeating, with adjustable snooze. They ring while the Mac is awake.
- Global shortcut (⌃⌥T by default) and keyboard control of the panel.
- The island follows the display you're using.
- Unanswered alerts keep chiming, then shrink to a `+0:42` reminder.
- New app icon, About panel, and a redesigned Settings window.
- Smoother opening animation.

## 0.1.0

- Timer with typed durations, presets and recent timers.
- Focus (Pomodoro) with typed phase lengths and optional auto-start.
- Notch island with hover peek, click to open, live activity and a glowing alert.
- Menu bar controls and Settings.
