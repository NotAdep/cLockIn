#if DEBUG
import AppKit
import CLockInCore
import SwiftUI

/// Renders each notch state to a PNG so the layout can be checked without screen recording.
/// Run a debug build with `--render-snapshots <directory>`.
@MainActor
enum SnapshotRenderer {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let geometry = NotchGeometry.current(allowVirtual: true) ?? .fallback

        func makeViewModel() -> NotchViewModel {
            let defaults = UserDefaults(suiteName: "cLockIn.snapshots.\(UUID().uuidString)")!
            let model = AppModel(settings: AppSettings(defaults: defaults), defaults: defaults)
            return NotchViewModel(model: model, geometry: geometry)
        }

        var states: [(String, NotchViewModel)] = []

        states.append(("1-closed", makeViewModel()))

        let hover = makeViewModel()
        hover.isHovering = true
        states.append(("2-closed-hover", hover))

        let compact = makeViewModel()
        compact.model.timer.setDuration(25 * 60)
        compact.model.timer.start()
        states.append(("3-compact-timer", compact))

        let compactFocus = makeViewModel()
        compactFocus.model.pomodoro.start()
        compactFocus.isHovering = true
        states.append(("4-compact-focus-hover", compactFocus))

        let expandedTimer = makeViewModel()
        expandedTimer.isExpanded = true
        states.append(("5-expanded-timer-idle", expandedTimer))

        let expandedPaused = makeViewModel()
        expandedPaused.model.timer.start()
        expandedPaused.model.timer.pause()
        expandedPaused.isExpanded = true
        states.append(("6-expanded-timer-paused", expandedPaused))

        let expandedFocus = makeViewModel()
        expandedFocus.model.pomodoro.start()
        expandedFocus.tab = .pomodoro
        expandedFocus.isExpanded = true
        states.append(("7-expanded-focus", expandedFocus))

        let typing = makeViewModel()
        typing.isExpanded = true
        typing.beginDurationEntry()
        for digit in "130" { typing.durationEntry?.append(digit) }
        states.append(("9-expanded-timer-typing", typing))

        let recents = makeViewModel()
        recents.model.timer.setDuration(90)
        recents.model.timer.start()
        recents.model.timer.cancel()
        recents.model.timer.setDuration(7 * 60)
        recents.isExpanded = true
        states.append(("10-expanded-timer-recents", recents))

        let alert = makeViewModel()
        alert.model.debugShowAlert(NotchAlert(
            title: "Focus complete", subtitle: "Up next: short break, 5m",
            symbol: Theme.symbol(for: .focus), tint: Theme.focus, action: .startNextPhase(.shortBreak)
        ))
        states.append(("8-alert", alert))

        for (name, viewModel) in states {
            write(canvas(for: viewModel, geometry: geometry), name: name, to: directory)
        }

        let editor = makeViewModel()
        editor.beginDurationEntry(for: .pomodoroSetting(.shortBreak))
        for digit in "730" { editor.durationEntry?.append(digit) }
        write(FocusEditorPreview(viewModel: editor), name: "11-focus-editor", to: directory)

        let focusTyping = makeViewModel()
        focusTyping.tab = .pomodoro
        focusTyping.isExpanded = true
        focusTyping.beginDurationEntry(for: .pomodoroDial)
        for digit in "5000" { focusTyping.durationEntry?.append(digit) }
        write(canvas(for: focusTyping, geometry: geometry), name: "12-focus-dial-typing", to: directory)

        let alertTimer = makeViewModel()
        alertTimer.model.debugShowAlert(NotchAlert(
            title: "Time's up", subtitle: "5m timer finished", symbol: "bell.fill", tint: Theme.timer
        ))
        write(canvas(for: alertTimer, geometry: geometry), name: "13-alert-timer", to: directory)

        let stopwatchVM = makeViewModel()
        stopwatchVM.tab = .stopwatch
        stopwatchVM.isExpanded = true
        stopwatchVM.model.stopwatch.start()
        for _ in 0..<3 { stopwatchVM.model.stopwatch.lap() }
        write(canvas(for: stopwatchVM, geometry: geometry), name: "30-stopwatch", to: directory)

        let world = makeViewModel()
        world.tab = .worldClock
        world.isExpanded = true
        write(canvas(for: world, geometry: geometry), name: "31-world-clock", to: directory)

        let digital = makeViewModel()
        digital.tab = .worldClock
        digital.isExpanded = true
        digital.model.settings.worldClockStyle = .digital
        write(canvas(for: digital, geometry: geometry), name: "31b-world-clock-digital", to: directory)

        let alarmList = makeViewModel()
        alarmList.tab = .alarms
        alarmList.isExpanded = true
        alarmList.model.alarms.add(Alarm(hour: 7, minute: 30, label: "Wake up", repeatDays: [2, 3, 4, 5, 6]))
        alarmList.model.alarms.add(Alarm(hour: 13, minute: 0, label: "Lunch", isEnabled: false))
        alarmList.model.alarms.add(Alarm(hour: 22, minute: 15, label: "Wind down", repeatDays: Set(1...7)))
        write(canvas(for: alarmList, geometry: geometry), name: "32-alarms", to: directory)

        let alarmEdit = makeViewModel()
        alarmEdit.tab = .alarms
        alarmEdit.isExpanded = true
        alarmEdit.edit(Alarm(hour: 6, minute: 45, label: "Gym", repeatDays: [2, 4, 6]))
        write(canvas(for: alarmEdit, geometry: geometry), name: "33-alarm-editor", to: directory)

        let alarmRinging = makeViewModel()
        alarmRinging.model.debugShowAlert(NotchAlert(
            title: "Wake up", subtitle: "7:30 AM", symbol: "alarm.fill", tint: Theme.alarm,
            action: .snooze(UUID()), isAlarm: true
        ))
        write(canvas(for: alarmRinging, geometry: geometry), name: "34-alarm-ringing", to: directory)

        let finished = makeViewModel()
        finished.model.debugShowAlert(
            NotchAlert(title: "Time's up", subtitle: "", symbol: "bell.fill", tint: Theme.timer, firedAt: Date().addingTimeInterval(-42)),
            minimized: true
        )
        write(canvas(for: finished, geometry: geometry), name: "35-finished-reminder", to: directory)

        // A Mac without a notch: the island hangs from the middle of the menu bar.
        let virtual = NotchGeometry.virtualPreview
        func makeVirtual() -> NotchViewModel {
            let viewModel = makeViewModel()
            viewModel.geometry = virtual
            return viewModel
        }
        let noNotchIdleHover = makeVirtual()
        noNotchIdleHover.isHovering = true
        write(canvas(for: noNotchIdleHover, geometry: virtual), name: "20-no-notch-hover", to: directory)
        let noNotchCompact = makeVirtual()
        noNotchCompact.model.timer.start()
        write(canvas(for: noNotchCompact, geometry: virtual), name: "21-no-notch-compact", to: directory)
        let noNotchExpanded = makeVirtual()
        noNotchExpanded.tab = .pomodoro
        noNotchExpanded.model.pomodoro.start()
        noNotchExpanded.isExpanded = true
        write(canvas(for: noNotchExpanded, geometry: virtual), name: "22-no-notch-expanded", to: directory)
    }

    // MARK: README screenshots

    /// Renders the screenshots in docs/screenshots: running examples on a desktop-like background.
    static func renderReadmeShots(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let geometry = NotchGeometry.notchedPreview

        func makeViewModel() -> NotchViewModel {
            let defaults = UserDefaults(suiteName: "cLockIn.readme.\(UUID().uuidString)")!
            return NotchViewModel(model: AppModel(settings: AppSettings(defaults: defaults), defaults: defaults), geometry: geometry)
        }

        let compact = makeViewModel()
        compact.model.timer.restore(TimerSnapshot(selectedDuration: 1500, countdown: running(duration: 1500, remaining: 754)))
        writeReadme(compact, height: 90, name: "live-activity", to: directory)

        let timer = makeViewModel()
        timer.model.timer.restore(TimerSnapshot(selectedDuration: 600, countdown: Countdown(duration: 600), recentDurations: [90, 420]))
        timer.isExpanded = true
        writeReadme(timer, name: "timer", to: directory)

        let focus = makeViewModel()
        var focusSnapshot = focus.model.pomodoro.snapshot
        focusSnapshot.countdown = running(duration: 1500, remaining: 1032)
        focusSnapshot.completedFocusRounds = 2
        focusSnapshot.roundsToday = 5
        focus.model.pomodoro.restore(focusSnapshot)
        focus.tab = .pomodoro
        focus.isExpanded = true
        writeReadme(focus, name: "focus", to: directory)

        let stopwatch = makeViewModel()
        stopwatch.model.stopwatch.restore(StopwatchSnapshot(accumulated: 95.37, startedAt: nil, laps: [21.32, 44.9, 70.05]))
        stopwatch.tab = .stopwatch
        stopwatch.isExpanded = true
        writeReadme(stopwatch, name: "stopwatch", to: directory)

        for style in WorldClockStyle.allCases {
            let world = makeViewModel()
            world.model.settings.worldClockStyle = style
            world.tab = .worldClock
            world.isExpanded = true
            writeReadme(world, name: "world-clock-\(style.rawValue)", to: directory)
        }

        let alarms = makeViewModel()
        alarms.model.alarms.add(Alarm(hour: 7, minute: 30, label: "Wake up", repeatDays: [2, 3, 4, 5, 6]))
        alarms.model.alarms.add(Alarm(hour: 13, minute: 0, label: "Lunch", isEnabled: false))
        alarms.model.alarms.add(Alarm(hour: 22, minute: 15, label: "Wind down", repeatDays: Set(1...7)))
        alarms.tab = .alarms
        alarms.isExpanded = true
        writeReadme(alarms, name: "alarms", to: directory)

        let ringing = makeViewModel()
        ringing.model.debugShowAlert(NotchAlert(
            title: "Wake up", subtitle: "7:30", symbol: "alarm.fill", tint: Theme.alarm, action: .snooze(UUID()), isAlarm: true
        ))
        writeReadme(ringing, height: 130, name: "alert", to: directory)
    }

    /// A countdown that's running with `remaining` seconds left, built through Codable since its state is private.
    private static func running(duration: TimeInterval, remaining: TimeInterval) -> Countdown {
        let end = Date().addingTimeInterval(remaining).timeIntervalSinceReferenceDate
        let json = #"{"duration":\#(duration),"state":{"running":{"endDate":\#(end)}}}"#
        return (try? JSONDecoder().decode(Countdown.self, from: Data(json.utf8))) ?? Countdown(duration: duration)
    }

    private static func writeReadme(_ viewModel: NotchViewModel, height: CGFloat = 250, name: String, to directory: URL) {
        let notch = viewModel.geometry.notchSize
        let view = ZStack(alignment: .top) {
            // A desktop-like backdrop with a translucent menu bar and the hardware notch.
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.2, blue: 0.42), Color(red: 0.42, green: 0.28, blue: 0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Color.white.opacity(0.18).frame(height: notch.height)
            UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
                .fill(.black)
                .frame(width: notch.width, height: notch.height)
            NotchRootView(viewModel: viewModel)
        }
        .frame(width: 700, height: height)
        write(view, name: name, to: directory)
    }

    private static func canvas(for viewModel: NotchViewModel, geometry: NotchGeometry) -> some View {
        let notch = geometry.notchSize
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.75), Color(white: 0.55)], startPoint: .top, endPoint: .bottom)
            Color(white: 0.85).frame(height: notch.height)
            NotchRootView(viewModel: viewModel)
            // Outline of the hardware notch, to check alignment.
            if geometry.hasHardwareNotch {
                Rectangle()
                    .stroke(Color.red.opacity(0.8), lineWidth: 0.5)
                    .frame(width: notch.width, height: notch.height)
            }
        }
        .frame(width: 700, height: 280)
    }

    private static func write(_ view: some View, name: String, to directory: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}

private struct FocusEditorPreview: View {
    let viewModel: NotchViewModel

    var body: some View {
        PomodoroPanel(viewModel: viewModel, isEditing: true)
            .padding(.horizontal, 26)
            .frame(width: 540, height: 156)
            .background(.black)
            .environment(\.colorScheme, .dark)
    }
}
#endif
