import Foundation
import Observation

/// One of the timers that are counting down (or paused).
public struct RunningTimer: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var countdown: Countdown
    /// Shown in lists and alerts, e.g. "10m".
    public var label: String

    public init(id: UUID = UUID(), countdown: Countdown, label: String) {
        self.id = id
        self.countdown = countdown
        self.label = label
    }
}

public struct TimerSnapshot: Codable, Equatable, Sendable {
    public var selectedDuration: TimeInterval
    /// Only in snapshots from versions with a single timer; restored into `timers`.
    public var countdown: Countdown?
    public var recentDurations: [TimeInterval]?
    public var timers: [RunningTimer]?

    public init(
        selectedDuration: TimeInterval,
        countdown: Countdown? = nil,
        recentDurations: [TimeInterval]? = nil,
        timers: [RunningTimer]? = nil
    ) {
        self.selectedDuration = selectedDuration
        self.countdown = countdown
        self.recentDurations = recentDurations
        self.timers = timers
    }
}

/// Several countdowns at once, plus the duration picker that new ones start from.
@MainActor
@Observable
public final class TimerEngine {
    public static let presets: [TimeInterval] = [1, 5, 10, 15, 25, 45].map { $0 * 60 }
    public static let durationRange: ClosedRange<TimeInterval> = 1...(24 * 3600 - 1)
    public static let maxRecents = 3
    public static let maxTimers = 5

    /// The duration the next timer will start with.
    public private(set) var selectedDuration: TimeInterval
    /// Active timers, oldest first.
    public private(set) var timers: [RunningTimer] = []
    /// Custom (non-preset) durations the user started, newest first.
    public private(set) var recentDurations: [TimeInterval] = []

    @ObservationIgnored public var onFinish: (@MainActor (RunningTimer) -> Void)?
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let now: () -> Date

    public init(duration: TimeInterval = 5 * 60, now: @escaping () -> Date = Date.init) {
        self.selectedDuration = duration.clamped(to: Self.durationRange)
        self.now = now
    }

    // MARK: State

    public var isActive: Bool { !timers.isEmpty }
    public var isRunning: Bool { timers.contains { $0.countdown.isRunning } }
    public var canStartAnother: Bool { timers.count < Self.maxTimers }

    /// The timer that matters most right now: the running one ending soonest, else the first paused one.
    public var primary: RunningTimer? {
        let date = now()
        return timers.filter(\.countdown.isRunning).min { $0.countdown.remaining(at: date) < $1.countdown.remaining(at: date) }
            ?? timers.first
    }

    public func timer(id: UUID) -> RunningTimer? {
        timers.first { $0.id == id }
    }

    /// Timers ordered for display: running ones by time left, then paused ones.
    public func sorted(at date: Date) -> [RunningTimer] {
        timers.sorted { lhs, rhs in
            if lhs.countdown.isRunning != rhs.countdown.isRunning { return lhs.countdown.isRunning }
            return lhs.countdown.remaining(at: date) < rhs.countdown.remaining(at: date)
        }
    }

    // MARK: Picking a duration

    public func setDuration(_ duration: TimeInterval) {
        selectedDuration = duration.clamped(to: Self.durationRange)
        changed()
    }

    public func adjustDuration(by delta: TimeInterval) {
        setDuration(selectedDuration + delta)
    }

    // MARK: Controlling timers

    /// Starts a new timer with the selected duration. Returns nil when the maximum is already running.
    @discardableResult
    public func start() -> UUID? {
        guard canStartAnother else { return nil }
        rememberIfCustom(selectedDuration)
        var countdown = Countdown(duration: selectedDuration)
        countdown.start(at: now())
        let timer = RunningTimer(countdown: countdown, label: TimeFormat.short(selectedDuration))
        timers.append(timer)
        changed()
        return timer.id
    }

    public func pause(id: UUID) {
        update(id) { $0.countdown.pause(at: now()) }
    }

    public func resume(id: UUID) {
        update(id) { $0.countdown.resume(at: now()) }
    }

    public func toggle(id: UUID) {
        guard let timer = timer(id: id) else { return }
        timer.countdown.isRunning ? pause(id: id) : resume(id: id)
    }

    public func addMinute(id: UUID) {
        update(id) { $0.countdown.extend(by: 60) }
    }

    public func cancel(id: UUID) {
        timers.removeAll { $0.id == id }
        changed()
    }

    public func cancelAll() {
        timers = []
        changed()
    }

    /// Pause or resume the most relevant timer; with none active, start one.
    public func togglePrimary() {
        if let primary { toggle(id: primary.id) } else { start() }
    }

    /// Checks for completion; call this periodically. Returns the timers that just finished.
    @discardableResult
    public func tick() -> [RunningTimer] {
        let date = now()
        let finished = timers.filter { $0.countdown.isFinished(at: date) }
        guard !finished.isEmpty else { return [] }
        timers.removeAll { timer in finished.contains { $0.id == timer.id } }
        changed()
        for timer in finished { onFinish?(timer) }
        return finished
    }

    // MARK: Persistence

    public var snapshot: TimerSnapshot {
        TimerSnapshot(selectedDuration: selectedDuration, recentDurations: recentDurations, timers: timers)
    }

    /// Restores saved state. Timers that ran out while the app was closed are dropped.
    public func restore(_ snapshot: TimerSnapshot) {
        selectedDuration = snapshot.selectedDuration.clamped(to: Self.durationRange)
        recentDurations = snapshot.recentDurations ?? []
        var saved = snapshot.timers ?? []
        if let legacy = snapshot.countdown, legacy.isActive {
            saved.append(RunningTimer(countdown: legacy, label: TimeFormat.short(legacy.duration)))
        }
        let date = now()
        timers = Array(saved.filter { !$0.countdown.isFinished(at: date) }.prefix(Self.maxTimers))
    }

    public func clearRecents() {
        recentDurations = []
        changed()
    }

    public func removeRecent(_ duration: TimeInterval) {
        recentDurations.removeAll { $0 == duration }
        changed()
    }

    private func update(_ id: UUID, _ change: (inout RunningTimer) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        change(&timers[index])
        changed()
    }

    private func rememberIfCustom(_ duration: TimeInterval) {
        guard !Self.presets.contains(duration) else { return }
        recentDurations.removeAll { $0 == duration }
        recentDurations.insert(duration, at: 0)
        recentDurations = Array(recentDurations.prefix(Self.maxRecents))
    }

    private func changed() {
        onChange?()
    }
}
