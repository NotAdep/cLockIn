import AppKit

enum SoundService {
    @MainActor
    static func playChime() {
        NSSound(named: "Glass")?.play()
    }
}
