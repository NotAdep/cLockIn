import AppKit
import CLockInCore
import ServiceManagement
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, notch, shortcut, alerts, timerFocus, alarms, worldClock, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .notch: "Notch"
        case .shortcut: "Keyboard"
        case .alerts: "Alerts & Sounds"
        case .timerFocus: "Timer & Focus"
        case .alarms: "Alarms"
        case .worldClock: "World Clock"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Startup and the menu bar."
        case .notch: "Where the island appears and when it stays out of the way."
        case .shortcut: "Open the panel and drive it without the mouse."
        case .alerts: "How cLockIn gets your attention when time is up."
        case .timerFocus: "Recent timers and the Pomodoro rhythm."
        case .alarms: "Snooze and how alarms behave around sleep."
        case .worldClock: "The cities in your notch and how they look."
        case .about: ""
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .notch: "rectangle.topthird.inset.filled"
        case .shortcut: "keyboard.fill"
        case .alerts: "bell.badge.fill"
        case .timerFocus: "timer"
        case .alarms: "alarm.fill"
        case .worldClock: "globe"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: Color(white: 0.55)
        case .notch: Color(white: 0.2)
        case .shortcut: Color(red: 0.35, green: 0.45, blue: 0.6)
        case .alerts: Color(red: 0.95, green: 0.3, blue: 0.3)
        case .timerFocus: Theme.timer
        case .alarms: Theme.alarm
        case .worldClock: Color(red: 0.55, green: 0.4, blue: 0.95)
        case .about: Color(red: 0.25, green: 0.55, blue: 1.0)
        }
    }

    /// Sidebar groups, like System Settings.
    static let groups: [[SettingsSection]] = [
        [.general, .notch, .shortcut, .alerts],
        [.timerFocus, .alarms, .worldClock],
        [.about],
    ]
}

/// A plain window for settings; SwiftUI's Settings scene is unreliable in an app with no Dock icon.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private(set) var window: NSWindow?
    private let selection = SettingsSelection()

    func show(model: AppModel, section: SettingsSection? = nil) {
        if let section { selection.section = section }
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model, selection: selection))
            let window = NSWindow(contentViewController: controller)
            window.title = "cLockIn Settings"
            window.titleVisibility = .hidden
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

#if DEBUG
extension SettingsWindowController {
    /// Opens a section and saves the window's contents as a PNG, drawn in-process (no screen recording needed).
    func debugCapture(model: AppModel, section: SettingsSection, to url: URL) {
        show(model: model, section: section)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard let view = window?.contentView?.superview ?? window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}
#endif

@MainActor
@Observable
final class SettingsSelection {
    var section: SettingsSection = .general
}

struct SettingsView: View {
    let model: AppModel
    @Bindable var selection: SettingsSelection

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection.section)
                .frame(width: 220)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.6).ignoresSafeArea())
            Divider().ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
                .id(selection.section)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.15), value: selection.section)
        .frame(width: 760, height: 540)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.section {
        case .general: GeneralPane(model: model)
        case .notch: NotchPane(settings: model.settings)
        case .shortcut: KeyboardPane(settings: model.settings)
        case .alerts: AlertsPane(model: model)
        case .timerFocus: TimerFocusPane(model: model)
        case .alarms: AlarmsPane(model: model)
        case .worldClock: WorldClockPane(model: model)
        case .about: AboutPane()
        }
    }
}

// MARK: Building blocks

/// The section list, styled like the System Settings sidebar.
private struct Sidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.groups.indices, id: \.self) { index in
                if index > 0 { Spacer().frame(height: 12) }
                ForEach(SettingsSection.groups[index]) { section in
                    SidebarRow(section: section, isSelected: selection == section) {
                        selection = section
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                IconTile(symbol: section.symbol, color: section.color, size: 22)
                Text(section.title)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A white symbol on a rounded, softly shaded colour tile, like System Settings.
private struct IconTile: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
    }
}

/// The large icon, title and one-line description at the top of each pane.
private struct PaneHeader: View {
    let section: SettingsSection

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: section.symbol, color: section.color, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).font(.title2.weight(.semibold))
                Text(section.subtitle).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }
}

/// A grouped form under a pane header.
private struct Pane<Content: View>: View {
    let section: SettingsSection
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(section: section)
            Form { content }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
    }
}

/// "Title ······ value  [− +]".
private struct ValueStepper: View {
    let title: String
    let value: String
    @Binding var number: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        Stepper(value: $number, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
            }
        }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            )
    }
}

// MARK: Panes

private struct GeneralPane: View {
    let model: AppModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        @Bindable var settings = model.settings
        Pane(section: .general) {
            Section {
                Toggle(isOn: $launchAtLogin) {
                    Text("Open at login")
                    Text("Start cLockIn automatically when you log in.")
                }
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Label(launchError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Works best once cLockIn is in your Applications folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                Toggle(isOn: $settings.showTimeInMenuBar) {
                    Text("Show countdown next to the icon")
                    Text("Handy on displays where the notch isn't visible.")
                }
            }

            SoftwareUpdateSection(updates: model.updates, settings: settings)
        }
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
            launchError = "Couldn't update the login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct SoftwareUpdateSection: View {
    let updates: UpdateService
    @Bindable var settings: AppSettings

    var body: some View {
        Section {
            HStack(spacing: 12) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if case .checking = updates.state {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Check Now") { Task { await updates.check() } }
                }
            }

            if let update = updates.availableUpdate {
                HStack {
                    Button("Download \(update.version)") { updates.download(update) }
                        .buttonStyle(.borderedProminent)
                    Button("Release Notes") { updates.openReleaseNotes(update) }
                    Spacer()
                    Button("Skip This Version") { updates.skip(update) }
                }
            }

            Toggle(isOn: $settings.checkForUpdates) {
                Text("Check for updates automatically")
                Text("Once a day, cLockIn asks GitHub for its latest release. Nothing about you or your Mac is sent.")
            }
        } header: {
            Text("Software Update")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        let (symbol, color): (String, Color) = switch updates.state {
        case .available: ("arrow.down.circle.fill", .accentColor)
        case .failed: ("exclamationmark.triangle.fill", .orange)
        case .upToDate: ("checkmark.circle.fill", .green)
        case .idle, .checking: ("arrow.triangle.2.circlepath.circle.fill", .secondary)
        }
        Image(systemName: symbol)
            .font(.system(size: 22))
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
    }

    private var title: String {
        switch updates.state {
        case .available(let update) where updates.availableUpdate != nil: "cLockIn \(update.version) is available"
        case .failed: "Couldn't check for updates"
        case .checking: "Checking for updates…"
        default: "cLockIn \(UpdateService.currentVersion)"
        }
    }

    private var detail: String {
        if case .failed(let message) = updates.state { return message }
        if updates.availableUpdate != nil { return "You have \(UpdateService.currentVersion)." }
        guard let lastChecked = updates.lastChecked else { return "Not checked yet." }
        let ago = lastChecked.formatted(.relative(presentation: .named))
        return updates.state == .upToDate ? "Up to date. Checked \(ago)." : "Last checked \(ago)."
    }
}

private struct NotchPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Pane(section: .notch) {
            Section("Display") {
                Picker("Show the island on", selection: $settings.notchDisplay) {
                    ForEach(NotchDisplayChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle(isOn: $settings.showOnScreensWithoutNotch) {
                    Text("Show on displays without a notch")
                    Text("Draws a small island at the top of the screen instead.")
                }
            }

            Section("Behavior") {
                Toggle(isOn: $settings.hideInFullScreen) {
                    Text("Hide live activities in full-screen apps")
                    Text("Finished alerts still appear.")
                }
                Toggle(isOn: $settings.hapticsEnabled) {
                    Text("Haptic feedback on hover")
                    Text("A light tap from the trackpad when the pointer reaches the island.")
                }
            }
        }
    }
}

private struct KeyboardPane: View {
    @Bindable var settings: AppSettings

    private let keys: [([String], String)] = [
        (["Space"], "Start or pause"),
        (["←", "→"], "Switch tabs"),
        (["⌘1", "…", "⌘5"], "Jump to a tab"),
        (["0", "…", "9"], "Type a duration or alarm time"),
        (["↩"], "Start what you typed, or save an alarm"),
        (["L"], "Lap the stopwatch"),
        (["R"], "Reset the stopwatch"),
        (["esc"], "Cancel typing, then close"),
    ]

    var body: some View {
        Pane(section: .shortcut) {
            Section {
                Picker("Open the panel with", selection: $settings.hotKey) {
                    ForEach(HotKeyChoice.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Works from any app. Press it again to close the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While the panel is open from the keyboard") {
                ForEach(keys, id: \.1) { combo, action in
                    HStack {
                        Text(action)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(combo, id: \.self) { key in
                                if key == "…" {
                                    Text("–").foregroundStyle(.secondary)
                                } else {
                                    KeyCap(label: key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct AlertsPane: View {
    let model: AppModel

    var body: some View {
        @Bindable var settings = model.settings
        Pane(section: .alerts) {
            Section("Sound") {
                Toggle("Play a sound when time is up", isOn: $settings.soundEnabled)
                Toggle(isOn: $settings.repeatAlertSound) {
                    Text("Keep chiming until I respond")
                    Text("Timers chime three more times, ten seconds apart.")
                }
                .disabled(!settings.soundEnabled)
            }

            Section {
                Toggle(isOn: $settings.systemNotificationsEnabled) {
                    Text("Also show macOS notification banners")
                    Text("Off by default: the notch is the notification.")
                }
            }

            Section {
                HStack {
                    Text("Try it")
                    Spacer()
                    Button("Timer alert") { model.previewAlert() }
                    Button("Alarm") { model.previewAlert(alarm: true) }
                }
            } footer: {
                Text("Shows a sample alert in the notch. Dismiss it there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TimerFocusPane: View {
    let model: AppModel

    var body: some View {
        Pane(section: .timerFocus) {
            Section("Timer") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recent custom timers")
                        Text(model.timer.recentDurations.isEmpty
                             ? "None yet. Type a duration in the Timer tab."
                             : model.timer.recentDurations.map(TimeFormat.short).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear") { model.timer.clearRecents() }
                        .disabled(model.timer.recentDurations.isEmpty)
                }
            }

            Section {
                ValueStepper(title: "Focus", value: TimeFormat.short(model.pomodoro.config.focus), number: minutes(\.focus), range: 1...180, step: 5)
                ValueStepper(title: "Short break", value: TimeFormat.short(model.pomodoro.config.shortBreak), number: minutes(\.shortBreak), range: 1...60)
                ValueStepper(title: "Long break", value: TimeFormat.short(model.pomodoro.config.longBreak), number: minutes(\.longBreak), range: 1...120, step: 5)
                ValueStepper(
                    title: "Long break after",
                    value: "\(model.pomodoro.config.roundsBeforeLongBreak) rounds",
                    number: config(\.roundsBeforeLongBreak),
                    range: 2...8
                )
                Toggle("Start the next phase automatically", isOn: config(\.autoAdvance))
            } header: {
                Text("Focus")
            } footer: {
                Text("You can also type exact lengths, including seconds, in the Focus tab of the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func minutes(_ keyPath: WritableKeyPath<PomodoroConfig, TimeInterval>) -> Binding<Int> {
        let seconds = config(keyPath)
        return Binding(get: { Int(seconds.wrappedValue / 60) }, set: { seconds.wrappedValue = TimeInterval($0 * 60) })
    }

    private func config<Value>(_ keyPath: WritableKeyPath<PomodoroConfig, Value>) -> Binding<Value> {
        Binding(
            get: { model.pomodoro.config[keyPath: keyPath] },
            set: { newValue in
                var config = model.pomodoro.config
                config[keyPath: keyPath] = newValue
                model.pomodoro.updateConfig(config)
            }
        )
    }
}

private struct AlarmsPane: View {
    let model: AppModel

    var body: some View {
        Pane(section: .alarms) {
            Section {
                ValueStepper(
                    title: "Snooze for",
                    value: "\(model.settings.snoozeMinutes) min",
                    number: Binding(get: { model.settings.snoozeMinutes }, set: { model.setSnoozeMinutes($0) }),
                    range: 1...60
                )
            } footer: {
                Text("You can also change it in the Alarms tab of the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Your alarms") {
                if model.alarms.alarms.isEmpty {
                    Text("No alarms yet. Add one from the Alarms tab in the notch.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.alarms.alarms) { alarm in
                    Toggle(isOn: Binding(get: { alarm.isEnabled }, set: { model.alarms.setEnabled($0, for: alarm.id) })) {
                        Text(AlarmTimeText.format(hour: alarm.hour, minute: alarm.minute))
                            .monospacedDigit()
                        Text("\(alarm.label) · \(alarm.repeatSummary())")
                    }
                    .tint(Theme.alarm)
                }
            }

            Section {
                Label {
                    Text("Alarms ring while your Mac is awake. If it was asleep, an alarm still rings on wake when it's at most 5 minutes late; later than that it's skipped quietly.")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.alarm)
                }
                .font(.callout)
            }
        }
    }
}

private struct WorldClockPane: View {
    let model: AppModel
    @State private var query = ""
    private static let allCities = WorldClock.allCities

    var body: some View {
        @Bindable var settings = model.settings
        Pane(section: .worldClock) {
            Section("Style") {
                HStack(spacing: 12) {
                    ForEach(WorldClockStyle.allCases) { style in
                        StyleCard(style: style, isSelected: settings.worldClockStyle == style) {
                            settings.worldClockStyle = style
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                if model.worldClocks.isEmpty {
                    Text("No cities yet").foregroundStyle(.secondary)
                }
                ForEach(model.worldClocks) { city in
                    CityRow(city: city) { model.removeWorldClock(city) }
                }
                .onMove { model.moveWorldClocks(from: $0, to: $1) }
            } header: {
                Text("Your cities")
            } footer: {
                Text("The notch shows the first \(WorldClockPanel.maxShown). Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Add a city") {
                TextField("Search", text: $query, prompt: Text("Search for a city"))
                ForEach(WorldClock.search(query, in: Self.allCities).filter { !model.worldClocks.contains($0) }.prefix(5)) { city in
                    Button {
                        model.addWorldClock(city)
                        query = ""
                    } label: {
                        HStack {
                            Text(city.name)
                            Text(WorldClock.relation(of: city.timeZone)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StyleCard: View {
    let style: WorldClockStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black)
                    switch style {
                    case .analog:
                        AnalogClock(date: Date(), timeZone: .current, isDaytime: true)
                            .frame(width: 44, height: 44)
                    case .digital:
                        Text(Date().formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
                .frame(height: 62)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
                }
                Text(style.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CityRow: View {
    let city: WorldClockCity
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AnalogClock(date: Date(), timeZone: city.timeZone, isDaytime: WorldClock.isDaytime(in: city.timeZone))
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(city.name)
                Text(WorldClock.relation(of: city.timeZone)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(time)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove \(city.name)")
        }
    }

    private var time: String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = city.timeZone
        return Date().formatted(style)
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            Text("cLockIn")
                .font(.largeTitle.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("Timer, Focus, Stopwatch, World Clock and Alarms, living in your notch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            Text("Made by NotAdep")
                .font(.callout.weight(.medium))
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
