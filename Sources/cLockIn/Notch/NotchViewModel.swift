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
    /// The time of the alarm being edited, typed as HHMM.
    case alarmTime
}

/// Something in the panel that changes value when you scroll over it.
enum ScrollTarget: Hashable {
    case timerDuration
    case pomodoroSetting(PomodoroPhase)
    case alarmHour
    case alarmMinute
    case snoozeLength
}

enum ExpandedTab: String, CaseIterable, Identifiable {
    case timer, pomodoro, stopwatch, worldClock, alarms

    var id: Self { self }

    var title: String {
        switch self {
        case .timer: "Timer"
        case .pomodoro: "Focus"
        case .stopwatch: "Stopwatch"
        case .worldClock: "World Clock"
        case .alarms: "Alarms"
        }
    }

    var symbol: String {
        switch self {
        case .timer: "timer"
        case .pomodoro: "brain.head.profile"
        case .stopwatch: "stopwatch"
        case .worldClock: "globe"
        case .alarms: "alarm"
        }
    }

    var tint: Color {
        switch self {
        case .timer: Theme.timer
        case .pomodoro: Theme.focus
        case .stopwatch: Theme.stopwatch
        case .worldClock: Theme.worldClock
        case .alarms: Theme.alarm
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
    /// True when the panel was opened from the keyboard shortcut, so it takes keys until it closes.
    var isKeyboardSession = false
    /// The alarm being added or edited in the Alarms tab.
    var alarmDraft: Alarm?
    var isNewAlarm = false
    /// Where each scrollable control sits, in the panel's SwiftUI coordinates. Scrolling is handled here
    /// rather than by AppKit views inside the panel, which would make its animations stutter.
    @ObservationIgnored var scrollRegions: [ScrollTarget: CGRect] = [:]
    @ObservationIgnored private var scrollAccumulator: CGFloat = 0

    init(model: AppModel, geometry: NotchGeometry) {
        self.model = model
        self.geometry = geometry
    }

    var presentation: NotchPresentation {
        if model.alert != nil && !model.isAlertMinimized { return .alert }
        if isExpanded { return .expanded }
        // A finished-but-unanswered reminder shows even over full-screen apps.
        if model.liveKind == .finished { return .compact }
        if model.liveKind != nil && !isSuppressed { return .compact }
        return .closed
    }

    /// Whether the panel should take keyboard focus right now.
    var wantsKeyboard: Bool {
        presentation == .expanded && (isEditingDuration || isKeyboardSession)
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
        case .compact where model.liveKind == .finished:
            model.restoreAlert()
        case .closed, .compact:
            expand()
        case .expanded:
            break
        }
    }

    func expand() {
        // Pick the tab without animating the switch; the panel is about to bloom in anyway.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch model.liveKind {
            case .timer: tab = .timer
            case .pomodoro: tab = .pomodoro
            case .stopwatch: tab = .stopwatch
            case .finished, nil: break
            }
        }
        isExpanded = true
    }

    func collapse() {
        commitDurationEntry(start: false)
        isKeyboardSession = false
        isExpanded = false
    }

    func select(_ newTab: ExpandedTab) {
        guard newTab != tab else { return }
        cancelDurationEntry()
        tab = newTab
    }

    // MARK: Alarm editing

    func beginNewAlarm() {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: model.now) ?? model.now
        alarmDraft = Alarm(hour: Calendar.current.component(.hour, from: next), minute: 0, repeatDays: [])
        isNewAlarm = true
    }

    func edit(_ alarm: Alarm) {
        alarmDraft = alarm
        isNewAlarm = false
    }

    func saveAlarmDraft() {
        commitDurationEntry(start: false)
        guard var draft = alarmDraft else { return }
        draft.isEnabled = true
        isNewAlarm ? model.alarms.add(draft) : model.alarms.update(draft)
        alarmDraft = nil
    }

    func deleteAlarmDraft() {
        cancelDurationEntry()
        if let draft = alarmDraft, !isNewAlarm { model.alarms.remove(id: draft.id) }
        alarmDraft = nil
    }

    func cancelAlarmDraft() {
        cancelDurationEntry()
        alarmDraft = nil
    }

    func stepAlarm(hours: Int = 0, minutes: Int = 0) {
        guard let draft = alarmDraft else { return }
        let total = ((draft.hour * 60 + draft.minute + hours * 60 + minutes) % 1440 + 1440) % 1440
        alarmDraft?.hour = total / 60
        alarmDraft?.minute = total % 60
    }

    /// Applies typed HHMM digits to the draft. In 12-hour regions "730" keeps the draft's AM or PM.
    private func applyTypedAlarmTime(_ entry: DurationDigits) {
        guard !entry.isEmpty, let draft = alarmDraft else { return }
        let digits = String(entry.digits.suffix(4))
        let padded = String(repeating: "0", count: 4 - digits.count) + digits
        var hour = Int(padded.prefix(2))!.clamped(to: 0...23)
        let minute = Int(padded.suffix(2))!.clamped(to: 0...59)
        if Self.uses12HourClock, hour <= 12 {
            hour = hour % 12 + (draft.hour >= 12 ? 12 : 0)
        }
        alarmDraft?.hour = hour
        alarmDraft?.minute = minute
    }

    nonisolated static var uses12HourClock: Bool {
        DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? false
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
        case .pomodoroSetting, .alarmTime: break
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
        case .alarmTime:
            applyTypedAlarmTime(entry)
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
        case .alarmHour:
            stepAlarm(hours: step)
        case .alarmMinute:
            stepAlarm(minutes: step)
        case .snoozeLength:
            model.setSnoozeMinutes(model.settings.snoozeMinutes + step)
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

    // MARK: Keyboard

    /// Keyboard input while the panel has focus. Returns true when the key was used.
    func handleKey(_ event: NSEvent) -> Bool {
        if durationEntry != nil { return handleTypingKey(event) }
        guard isKeyboardSession, presentation == .expanded else { return false }

        let characters = event.charactersIgnoringModifiers ?? ""
        switch event.keyCode {
        case 53: // Escape
            if alarmDraft != nil { cancelAlarmDraft() } else { collapse() }
        case 49: // Space
            toggleCurrentTab()
        case 123: // Left arrow
            moveTab(by: -1)
        case 124: // Right arrow
            moveTab(by: 1)
        case 36, 76: // Return
            if alarmDraft != nil { saveAlarmDraft() } else { toggleCurrentTab() }
        default:
            if event.modifierFlags.contains(.command), let index = Int(characters), (1...ExpandedTab.allCases.count).contains(index) {
                select(ExpandedTab.allCases[index - 1])
            } else if let digit = characters.first, digit.isNumber, let target = typingTarget {
                // Typing a number on Timer or Focus starts a custom duration right away.
                beginDurationEntry(for: target)
                durationEntry?.append(digit)
            } else if tab == .stopwatch, characters == "l" {
                model.stopwatch.lap()
            } else if tab == .stopwatch, characters == "r" {
                model.stopwatch.reset()
            } else {
                return false
            }
        }
        return true
    }

    private var typingTarget: DurationTarget? {
        switch tab {
        case .timer: model.timer.isActive ? nil : .timer
        case .pomodoro: model.pomodoro.isActive ? nil : .pomodoroDial
        case .alarms: alarmDraft == nil ? nil : .alarmTime
        case .stopwatch, .worldClock: nil
        }
    }

    private func toggleCurrentTab() {
        switch tab {
        case .timer: model.timer.toggle()
        case .pomodoro: model.pomodoro.toggle()
        case .stopwatch: model.stopwatch.toggle()
        case .worldClock, .alarms: break
        }
    }

    private func moveTab(by offset: Int) {
        let all = ExpandedTab.allCases
        let index = all.firstIndex(of: tab) ?? 0
        select(all[(index + offset + all.count) % all.count])
    }

    private func handleTypingKey(_ event: NSEvent) -> Bool {
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
            for character in characters {
                if durationTarget == .alarmTime, (durationEntry?.digits.count ?? 0) >= 4 { break }
                durationEntry?.append(character)
            }
        }
        return true
    }
}
