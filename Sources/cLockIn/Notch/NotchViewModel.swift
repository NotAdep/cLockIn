import AppKit
import CLockInCore
import Observation
import SwiftUI

enum NotchPresentation: Equatable {
    /// Hidden behind the hardware notch.
    case closed
    /// A live activity: ring on the left, time on the right.
    case compact
    /// Something just finished.
    case alert
    /// The full panel.
    case expanded
}

/// What a typed duration will be applied to.
enum DurationTarget: Equatable {
    case timer
    /// The Focus dial: sets the current phase's length, and Return starts it.
    case pomodoroDial
    /// A row in the Focus duration editor.
    case pomodoroSetting(PomodoroPhase)
}

/// Something in the panel that changes value when you scroll over it.
enum ScrollTarget: Hashable {
    case timerDuration
    case pomodoroSetting(PomodoroPhase)
}

enum ExpandedTab: String, CaseIterable, Identifiable {
    case timer, pomodoro

    var id: Self { self }

    var title: String {
        switch self {
        case .timer: "Timer"
        case .pomodoro: "Focus"
        }
    }

    var symbol: String {
        switch self {
        case .timer: "timer"
        case .pomodoro: "brain.head.profile"
        }
    }
}

/// Decides which shape the notch takes and how big it is.
@MainActor
@Observable
final class NotchViewModel {
    enum Metrics {
        static let compactSideWidth: CGFloat = 74
        static let expandedSideMin: CGFloat = 168
        static let expandedMinWidth: CGFloat = 540
        static let expandedContentHeight: CGFloat = 180
        static let alertContentHeight: CGFloat = 56
    }

    let model: AppModel
    var geometry: NotchGeometry
    var isHovering = false
    var isExpanded = false
    var tab: ExpandedTab = .timer
    /// True while a full-screen app is in front and the live activity should stay out of the way.
    var isSuppressed = false
    /// Non-nil while the user is typing a custom duration.
    var durationEntry: DurationDigits?
    var durationTarget: DurationTarget = .timer
    /// Where each scrollable control sits, in the panel's SwiftUI coordinates. Scrolling is handled here
    /// rather than by AppKit views inside the panel, which would make its animations stutter.
    @ObservationIgnored var scrollRegions: [ScrollTarget: CGRect] = [:]
    @ObservationIgnored private var scrollAccumulator: CGFloat = 0

    init(model: AppModel, geometry: NotchGeometry) {
        self.model = model
        self.geometry = geometry
    }

    var presentation: NotchPresentation {
        if model.alert != nil { return .alert }
        if isExpanded { return .expanded }
        if model.liveKind != nil && !isSuppressed { return .compact }
        return .closed
    }

    var notchSize: CGSize { geometry.notchSize }

    /// Size of the flat body, not counting the outward curves at the top.
    var bodySize: CGSize {
        let notch = notchSize
        switch presentation {
        case .closed:
            return isHovering ? CGSize(width: notch.width + 28, height: notch.height + 6) : notch
        case .compact:
            let width = notch.width + 2 * Metrics.compactSideWidth
            return isHovering ? CGSize(width: width + 20, height: notch.height + 5) : CGSize(width: width, height: notch.height)
        case .alert:
            return CGSize(width: max(notch.width + 2 * 120, 420), height: notch.height + Metrics.alertContentHeight)
        case .expanded:
            return Self.expandedBodySize(for: notch)
        }
    }

    static func expandedBodySize(for notch: CGSize) -> CGSize {
        CGSize(
            width: max(notch.width + 2 * Metrics.expandedSideMin, Metrics.expandedMinWidth),
            height: notch.height + Metrics.expandedContentHeight
        )
    }

    var topRadius: CGFloat {
        switch presentation {
        case .closed, .compact: 6
        case .alert, .expanded: 12
        }
    }

    var bottomRadius: CGFloat {
        switch presentation {
        case .closed: isHovering ? 12 : 10
        case .compact: isHovering ? 15 : 12
        case .alert: 24
        case .expanded: 32
        }
    }

    var shapeSize: CGSize {
        CGSize(width: bodySize.width + 2 * topRadius, height: bodySize.height)
    }

    /// When idle, nothing is drawn at all: the hardware notch is darker than any black an LCD can show,
    /// so even a perfectly aligned black shape would be visible around its edges.
    var isShapeVisible: Bool {
        presentation != .closed || isHovering
    }

    /// Every change of state springs, with a little overshoot when growing and shrinking alike.
    var shapeAnimation: Animation {
        switch presentation {
        case .expanded, .alert: Motion.open
        case .compact: Motion.compact
        case .closed: Motion.close
        }
    }

    /// The area that counts as "over the notch", in screen coordinates.
    var hitRect: CGRect {
        let size = shapeSize
        let frame = geometry.screenFrame
        let rect = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        // A little slack around the small states makes the notch easier to reach.
        return presentation == .closed || presentation == .compact ? rect.insetBy(dx: -8, dy: -4) : rect
    }

    func tapped() {
        switch presentation {
        case .alert:
            model.dismissAlert()
        case .closed, .compact:
            expand()
        case .expanded:
            break
        }
    }

    func expand() {
        switch model.liveKind {
        case .timer: tab = .timer
        case .pomodoro: tab = .pomodoro
        case nil: break
        }
        isExpanded = true
    }

    func collapse() {
        commitDurationEntry(start: false)
        isExpanded = false
    }

    // MARK: Typed duration

    var isEditingDuration: Bool { durationEntry != nil }

    func isEditing(_ target: DurationTarget) -> Bool {
        durationEntry != nil && durationTarget == target
    }

    func beginDurationEntry(for target: DurationTarget = .timer) {
        switch target {
        case .timer: guard !model.timer.isActive else { return }
        case .pomodoroDial: guard !model.pomodoro.isActive else { return }
        case .pomodoroSetting: break
        }
        // Switching fields keeps what was typed in the previous one.
        commitDurationEntry(start: false)
        durationTarget = target
        durationEntry = DurationDigits()
    }

    /// Applies what was typed (if anything). `start` only applies to the timer and the Focus dial.
    func commitDurationEntry(start: Bool) {
        guard let entry = durationEntry else { return }
        durationEntry = nil
        let typed = !entry.isEmpty && entry.duration > 0 ? entry.duration : nil

        switch durationTarget {
        case .timer:
            if let typed { model.timer.setDuration(typed) }
            if start { model.timer.start() }
        case .pomodoroDial:
            if let typed { setPomodoroDuration(typed, for: model.pomodoro.phase) }
            if start { model.pomodoro.start() }
        case .pomodoroSetting(let phase):
            if let typed { setPomodoroDuration(typed, for: phase) }
        }
    }

    private func setPomodoroDuration(_ duration: TimeInterval, for phase: PomodoroPhase) {
        var config = model.pomodoro.config
        let value = duration.clamped(to: TimerEngine.durationRange)
        switch phase {
        case .focus: config.focus = value
        case .shortBreak: config.shortBreak = value
        case .longBreak: config.longBreak = value
        }
        model.pomodoro.updateConfig(config)
    }

    func cancelDurationEntry() {
        durationEntry = nil
    }

    // MARK: Scrolling

    /// Scroll input at a point in the panel's SwiftUI coordinates. Returns true when a control used it.
    func handleScroll(_ event: NSEvent, at point: CGPoint) -> Bool {
        guard presentation == .expanded,
              let target = scrollRegions.first(where: { $0.value.contains(point) })?.key else {
            scrollAccumulator = 0
            return false
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 12 : event.scrollingDeltaY
        scrollAccumulator += event.isDirectionInvertedFromDevice ? -delta : delta
        while abs(scrollAccumulator) >= 1 {
            let step = scrollAccumulator > 0 ? 1 : -1
            scrollAccumulator -= CGFloat(step)
            applyScroll(step, to: target)
        }
        if event.phase == .ended || event.momentumPhase == .ended { scrollAccumulator = 0 }
        return true
    }

    private func applyScroll(_ step: Int, to target: ScrollTarget) {
        switch target {
        case .timerDuration:
            guard !model.timer.isActive, !isEditing(.timer) else { return }
            model.timer.adjustDuration(by: TimeInterval(step) * 60)
        case .pomodoroSetting(let phase):
            guard !isEditing(.pomodoroSetting(phase)) else { return }
            stepPomodoroDuration(for: phase, by: step)
        }
    }

    /// One-minute steps, five-minute steps past an hour; snaps to whole minutes after typing odd seconds.
    func stepPomodoroDuration(for phase: PomodoroPhase, by direction: Int) {
        let value = model.pomodoro.config.duration(for: phase)
        let minutes = (value / 60).rounded(direction > 0 ? .down : .up)
        let size: Double = minutes + Double(direction) > 60 || (direction < 0 && minutes > 60) ? 5 : 1
        let next = ((minutes + Double(direction) * size) * 60).clamped(to: 60...TimerEngine.durationRange.upperBound)
        setPomodoroDuration(next, for: phase)
    }

    /// Keyboard input while typing a duration. Returns true when the key was used.
    func handleKey(_ event: NSEvent) -> Bool {
        guard durationEntry != nil else { return false }
        switch event.keyCode {
        case 36, 76: // Return, Enter
            commitDurationEntry(start: true)
        case 53: // Escape
            cancelDurationEntry()
        case 51, 117: // Delete, Forward delete
            durationEntry?.deleteLast()
        default:
            guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty,
                  characters.allSatisfy(\.isNumber) else { return false }
            for character in characters { durationEntry?.append(character) }
        }
        return true
    }
}
