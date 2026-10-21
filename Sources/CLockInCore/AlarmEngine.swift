import Foundation
import Observation

public struct Alarm: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var hour: Int
    public var minute: Int
    public var label: String
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty means "once".
    public var repeatDays: Set<Int>
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        label: String = "Alarm",
        repeatDays: Set<Int> = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.hour = hour.clamped(to: 0...23)
        self.minute = minute.clamped(to: 0...59)
        self.label = label
        self.repeatDays = repeatDays.filter { (1...7).contains($0) }
        self.isEnabled = isEnabled
    }

    public var repeats: Bool { !repeatDays.isEmpty }

    /// The first time this alarm rings strictly after `date`, ignoring whether it's enabled.
    public func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        if repeatDays.isEmpty {
            let components = DateComponents(hour: hour, minute: minute, second: 0)
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
        return repeatDays
            .compactMap { weekday in
                let components = DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday)
                return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
            }
            .min()
    }

    /// "Every day", "Weekdays", "Weekends", "Once" or "Mon, Wed, Fri".
    public func repeatSummary(calendar: Calendar = .current) -> String {
        switch repeatDays {
        case []: return "Once"
        case Set(1...7): return "Every day"
        case [2, 3, 4, 5, 6]: return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            // Order the days the way this calendar starts its week.
            let ordered = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }.filter(repeatDays.contains)
            return ordered.map { calendar.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        }
    }
}

public struct AlarmSnapshot: Codable, Equatable, Sendable {
    public var alarms: [Alarm]
    public var snoozedUntil: [UUID: Date]
    public var lastCheck: Date
}

/// Alarms that ring while the Mac is awake. Something has to call `tick()` regularly (once a second is plenty).
@MainActor
@Observable
public final class AlarmEngine {
    public static let defaultSnoozeDuration: TimeInterval = 9 * 60
    public static let snoozeRange: ClosedRange<TimeInterval> = 60...(60 * 60)
    /// If the Mac was asleep when an alarm was due, it still rings on wake if it's at most this late.
    public static let missedTolerance: TimeInterval = 5 * 60

    public private(set) var alarms: [Alarm] = []
    public private(set) var snoozedUntil: [UUID: Date] = [:]
    /// How long Snooze waits before ringing again.
    public private(set) var snoozeDuration: TimeInterval = AlarmEngine.defaultSnoozeDuration
    @ObservationIgnored private var lastCheck: Date

    @ObservationIgnored public var onFire: (@MainActor (Alarm) -> Void)?
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    public init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        self.lastCheck = now()
    }

    /// True while any alarm could still ring, so the app knows whether to keep checking.
    public var needsChecking: Bool {
        alarms.contains(where: \.isEnabled) || !snoozedUntil.isEmpty
    }

    public func nextFireDate(for alarm: Alarm) -> Date? {
        let scheduled = alarm.isEnabled ? alarm.nextFire(after: now(), calendar: calendar) : nil
        return [scheduled, snoozedUntil[alarm.id]].compactMap { $0 }.min()
    }

    /// The soonest alarm to ring, and when.
    public var nextAlarm: (alarm: Alarm, date: Date)? {
        alarms
            .compactMap { alarm in nextFireDate(for: alarm).map { (alarm, $0) } }
            .min { $0.1 < $1.1 }
    }

    public func add(_ alarm: Alarm) {
        alarms.append(alarm)
        sortAlarms()
        changed()
    }

    public func update(_ alarm: Alarm) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[index] = alarm
        if !alarm.isEnabled { snoozedUntil[alarm.id] = nil }
        sortAlarms()
        changed()
    }

    public func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard var alarm = alarms.first(where: { $0.id == id }) else { return }
        alarm.isEnabled = isEnabled
        update(alarm)
    }

    public func remove(id: UUID) {
        alarms.removeAll { $0.id == id }
        snoozedUntil[id] = nil
        changed()
    }

    public func setSnoozeDuration(_ duration: TimeInterval) {
        snoozeDuration = duration.clamped(to: Self.snoozeRange)
    }

    public func snooze(id: UUID) {
        guard alarms.contains(where: { $0.id == id }) else { return }
        snoozedUntil[id] = now().addingTimeInterval(snoozeDuration)
        changed()
    }

    /// Rings any alarm that came due since the last check. Returns the alarms that rang.
    @discardableResult
    public func tick() -> [Alarm] {
        let date = now()
        let since = lastCheck
        lastCheck = date
        guard date > since else { return [] }

        var rang: [Alarm] = []
        var didChange = false
        for alarm in alarms {
            let scheduled = alarm.isEnabled ? alarm.nextFire(after: since, calendar: calendar) : nil
            let snoozed = snoozedUntil[alarm.id].flatMap { $0 > since ? $0 : nil }
            guard let due = [scheduled, snoozed].compactMap({ $0 }).min(), due <= date else { continue }

            snoozedUntil[alarm.id] = nil
            if !alarm.repeats, scheduled == due, let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[index].isEnabled = false
            }
            didChange = true
            if date.timeIntervalSince(due) <= Self.missedTolerance {
                rang.append(alarm)
            }
        }
        if didChange { changed() }
        for alarm in rang { onFire?(alarm) }
        return rang
    }

    public var snapshot: AlarmSnapshot {
        AlarmSnapshot(alarms: alarms, snoozedUntil: snoozedUntil, lastCheck: lastCheck)
    }

    /// Restores saved alarms. Anything that came due while the app wasn't running is caught by the next tick.
    public func restore(_ snapshot: AlarmSnapshot) {
        alarms = snapshot.alarms
        snoozedUntil = snapshot.snoozedUntil
        lastCheck = min(snapshot.lastCheck, now())
        sortAlarms()
    }

    private func sortAlarms() {
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    private func changed() {
        onChange?()
    }
}
