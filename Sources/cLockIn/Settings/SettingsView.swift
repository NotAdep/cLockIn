import AppKit
import CLockInCore
import ServiceManagement
import SwiftUI

/// A plain window for settings; SwiftUI's Settings scene is unreliable in an app with no Dock icon.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "cLockIn Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Play a sound when time is up", isOn: $settings.soundEnabled)
                Toggle("Also show macOS notification banners", isOn: $settings.systemNotificationsEnabled)
                Toggle("Haptic feedback when hovering the notch", isOn: $settings.hapticsEnabled)
            }

            Section("Notch") {
                Toggle("Show on displays without a notch", isOn: $settings.showOnScreensWithoutNotch)
                Toggle("Hide live activity in full-screen apps", isOn: $settings.hideInFullScreen)
                Toggle("Show countdown in the menu bar", isOn: $settings.showTimeInMenuBar)
            }

            Section("Focus (Pomodoro)") {
                minutesStepper("Focus", \.focus, range: 5...120, step: 5)
                minutesStepper("Short break", \.shortBreak, range: 1...30, step: 1)
                minutesStepper("Long break", \.longBreak, range: 5...60, step: 5)
                Stepper(
                    "Long break after \(model.pomodoro.config.roundsBeforeLongBreak) rounds",
                    value: configBinding(\.roundsBeforeLongBreak),
                    in: 2...8
                )
                Toggle("Start the next phase automatically", isOn: configBinding(\.autoAdvance))
            }

            Section {
                LabeledContent("cLockIn", value: version)
                LabeledContent("Made by", value: "NotAdep")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private func minutesStepper(
        _ title: String,
        _ keyPath: WritableKeyPath<PomodoroConfig, TimeInterval>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        let minutes = Binding<Int>(
            get: { Int(model.pomodoro.config[keyPath: keyPath] / 60) },
            set: { configBinding(keyPath).wrappedValue = TimeInterval($0 * 60) }
        )
        return Stepper("\(title): \(minutes.wrappedValue) min", value: minutes, in: range, step: step)
    }

    private func configBinding<Value>(_ keyPath: WritableKeyPath<PomodoroConfig, Value>) -> Binding<Value> {
        Binding(
            get: { model.pomodoro.config[keyPath: keyPath] },
            set: { newValue in
                var config = model.pomodoro.config
                config[keyPath: keyPath] = newValue
                model.pomodoro.updateConfig(config)
            }
        )
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
