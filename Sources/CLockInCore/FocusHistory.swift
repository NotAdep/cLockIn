import Foundation
import Observation

/// One focus round, finished or cut short.
public struct FocusSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    /// Time actually spent focusing.
    public var focused: TimeInterval
    /// The length the round was set to.
    public var planned: TimeInterval
    public var label: String?
    /// False when the round was skipped or reset before it ended.
    public var completed: Bool

    public init(
        id: UUID = UUID(), start: Date, end: Date, focused: TimeInterval,
        planned: TimeInterval, label: String?, completed: Bool
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.focused = focused
        self.planned = planned
        self.label = label
        self.completed = completed
    }
}

public struct FocusHistorySnapshot: Codable, Equatable, Sendable {
    public var sessions: [FocusSession]
    public var labels: [String]

    public init(sessions: [FocusSession], labels: [String]) {
        self.sessions = sessions
        self.labels = labels
    }
}

/// Totals for one calendar day.
public struct FocusDay: Equatable, Sendable {
    public var day: Date
    public var focused: TimeInterval
    public var byLabel: [String: TimeInterval]
    public var completedRounds: Int
}

/// Every focus session, plus the labels you can tag them with.
@MainActor
@Observable
public final class FocusHistory {
    /// Rounds cut short before this much focus aren't worth recording.
    public nonisolated static let minimumPartial: TimeInterval = 60
    public nonisolated static let unlabeled = "No label"

    public private(set) var sessions: [FocusSession] = []
    public private(set) var labels: [String] = []

    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: Recording

    public func record(_ session: FocusSession) {
        guard session.completed || session.focused >= Self.minimumPartial else { return }
        sessions.append(session)
        if let label = session.label, !labels.contains(label) { labels.append(label) }
        changed()
    }

    public func clear() {
        sessions = []
        changed()
    }

    // MARK: Labels

    public func addLabel(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !labels.contains(trimmed) else { return }
        labels.append(trimmed)
        changed()
    }

    /// Renames a label everywhere, including past sessions.
    public func renameLabel(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let index = labels.firstIndex(of: old) else { return }
        if labels.contains(trimmed) {
            labels.remove(at: index)
        } else {
            labels[index] = trimmed
        }
        for i in sessions.indices where sessions[i].label == old { sessions[i].label = trimmed }
        changed()
    }

    /// Removes a label from the list. Past sessions keep it, so totals don't change.
    public func removeLabel(_ name: String) {
        labels.removeAll { $0 == name }
        changed()
    }

    // MARK: Statistics

    public func sessions(in interval: DateInterval) -> [FocusSession] {
        sessions.filter { interval.contains($0.end) }
    }

    public func totalFocused(in interval: DateInterval) -> TimeInterval {
        sessions(in: interval).reduce(0) { $0 + $1.focused }
    }

    /// One entry per day for the `count` days ending with the day containing `date`, oldest first.
    public func days(_ count: Int, endingAt date: Date) -> [FocusDay] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let daySessions = sessions(in: DateInterval(start: day, end: next.addingTimeInterval(-0.001)))
            var byLabel: [String: TimeInterval] = [:]
            for session in daySessions { byLabel[session.label ?? Self.unlabeled, default: 0] += session.focused }
            return FocusDay(
                day: day,
                focused: daySessions.reduce(0) { $0 + $1.focused },
                byLabel: byLabel,
                completedRounds: daySessions.filter(\.completed).count
            )
        }
    }

    /// Focus time per label within an interval, largest first.
    public func totalsByLabel(in interval: DateInterval) -> [(label: String, focused: TimeInterval)] {
        var totals: [String: TimeInterval] = [:]
        for session in sessions(in: interval) { totals[session.label ?? Self.unlabeled, default: 0] += session.focused }
        return totals.map { ($0.key, $0.value) }.sorted { $0.focused > $1.focused }
    }

    /// Consecutive days with at least one completed round, counting back from today
    /// (or from yesterday, if nothing is finished yet today).
    public func streak(at date: Date) -> Int {
        let completedDays = Set(sessions.filter(\.completed).map { calendar.startOfDay(for: $0.end) })
        var day = calendar.startOfDay(for: date)
        if !completedDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while completedDays.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: Export

    /// One row per session, oldest first, for Numbers or Excel.
    public func csv(timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        var lines = ["start,end,focused_minutes,planned_minutes,label,completed"]
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let label = (session.label ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            lines.append([
                formatter.string(from: session.start),
                formatter.string(from: session.end),
                String(format: "%.1f", session.focused / 60),
                String(format: "%.1f", session.planned / 60),
                "\"\(label)\"",
                session.completed ? "yes" : "no",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Persistence

    public var snapshot: FocusHistorySnapshot {
        FocusHistorySnapshot(sessions: sessions, labels: labels)
    }

    public func restore(_ snapshot: FocusHistorySnapshot) {
        sessions = snapshot.sessions
        labels = snapshot.labels
    }

    private func changed() {
        onChange?()
    }
}
