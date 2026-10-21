import Foundation
import Observation

public struct StopwatchSnapshot: Codable, Equatable, Sendable {
    public var accumulated: TimeInterval
    public var startedAt: Date?
    public var laps: [TimeInterval]
}

/// A stopwatch with laps. Like the countdowns, it stores dates rather than ticking.
@MainActor
@Observable
public final class StopwatchEngine {
    /// Time banked from earlier runs; the current run adds `now - startedAt` on top.
    public private(set) var accumulated: TimeInterval = 0
    public private(set) var startedAt: Date?
    /// Total elapsed time at each lap press, oldest first.
    public private(set) var laps: [TimeInterval] = []

    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let now: () -> Date

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    public var isRunning: Bool { startedAt != nil }
    public var isActive: Bool { isRunning || accumulated > 0 }

    public func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// Time since the last lap press (or the start).
    public func currentLap(at date: Date) -> TimeInterval {
        elapsed(at: date) - (laps.last ?? 0)
    }

    /// Each lap's own duration, oldest first.
    public var lapDurations: [TimeInterval] {
        zip(laps, [0] + laps).map { $0 - $1 }
    }

    /// Indices into `lapDurations` of the fastest and slowest laps, once there are at least two.
    public var lapExtremes: (fastest: Int, slowest: Int)? {
        let durations = lapDurations
        guard durations.count >= 2,
              let fastest = durations.indices.min(by: { durations[$0] < durations[$1] }),
              let slowest = durations.indices.max(by: { durations[$0] < durations[$1] }),
              durations[fastest] < durations[slowest] else { return nil }
        return (fastest, slowest)
    }

    public func start() {
        guard startedAt == nil else { return }
        startedAt = now()
        changed()
    }

    public func pause() {
        guard let startedAt else { return }
        accumulated += max(0, now().timeIntervalSince(startedAt))
        self.startedAt = nil
        changed()
    }

    public func toggle() {
        isRunning ? pause() : start()
    }

    public func lap() {
        guard isRunning else { return }
        laps.append(elapsed(at: now()))
        changed()
    }

    public func reset() {
        accumulated = 0
        startedAt = nil
        laps = []
        changed()
    }

    public var snapshot: StopwatchSnapshot {
        StopwatchSnapshot(accumulated: accumulated, startedAt: startedAt, laps: laps)
    }

    public func restore(_ snapshot: StopwatchSnapshot) {
        accumulated = snapshot.accumulated
        startedAt = snapshot.startedAt
        laps = snapshot.laps
    }

    private func changed() {
        onChange?()
    }
}
