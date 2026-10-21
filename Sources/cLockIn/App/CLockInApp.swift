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
            Image(systemName: model.liveKind == nil ? "timer" : "timer.circle.fill")
        }
    }
}

struct MenuBarContent: View {
    let model: AppModel
    let notch: NotchController

    var body: some View {
        if let activity = model.activity {
            Text("\(activity.title): \(activity.timeText)\(activity.isPaused ? " (paused)" : "")")
            Divider()
        }

        Section("Timer") {
            if model.timer.isActive {
                Button(model.timer.isPaused ? "Resume Timer" : "Pause Timer") { model.timer.toggle() }
                Button("Add 1 Minute") { model.timer.addMinute() }
                Button("Cancel Timer") { model.timer.cancel() }
            } else {
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
