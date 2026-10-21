import Foundation
import Observation

extension Notification.Name {
    /// Posted when a setting changes which screen the notch should appear on.
    static let notchPlacementSettingsChanged = Notification.Name("notchPlacementSettingsChanged")
    static let hotKeySettingChanged = Notification.Name("hotKeySettingChanged")
}

/// Which display the island lives on.
enum NotchDisplayChoice: String, CaseIterable, Identifiable {
    /// Whichever display the pointer is on, so it's always where you're working.
    case pointer
    /// Always the MacBook's own screen (falls back to the main display when the lid is closed).
    case builtIn

    var id: Self { self }

    var title: String {
        switch self {
        case .pointer: "Display you're using"
        case .builtIn: "Built-in display"
        }
    }
}

enum WorldClockStyle: String, CaseIterable, Identifiable {
    case analog, digital

    var id: Self { self }

    var title: String {
        switch self {
        case .analog: "Analog"
        case .digital: "Digital"
        }
    }

    var symbol: String {
        switch self {
        case .analog: "clock"
        case .digital: "textformat.123"
        }
    }
}

/// The global shortcut that opens the panel.
enum HotKeyChoice: String, CaseIterable, Identifiable {
    case controlOptionT
    case commandOptionT
    case controlOptionSpace
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .controlOptionT: "⌃⌥T"
        case .commandOptionT: "⌥⌘T"
        case .controlOptionSpace: "⌃⌥Space"
        case .off: "Off"
        }
    }
}

/// App preferences backed by UserDefaults.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let sound = "soundEnabled"
        static let haptics = "hapticsEnabled"
        static let virtualNotch = "showOnScreensWithoutNotch"
        static let hideInFullScreen = "hideInFullScreen"
        static let menuBarTime = "showTimeInMenuBar"
        static let notifications = "systemNotificationsEnabled"
        static let repeatSound = "repeatAlertSound"
        static let hotKey = "hotKey"
        static let display = "notchDisplay"
        static let snoozeMinutes = "snoozeMinutes"
        static let worldClockStyle = "worldClockStyle"
        static let checkForUpdates = "checkForUpdates"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.sound) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: Key.hideInFullScreen) } }
    var showTimeInMenuBar: Bool { didSet { defaults.set(showTimeInMenuBar, forKey: Key.menuBarTime) } }
    var systemNotificationsEnabled: Bool {
        didSet {
            defaults.set(systemNotificationsEnabled, forKey: Key.notifications)
            if systemNotificationsEnabled { NotificationService.shared.requestAuthorization() }
        }
    }
    var repeatAlertSound: Bool { didSet { defaults.set(repeatAlertSound, forKey: Key.repeatSound) } }
    var hotKey: HotKeyChoice {
        didSet {
            defaults.set(hotKey.rawValue, forKey: Key.hotKey)
            NotificationCenter.default.post(name: .hotKeySettingChanged, object: nil)
        }
    }
    var notchDisplay: NotchDisplayChoice {
        didSet {
            defaults.set(notchDisplay.rawValue, forKey: Key.display)
            NotificationCenter.default.post(name: .notchPlacementSettingsChanged, object: nil)
        }
    }
    var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: Key.checkForUpdates) } }
    var snoozeMinutes: Int { didSet { defaults.set(snoozeMinutes, forKey: Key.snoozeMinutes) } }
    var worldClockStyle: WorldClockStyle { didSet { defaults.set(worldClockStyle.rawValue, forKey: Key.worldClockStyle) } }
    var showOnScreensWithoutNotch: Bool {
        didSet {
            defaults.set(showOnScreensWithoutNotch, forKey: Key.virtualNotch)
            NotificationCenter.default.post(name: .notchPlacementSettingsChanged, object: nil)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.sound: true,
            Key.haptics: true,
            Key.virtualNotch: true,
            Key.hideInFullScreen: true,
            Key.menuBarTime: false,
            // Off by default: the notch alert is the notification.
            Key.notifications: false,
            Key.repeatSound: true,
            Key.hotKey: HotKeyChoice.controlOptionT.rawValue,
            Key.display: NotchDisplayChoice.pointer.rawValue,
            Key.snoozeMinutes: 9,
            Key.worldClockStyle: WorldClockStyle.analog.rawValue,
            Key.checkForUpdates: true,
        ])
        soundEnabled = defaults.bool(forKey: Key.sound)
        hapticsEnabled = defaults.bool(forKey: Key.haptics)
        showOnScreensWithoutNotch = defaults.bool(forKey: Key.virtualNotch)
        hideInFullScreen = defaults.bool(forKey: Key.hideInFullScreen)
        showTimeInMenuBar = defaults.bool(forKey: Key.menuBarTime)
        systemNotificationsEnabled = defaults.bool(forKey: Key.notifications)
        repeatAlertSound = defaults.bool(forKey: Key.repeatSound)
        hotKey = defaults.string(forKey: Key.hotKey).flatMap(HotKeyChoice.init(rawValue:)) ?? .controlOptionT
        notchDisplay = defaults.string(forKey: Key.display).flatMap(NotchDisplayChoice.init(rawValue:)) ?? .pointer
        checkForUpdates = defaults.bool(forKey: Key.checkForUpdates)
        snoozeMinutes = defaults.integer(forKey: Key.snoozeMinutes).clamped(to: 1...60)
        worldClockStyle = defaults.string(forKey: Key.worldClockStyle).flatMap(WorldClockStyle.init(rawValue:)) ?? .analog
    }
}
