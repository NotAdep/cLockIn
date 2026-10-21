import AppKit

/// Trackpad taps. macOS only plays them while a finger is on a Force Touch trackpad, not with a mouse.
@MainActor
enum HapticService {
    /// A firm tap: "level change" is the strongest pattern macOS offers to apps.
    static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
