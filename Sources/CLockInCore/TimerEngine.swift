import Foundation
import Observation

public struct TimerSnapshot: Codable, Equatable, Sendable {
    public var selectedDuration: TimeInterval
    public var countdown: Countdown
    public var recentDurations: [TimeInterval]?

    public init(selectedDuration: TimeInterval, countdown: Countdown, recentDurations: [TimeInterval]? = nil) {
        self.selectedDuration = selectedDuration
        self.countdown = countdown
        self.recentDurations = recentDurations
    }
}

/// A single countdown timer with presets.
@MainActor
@Observable
public final class TimerEngine {
    public static let presets: [TimeInterval] = [1, 5, 10, 15, 25, 45].map { $0 * 60 }
    public static let durationRange: ClosedRange<TimeInterval> = 1...(24 * 3600 - 1)
    public static let maxRecents = 3

    /// The duration the user picked; the timer returns to it after finishing or being cancelled.
    public private(set) var selectedDuration: TimeInterval
    public private(set) var countdown: Countdown
    /// Custom (non-preset) durations the user started, newest first.
    public private(set) var recentDurations: [TimeInterval] = []

    @ObservationIgnored public var onFinish: (@MainActor () -> Void)?
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let now: () -> Date

    public init(duration: TimeInterval = 5 * 60, now: @escaping () -> Date = Date.init) {
        let duration = duration.clamped(to: Self.durationRange)
        self.selectedDuration = duration
        self.countdown = Countdown(duration: duration)
        self.now = now
    }

    public var isRunning: Bool { countdown.isRunning }
    public var isPaused: Bool { countdown.isPaused }
    public var isActive: Bool { countdown.isActive }

    public func remaining(at date: Date) -> TimeInterval { countdown.remaining(at: date) }
    public func progress(at date: Date) -> Double { countdown.progress(at: date) }

    public func setDuration(_ duration: TimeInterval) {
        guard !countdown.isActive else { return }
        selectedDuration = duration.clamped(to: Self.durationRange)
        countdown = Countdown(duration: selectedDuration)
        changed()
    }

    public func adjustDuration(by delta: TimeInterval) {
        setDuration(selectedDuration + delta)
    }

    public func start() {
        switch countdown.state {
        case .idle:
            rememberIfCustom(selectedDuration)
            countdown.start(at: now())
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

    public func cancel() {
        countdown = Countdown(duration: selectedDuration)
        changed()
    }

    public func addMinute() {
        countdown.extend(by: 60)
        if !countdown.isActive { selectedDuration = countdown.duration }
        changed()
    }

    /// Checks for completion; call this periodically. Returns true when the timer just finished.
    @discardableResult
    public func tick() -> Bool {
        guard countdown.isFinished(at: now()) else { return false }
        countdown = Countdown(duration: selectedDuration)
        changed()
        onFinish?()
        return true
    }

    public var snapshot: TimerSnapshot {
        TimerSnapshot(selectedDuration: selectedDuration, countdown: countdown, recentDurations: recentDurations)
    }

    /// Restores saved state. A timer that ran out while the app was closed comes back idle.
    public func restore(_ snapshot: TimerSnapshot) {
        selectedDuration = snapshot.selectedDuration.clamped(to: Self.durationRange)
        recentDurations = snapshot.recentDurations ?? []
        countdown = snapshot.countdown.isFinished(at: now())
            ? Countdown(duration: selectedDuration)
            : snapshot.countdown
    }

    public func clearRecents() {
        recentDurations = []
        changed()
    }

    public func removeRecent(_ duration: TimeInterval) {
        recentDurations.removeAll { $0 == duration }
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
