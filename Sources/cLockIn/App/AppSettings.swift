import Foundation
import Observation

extension Notification.Name {
    /// Posted when a setting changes which screen the notch should appear on.
    static let notchPlacementSettingsChanged = Notification.Name("notchPlacementSettingsChanged")
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
        ])
        soundEnabled = defaults.bool(forKey: Key.sound)
        hapticsEnabled = defaults.bool(forKey: Key.haptics)
        showOnScreensWithoutNotch = defaults.bool(forKey: Key.virtualNotch)
        hideInFullScreen = defaults.bool(forKey: Key.hideInFullScreen)
        showTimeInMenuBar = defaults.bool(forKey: Key.menuBarTime)
        systemNotificationsEnabled = defaults.bool(forKey: Key.notifications)
    }
}
