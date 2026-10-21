#if DEBUG
import AppKit
import QuartzCore

/// Measures frame pacing while the notch animates, so animation smoothness can be compared with numbers.
/// Drive it from another process:
///   DistributedNotificationCenter post "com.notadep.cLockIn.debug" with object "open-timer|/path/to/log.txt"
/// Commands: open-<tab> (timer, pomodoro, stopwatch, worldClock, alarms), close,
/// settings-<section>|<png path> (captures the Settings window at that section),
/// start-timer, start-stopwatch, start-focus, rolling-on/off, pin-open-<tab> (opens and keeps the panel open), stop-all.
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
            case "start-focus":
                var config = model.pomodoro.config
                config.focus = 25 * 60
                model.pomodoro.updateConfig(config)
                model.pomodoro.start()
                return
            case "keyboard-open": controller?.debugOpenFromKeyboard(); return
            case "rolling-on": model.settings.rollingDigitsInPanel = true; return
            case "rolling-off": model.settings.rollingDigitsInPanel = false; return
            case "stop-all":
                model.timer.cancelAll()
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
        if command == "panel-key-test", let controller, let output {
            controller.debugOpenFromKeyboard()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard let panel = controller.debugPanel else { return }
                controller.viewModel.select(.timer)
                for text in ["7", "5"] {
                    if let event = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: panel.windowNumber, context: nil, characters: text,
                        charactersIgnoringModifiers: text, isARepeat: false, keyCode: text == "7" ? 26 : 23
                    ) { NSApp.postEvent(event, atStart: false) }
                }
                try? await Task.sleep(for: .milliseconds(400))
                let report = "panelIsKey=\(panel.isKeyWindow) typed=\(controller.viewModel.durationEntry?.digits ?? "nothing")\n"
                try? report.write(to: output, atomically: true, encoding: .utf8)
                controller.debugClose()
            }
            return
        }
        if command == "type-test", let model = controller?.viewModel.model, let output {
            typeTest(model: model, output: output)
            return
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

    /// Opens the statistics window, types into its label field from inside the app, and reports what arrived.
    private func typeTest(model: AppModel, output: URL) {
        FocusStatsWindowController.shared.show(model: model, editingLabels: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard let window = FocusStatsWindowController.shared.window,
                  let field = Self.firstTextField(in: window.contentView) else {
                try? "no window or text field\n".write(to: output, atomically: true, encoding: .utf8)
                return
            }
            let focused = window.makeFirstResponder(field)
            for character in "Deep 1" {
                let text = String(character)
                let code: UInt16 = character == " " ? 49 : character == "1" ? 18 : 0
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: text,
                        charactersIgnoringModifiers: text, isARepeat: false, keyCode: code
                    ) { NSApp.postEvent(event, atStart: false) }
                }
            }
            try? await Task.sleep(for: .milliseconds(600))
            let editor = window.firstResponder as? NSTextView
            let report = """
            appActive=\(NSApp.isActive) statsIsKey=\(window.isKeyWindow) keyWindow=\(NSApp.keyWindow?.title ?? "none")
            madeFirstResponder=\(focused) firstResponder=\(type(of: window.firstResponder as Any))
            fieldValue="\(field.stringValue)" editorText="\(editor?.string ?? "-")"
            notchTyping=\(controller?.viewModel.isEditingDuration ?? false) keyboardSession=\(controller?.viewModel.isKeyboardSession ?? false)

            """
            try? report.write(to: output, atomically: true, encoding: .utf8)
        }
    }

    private static func firstTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
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
