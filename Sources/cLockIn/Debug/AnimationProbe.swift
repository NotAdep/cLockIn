#if DEBUG
import AppKit
import QuartzCore

/// Measures frame pacing while the notch animates, so animation smoothness can be compared with numbers.
/// Drive it from another process:
///   DistributedNotificationCenter post "com.notadep.cLockIn.debug" with object "open-timer|/path/to/log.txt"
/// Commands: open-<tab> (timer, pomodoro, stopwatch, worldClock, alarms), close,
/// settings-<section>|<png path> (captures the Settings window at that section),
/// start-timer, start-stopwatch, pin-open-<tab> (opens and keeps the panel open), stop-all.
@MainActor
final class AnimationProbe: NSObject {
    static let shared = AnimationProbe()
    static let notification = Notification.Name("com.notadep.cLockIn.debug")

    private weak var controller: NotchController?
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []

    func install(controller: NotchController) {
        self.controller = controller
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(received(_:)), name: Self.notification, object: nil
        )
    }

    @objc private func received(_ notification: Notification) {
        guard let raw = notification.object as? String else { return }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        let output = parts.count > 1 ? URL(fileURLWithPath: parts[1]) : nil
        let command = parts[0]
        if command.hasPrefix("settings-"), let section = SettingsSection(rawValue: String(command.dropFirst(9))),
           let model = controller?.viewModel.model, let output {
            SettingsWindowController.shared.debugCapture(model: model, section: section, to: output)
            return
        }
        if let model = controller?.viewModel.model {
            switch command {
            case "start-timer": model.timer.setDuration(25 * 60); model.timer.start(); return
            case "start-stopwatch": model.stopwatch.start(); return
            case "stop-all":
                model.timer.cancel()
                model.stopwatch.reset()
                model.pomodoro.reset()
                model.dismissAlert()
                controller?.debugPinned = false
                controller?.debugClose()
                return
            case "menubar-time-on": model.settings.showTimeInMenuBar = true; return
            case "menubar-time-off": model.settings.showTimeInMenuBar = false; return
            case "pin-open-timer", "pin-open-stopwatch", "pin-open-worldClock":
                controller?.debugPinned = true
                controller?.debugOpen(tab: ExpandedTab(rawValue: String(command.dropFirst(9))) ?? .timer)
                return
            default: break
            }
        }
        if command == "close" {
            controller?.debugClose()
        } else if command.hasPrefix("open-"), let tab = ExpandedTab(rawValue: String(command.dropFirst(5))) {
            controller?.debugOpen(tab: tab)
        } else {
            return
        }
        measure(label: parts[0], output: output)
    }

    private func measure(label: String, output: URL?) {
        guard let view = controller?.debugContentView else { return }
        link?.invalidate()
        stamps = []
        let link = view.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            link.invalidate()
            self.report(label: label, output: output)
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        stamps.append(link.timestamp)
    }

    private func report(label: String, output: URL?) {
        let intervals = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }
        let slow = intervals.filter { $0 > 25 }
        let line = String(
            format: "%@ frames=%d max=%.1fms over25ms=%d worst=[%@]\n",
            label, intervals.count, intervals.max() ?? 0, slow.count,
            slow.sorted(by: >).prefix(5).map { String(format: "%.0f", $0) }.joined(separator: ",")
        )
        guard let output else { return print(line, terminator: "") }
        if let handle = try? FileHandle(forWritingTo: output) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: output)
        }
    }
}
#endif
