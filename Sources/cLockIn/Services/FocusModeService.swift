import AppKit

/// Turns Do Not Disturb on and off by running two shortcuts the user makes in the Shortcuts app.
/// macOS has no public way for an app to change Focus itself; Shortcuts' "Set Focus" action can.
enum FocusModeService {
    static let defaultOnShortcut = "cLockIn Focus On"
    static let defaultOffShortcut = "cLockIn Focus Off"

    /// Runs a shortcut by name in the background. Failures (a missing shortcut, say) are ignored.
    static func run(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Names of the user's shortcuts, to check the two exist.
    static func installedShortcuts() async -> Set<String> {
        await Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            return Set(names)
        }.value
    }

    static func openShortcutsApp() {
        NSWorkspace.shared.open(URL(string: "shortcuts://")!)
    }
}
