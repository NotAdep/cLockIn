#if DEBUG
import AppKit
import CLockInCore
import SwiftUI

/// Renders each notch state to a PNG so the layout can be checked without screen recording.
/// Run a debug build with `--render-snapshots <directory>`.
@MainActor
enum SnapshotRenderer {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let geometry = NotchGeometry.current(allowVirtual: true) ?? .fallback

        func makeViewModel() -> NotchViewModel {
            let defaults = UserDefaults(suiteName: "cLockIn.snapshots.\(UUID().uuidString)")!
            let model = AppModel(settings: AppSettings(defaults: defaults), defaults: defaults)
            return NotchViewModel(model: model, geometry: geometry)
        }

        var states: [(String, NotchViewModel)] = []

        states.append(("1-closed", makeViewModel()))

        let hover = makeViewModel()
        hover.isHovering = true
        states.append(("2-closed-hover", hover))

        let compact = makeViewModel()
        compact.model.timer.setDuration(25 * 60)
        compact.model.timer.start()
        states.append(("3-compact-timer", compact))

        let compactFocus = makeViewModel()
        compactFocus.model.pomodoro.start()
        compactFocus.isHovering = true
        states.append(("4-compact-focus-hover", compactFocus))

        let expandedTimer = makeViewModel()
        expandedTimer.isExpanded = true
        states.append(("5-expanded-timer-idle", expandedTimer))

        let expandedPaused = makeViewModel()
        expandedPaused.model.timer.start()
        expandedPaused.model.timer.pause()
        expandedPaused.isExpanded = true
        states.append(("6-expanded-timer-paused", expandedPaused))

        let expandedFocus = makeViewModel()
        expandedFocus.model.pomodoro.start()
        expandedFocus.tab = .pomodoro
        expandedFocus.isExpanded = true
        states.append(("7-expanded-focus", expandedFocus))

        let typing = makeViewModel()
        typing.isExpanded = true
        typing.beginDurationEntry()
        for digit in "130" { typing.durationEntry?.append(digit) }
        states.append(("9-expanded-timer-typing", typing))

        let recents = makeViewModel()
        recents.model.timer.setDuration(90)
        recents.model.timer.start()
        recents.model.timer.cancel()
        recents.model.timer.setDuration(7 * 60)
        recents.isExpanded = true
        states.append(("10-expanded-timer-recents", recents))

        let alert = makeViewModel()
        alert.model.debugShowAlert(NotchAlert(
            title: "Focus complete", subtitle: "Up next: short break, 5m",
            symbol: Theme.symbol(for: .focus), tint: Theme.focus, action: .startNextPhase(.shortBreak)
        ))
        states.append(("8-alert", alert))

        for (name, viewModel) in states {
            write(canvas(for: viewModel, geometry: geometry), name: name, to: directory)
        }

        let editor = makeViewModel()
        editor.beginDurationEntry(for: .pomodoroSetting(.shortBreak))
        for digit in "730" { editor.durationEntry?.append(digit) }
        write(FocusEditorPreview(viewModel: editor), name: "11-focus-editor", to: directory)

        let focusTyping = makeViewModel()
        focusTyping.tab = .pomodoro
        focusTyping.isExpanded = true
        focusTyping.beginDurationEntry(for: .pomodoroDial)
        for digit in "5000" { focusTyping.durationEntry?.append(digit) }
        write(canvas(for: focusTyping, geometry: geometry), name: "12-focus-dial-typing", to: directory)

        let alertTimer = makeViewModel()
        alertTimer.model.debugShowAlert(NotchAlert(
            title: "Time's up", subtitle: "5m timer finished", symbol: "bell.fill", tint: Theme.timer
        ))
        write(canvas(for: alertTimer, geometry: geometry), name: "13-alert-timer", to: directory)

        // A Mac without a notch: the island hangs from the middle of the menu bar.
        let virtual = NotchGeometry.virtualPreview
        func makeVirtual() -> NotchViewModel {
            let viewModel = makeViewModel()
            viewModel.geometry = virtual
            return viewModel
        }
        let noNotchIdleHover = makeVirtual()
        noNotchIdleHover.isHovering = true
        write(canvas(for: noNotchIdleHover, geometry: virtual), name: "20-no-notch-hover", to: directory)
        let noNotchCompact = makeVirtual()
        noNotchCompact.model.timer.start()
        write(canvas(for: noNotchCompact, geometry: virtual), name: "21-no-notch-compact", to: directory)
        let noNotchExpanded = makeVirtual()
        noNotchExpanded.tab = .pomodoro
        noNotchExpanded.model.pomodoro.start()
        noNotchExpanded.isExpanded = true
        write(canvas(for: noNotchExpanded, geometry: virtual), name: "22-no-notch-expanded", to: directory)
    }

    private static func canvas(for viewModel: NotchViewModel, geometry: NotchGeometry) -> some View {
        let notch = geometry.notchSize
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.75), Color(white: 0.55)], startPoint: .top, endPoint: .bottom)
            Color(white: 0.85).frame(height: notch.height)
            NotchRootView(viewModel: viewModel)
            // Outline of the hardware notch, to check alignment.
            if geometry.hasHardwareNotch {
                Rectangle()
                    .stroke(Color.red.opacity(0.8), lineWidth: 0.5)
                    .frame(width: notch.width, height: notch.height)
            }
        }
        .frame(width: 700, height: 280)
    }

    private static func write(_ view: some View, name: String, to directory: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}

private struct FocusEditorPreview: View {
    let viewModel: NotchViewModel
    @Namespace private var namespace

    var body: some View {
        PomodoroPanel(viewModel: viewModel, namespace: namespace, isEditing: true)
            .padding(.horizontal, 26)
            .frame(width: 540, height: 156)
            .background(.black)
            .environment(\.colorScheme, .dark)
    }
}
#endif
