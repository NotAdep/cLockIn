import Foundation

/// A countdown that stores its end date instead of ticking, so it stays accurate across sleep and never drifts.
public struct Countdown: Codable, Equatable, Sendable {
    public enum State: Codable, Equatable, Sendable {
        case idle
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    public var duration: TimeInterval
    public private(set) var state: State = .idle

    public init(duration: TimeInterval) {
        self.duration = max(1, duration)
    }

    public var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    public var isPaused: Bool {
        if case .paused = state { true } else { false }
    }

    public var isActive: Bool { state != .idle }

    public var endDate: Date? {
        if case .running(let endDate) = state { endDate } else { nil }
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle: duration
        case .running(let endDate): max(0, endDate.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    /// Elapsed fraction from 0 (just started) to 1 (done).
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    public func isFinished(at now: Date) -> Bool {
        isRunning && remaining(at: now) <= 0
    }

    public mutating func start(at now: Date) {
        state = .running(endDate: now.addingTimeInterval(duration))
    }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        state = .paused(remaining: remaining(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let remaining) = state else { return }
        state = .running(endDate: now.addingTimeInterval(remaining))
    }

    public mutating func reset() {
        state = .idle
    }

    /// Adds time to an active countdown, growing `duration` too so progress stays meaningful.
    public mutating func extend(by seconds: TimeInterval) {
        switch state {
        case .idle:
            duration = max(1, duration + seconds)
        case .running(let endDate):
            state = .running(endDate: endDate.addingTimeInterval(seconds))
            duration += seconds
        case .paused(let remaining):
            state = .paused(remaining: remaining + seconds)
            duration += seconds
        }
    }
}
