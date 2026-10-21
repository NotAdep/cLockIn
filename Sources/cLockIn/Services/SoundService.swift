import AppKit

enum SoundService {
    enum Sound {
        /// Timers and Focus phases finishing.
        case chime
        /// Alarms: brighter, and repeated more often.
        case alarm

        var name: String {
            switch self {
            case .chime: "Glass"
            case .alarm: "Hero"
            }
        }
    }

    @MainActor
    static func play(_ sound: Sound) {
        NSSound(named: sound.name)?.play()
    }
}
