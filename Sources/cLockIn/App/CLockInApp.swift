import AppKit
import CLockInCore
import SwiftUI

@main
struct CLockInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: appDelegate.model, notch: appDelegate.notch)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    lazy var model = AppModel(settings: settings)
    lazy var notch = NotchController(model: model, settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--readme-shots"),
           CommandLine.arguments.indices.contains(index + 1) {
            SnapshotRenderer.renderReadmeShots(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-snapshots"),
           CommandLine.arguments.indices.contains(index + 1) {
            SnapshotRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        #endif
        if settings.systemNotificationsEnabled { NotificationService.shared.requestAuthorization() }
        notch.start()
        model.updates.start()
    }
}

/// The backup controls in the menu bar, also used on displays without a notch.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if model.settings.showTimeInMenuBar, let activity = model.activity {
            HStack(spacing: 4) {
                Image(systemName: activity.isPaused ? "pause.circle" : activity.symbol)
                Text(activity.timeText).monospacedDigit()
            }
        } else {
            // Only whether something runs, not the clock, so the status item isn't redrawn every second.
            Image(systemName: model.hasLiveActivity ? "timer.circle.fill" : "timer")
        }
    }
}

struct MenuBarContent: View {
    let model: AppModel
    let notch: NotchController

    var body: some View {
        if let update = model.updates.availableUpdate {
            Section("cLockIn \(update.version) is available") {
                Button("Download Update…") { model.updates.download(update) }
                Button("Release Notes") { model.updates.openReleaseNotes(update) }
            }
            Divider()
        }

        if let summary = model.menuSummary {
            // No live times in the menu: SwiftUI keeps the menu built, and a ticking title rebuilds it every second.
            Text("\(summary.title)\(summary.isPaused ? " (paused)" : "")")
            Divider()
        }

        Section("Timers") {
            ForEach(model.timer.timers) { item in
                let paused = item.countdown.isPaused
                Menu("\(item.label) timer\(paused ? " (paused)" : "")") {
                    Button(paused ? "Resume" : "Pause") { model.timer.toggle(id: item.id) }
                    Button("Add 1 Minute") { model.timer.addMinute(id: item.id) }
                    Button("Cancel") { model.timer.cancel(id: item.id) }
                }
            }
            if model.timer.canStartAnother {
                ForEach([5.0, 10, 25].map { $0 * 60 }, id: \.self) { duration in
                    Button("Start \(TimeFormat.short(duration)) Timer") {
                        model.timer.setDuration(duration)
                        model.timer.start()
                    }
                }
            }
        }

        Section("Focus") {
            let pomodoro = model.pomodoro
            Button(pomodoro.isRunning ? "Pause \(pomodoro.phase.title)" : "Start \(pomodoro.phase.title)") {
                pomodoro.toggle()
            }
            Button("Skip to \(pomodoro.nextPhase.title)") { pomodoro.skip() }
            Button("Reset Cycle") { pomodoro.reset() }
            Button("Focus Statistics…") { FocusStatsWindowController.shared.show(model: model) }
        }

        Section("Stopwatch") {
            let stopwatch = model.stopwatch
            Button(stopwatch.isRunning ? "Pause Stopwatch" : stopwatch.isActive ? "Resume Stopwatch" : "Start Stopwatch") {
                stopwatch.toggle()
            }
            if stopwatch.isRunning { Button("Lap") { stopwatch.lap() } }
            if stopwatch.isActive && !stopwatch.isRunning { Button("Reset Stopwatch") { stopwatch.reset() } }
        }

        if !model.alarms.alarms.isEmpty {
            Section("Alarms") {
                ForEach(model.alarms.alarms) { alarm in
                    Toggle(
                        "\(AlarmTimeText.format(hour: alarm.hour, minute: alarm.minute))  \(alarm.label), \(alarm.repeatSummary())",
                        isOn: Binding(get: { alarm.isEnabled }, set: { model.alarms.setEnabled($0, for: alarm.id) })
                    )
                }
            }
        }

        Divider()
        Button("Open Panel") { notch.showExpanded() }
        Button("Settings…") { SettingsWindowController.shared.show(model: model) }
            .keyboardShortcut(",")
        Button("Check for Updates…") {
            SettingsWindowController.shared.show(model: model, section: .general)
            Task { await model.updates.check() }
        }
        Button("About cLockIn") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: "Made by NotAdep",
                    attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
                ),
            ])
        }
        Button("Quit cLockIn") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
