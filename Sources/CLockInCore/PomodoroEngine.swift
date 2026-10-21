import Foundation
import Observation

public enum PomodoroPhase: String, Codable, Sendable, CaseIterable {
    case focus, shortBreak, longBreak

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    public var isBreak: Bool { self != .focus }
}

public struct PomodoroConfig: Codable, Equatable, Sendable {
    public var focus: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    public var roundsBeforeLongBreak: Int
    public var autoAdvance: Bool

    public init(
        focus: TimeInterval = 25 * 60,
        shortBreak: TimeInterval = 5 * 60,
        longBreak: TimeInterval = 15 * 60,
        roundsBeforeLongBreak: Int = 4,
        autoAdvance: Bool = false
    ) {
        self.focus = focus
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.roundsBeforeLongBreak = max(1, roundsBeforeLongBreak)
        self.autoAdvance = autoAdvance
    }

    public func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus: focus
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }
}

public struct PomodoroSnapshot: Codable, Equatable, Sendable {
    public var config: PomodoroConfig
    public var phase: PomodoroPhase
    public var countdown: Countdown
    public var completedFocusRounds: Int
    public var roundsToday: Int
    public var roundsDay: Date
    public var label: String?
}

/// Focus / short break / long break cycle.
@MainActor
@Observable
public final class PomodoroEngine {
    public private(set) var config: PomodoroConfig
    public private(set) var phase: PomodoroPhase = .focus
    public private(set) var countdown: Countdown
    /// Focus rounds finished in the current cycle; resets after a long break.
    public private(set) var completedFocusRounds = 0
    public private(set) var roundsToday = 0
    /// What the current focus rounds are for, e.g. "Thesis". Recorded with each session.
    public private(set) var label: String?
    private var roundsDay: Date

    @ObservationIgnored public var onPhaseFinished: (@MainActor (_ finished: PomodoroPhase, _ next: PomodoroPhase) -> Void)?
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    /// Called whenever a focus round ends, finished or cut short, so it can be added to the history.
    @ObservationIgnored public var onFocusSession: (@MainActor (FocusSession) -> Void)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(config: PomodoroConfig = PomodoroConfig(), now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.config = config
        self.countdown = Countdown(duration: config.focus)
        self.now = now
        self.calendar = calendar
        self.roundsDay = now()
    }

    public var isRunning: Bool { countdown.isRunning }
    public var isPaused: Bool { countdown.isPaused }
    public var isActive: Bool { countdown.isActive }

    public var nextPhase: PomodoroPhase {
        switch phase {
        case .focus: completedFocusRounds + 1 >= config.roundsBeforeLongBreak ? .longBreak : .shortBreak
        case .shortBreak, .longBreak: .focus
        }
    }

    public func remaining(at date: Date) -> TimeInterval { countdown.remaining(at: date) }
    public func progress(at date: Date) -> Double { countdown.progress(at: date) }

    public func updateConfig(_ newConfig: PomodoroConfig) {
        config = newConfig
        if !countdown.isActive {
            countdown = Countdown(duration: config.duration(for: phase))
        }
        changed()
    }

    public func start() {
        switch countdown.state {
        case .idle: countdown.start(at: now())
        case .paused: countdown.resume(at: now())
        case .running: return
        }
        changed()
    }

    public func pause() {
        guard countdown.isRunning else { return }
        countdown.pause(at: now())
        changed()
    }

    public func toggle() {
        countdown.isRunning ? pause() : start()
    }

    /// Moves to the next phase without counting the current one toward today's total.
    public func skip() {
        advance(countTowardToday: false, startNext: false)
    }

    public func setLabel(_ newLabel: String?) {
        label = newLabel
        changed()
    }

    /// Back to the first focus round of a fresh cycle.
    public func reset() {
        if phase == .focus { recordFocus(completed: false, end: now()) }
        phase = .focus
        completedFocusRounds = 0
        countdown = Countdown(duration: config.focus)
        changed()
    }

    /// Checks for completion; call this periodically. Returns true when a phase just finished.
    @discardableResult
    public func tick() -> Bool {
        rollDayIfNeeded()
        guard countdown.isFinished(at: now()) else { return false }
        let finished = phase
        advance(countTowardToday: true, startNext: config.autoAdvance)
        onPhaseFinished?(finished, phase)
        return true
    }

    public var snapshot: PomodoroSnapshot {
        PomodoroSnapshot(
            config: config,
            phase: phase,
            countdown: countdown,
            completedFocusRounds: completedFocusRounds,
            roundsToday: roundsToday,
            roundsDay: roundsDay,
            label: label
        )
    }

    /// Restores saved state. A phase that ran out while the app was closed is completed silently.
    public func restore(_ snapshot: PomodoroSnapshot) {
        config = snapshot.config
        phase = snapshot.phase
        countdown = snapshot.countdown
        completedFocusRounds = snapshot.completedFocusRounds
        roundsToday = snapshot.roundsToday
        roundsDay = snapshot.roundsDay
        label = snapshot.label
        rollDayIfNeeded()
        if countdown.isFinished(at: now()) {
            advance(countTowardToday: true, startNext: false, finishedAt: countdown.endDate)
        }
    }

    private func advance(countTowardToday: Bool, startNext: Bool, finishedAt: Date? = nil) {
        rollDayIfNeeded()
        let next = nextPhase
        switch phase {
        case .focus:
            // Finishing counts the full round; skipping records only the time actually spent.
            recordFocus(completed: countTowardToday, end: finishedAt ?? now())
            completedFocusRounds += 1
            if countTowardToday { roundsToday += 1 }
        case .longBreak:
            completedFocusRounds = 0
        case .shortBreak:
            break
        }
        phase = next
        countdown = Countdown(duration: config.duration(for: next))
        if startNext { countdown.start(at: now()) }
        changed()
    }

    private func recordFocus(completed: Bool, end: Date) {
        let focused = completed ? countdown.duration : countdown.duration - countdown.remaining(at: end)
        guard focused > 0, countdown.isActive || completed else { return }
        onFocusSession?(FocusSession(
            start: end.addingTimeInterval(-focused), end: end, focused: focused,
            planned: countdown.duration, label: label, completed: completed
        ))
    }

    private func rollDayIfNeeded() {
        let date = now()
        guard !calendar.isDate(roundsDay, inSameDayAs: date) else { return }
        roundsDay = date
        roundsToday = 0
    }

    private func changed() {
        onChange?()
    }
}
