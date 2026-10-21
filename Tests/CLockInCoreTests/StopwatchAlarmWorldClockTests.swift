import XCTest
@testable import CLockInCore

private var gmtCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "GMT")!
    return calendar
}()

/// Monday 5 January 2026 at the given time, GMT.
private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
    gmtCalendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: hour, minute: minute))!
}

@MainActor
final class StopwatchEngineTests: XCTestCase {
    func testElapsedAcrossPauses() {
        let clock = TestClock()
        let stopwatch = StopwatchEngine(now: { clock.now })
        stopwatch.start()
        clock.advance(10)
        stopwatch.pause()
        clock.advance(100)
        stopwatch.start()
        clock.advance(5)
        XCTAssertEqual(stopwatch.elapsed(at: clock.now), 15, accuracy: 0.001)
    }

    func testLapsAndExtremes() {
        let clock = TestClock()
        let stopwatch = StopwatchEngine(now: { clock.now })
        stopwatch.start()
        for split: TimeInterval in [10, 7, 12] {
            clock.advance(split)
            stopwatch.lap()
        }
        clock.advance(3)
        XCTAssertEqual(stopwatch.lapDurations, [10, 7, 12])
        XCTAssertEqual(stopwatch.currentLap(at: clock.now), 3, accuracy: 0.001)
        XCTAssertEqual(stopwatch.lapExtremes?.fastest, 1)
        XCTAssertEqual(stopwatch.lapExtremes?.slowest, 2)
        stopwatch.reset()
        XCTAssertFalse(stopwatch.isActive)
        XCTAssertTrue(stopwatch.laps.isEmpty)
    }

    func testRestoreKeepsRunning() {
        let clock = TestClock()
        let original = StopwatchEngine(now: { clock.now })
        original.start()
        clock.advance(20)
        let restored = StopwatchEngine(now: { clock.now })
        restored.restore(original.snapshot)
        clock.advance(10)
        XCTAssertEqual(restored.elapsed(at: clock.now), 30, accuracy: 0.001)
    }
}

@MainActor
final class AlarmEngineTests: XCTestCase {
    func testOneShotNextFireIsTodayOrTomorrow() {
        let alarm = Alarm(hour: 9, minute: 30)
        XCTAssertEqual(alarm.nextFire(after: monday(8), calendar: gmtCalendar), monday(9, 30))
        XCTAssertEqual(alarm.nextFire(after: monday(10), calendar: gmtCalendar), monday(9, 30).addingTimeInterval(86_400))
    }

    func testRepeatingAlarmSkipsToNextChosenDay() {
        // Wednesday (4) and Friday (6), asked on Monday after 7:00.
        let alarm = Alarm(hour: 7, minute: 0, repeatDays: [4, 6])
        XCTAssertEqual(alarm.nextFire(after: monday(8), calendar: gmtCalendar), monday(7).addingTimeInterval(2 * 86_400))
        XCTAssertEqual(alarm.repeatSummary(calendar: gmtCalendar), "Wed, Fri")
        XCTAssertEqual(Alarm(hour: 7, minute: 0, repeatDays: [2, 3, 4, 5, 6]).repeatSummary(), "Weekdays")
    }

    func testRingsOnceAndDisablesOneShot() {
        var date = monday(9, 29)
        let engine = AlarmEngine(now: { date }, calendar: gmtCalendar)
        var rang: [String] = []
        engine.onFire = { rang.append($0.label) }
        engine.add(Alarm(hour: 9, minute: 30, label: "Standup"))
        engine.tick()
        date = monday(9, 30).addingTimeInterval(0.5)
        engine.tick()
        date = monday(9, 31)
        engine.tick()
        XCTAssertEqual(rang, ["Standup"])
        XCTAssertFalse(engine.alarms[0].isEnabled)
        XCTAssertFalse(engine.needsChecking)
    }

    func testRepeatingAlarmStaysEnabledAndRingsNextDay() {
        var date = monday(6, 59)
        let engine = AlarmEngine(now: { date }, calendar: gmtCalendar)
        var count = 0
        engine.onFire = { _ in count += 1 }
        engine.add(Alarm(hour: 7, minute: 0, repeatDays: Set(1...7)))
        date = monday(7, 0).addingTimeInterval(1)
        engine.tick()
        date = monday(7, 0).addingTimeInterval(86_400 + 1)
        engine.tick()
        XCTAssertEqual(count, 2)
        XCTAssertTrue(engine.alarms[0].isEnabled)
    }

    func testSnoozeRingsAgainAfterNineMinutes() {
        var date = monday(7)
        let engine = AlarmEngine(now: { date }, calendar: gmtCalendar)
        var count = 0
        engine.onFire = { _ in count += 1 }
        let alarm = Alarm(hour: 7, minute: 0, isEnabled: false)
        engine.add(alarm)
        engine.snooze(id: alarm.id)
        XCTAssertTrue(engine.needsChecking)
        date = monday(7, 8)
        engine.tick()
        XCTAssertEqual(count, 0)
        date = monday(7, 9).addingTimeInterval(1)
        engine.tick()
        XCTAssertEqual(count, 1)
        XCTAssertTrue(engine.snoozedUntil.isEmpty)
    }

    func testSnoozeLengthIsConfigurable() {
        var date = monday(7)
        let engine = AlarmEngine(now: { date }, calendar: gmtCalendar)
        var count = 0
        engine.onFire = { _ in count += 1 }
        engine.setSnoozeDuration(5 * 60)
        let alarm = Alarm(hour: 7, minute: 0, isEnabled: false)
        engine.add(alarm)
        engine.snooze(id: alarm.id)
        date = monday(7, 5).addingTimeInterval(1)
        engine.tick()
        XCTAssertEqual(count, 1)
        engine.setSnoozeDuration(0)
        XCTAssertEqual(engine.snoozeDuration, 60, "clamped to at least a minute")
    }

    func testAlarmMissedDuringLongSleepDoesNotRingLate() {
        var date = monday(6)
        let engine = AlarmEngine(now: { date }, calendar: gmtCalendar)
        var count = 0
        engine.onFire = { _ in count += 1 }
        engine.add(Alarm(hour: 7, minute: 0))
        date = monday(7, 4)
        engine.tick()
        XCTAssertEqual(count, 1, "4 minutes late is within tolerance")

        engine.add(Alarm(hour: 8, minute: 0))
        date = monday(9)
        engine.tick()
        XCTAssertEqual(count, 1, "an hour late is skipped")
        XCTAssertFalse(engine.alarms.contains(where: \.isEnabled))
    }

    func testNextAlarmPicksSoonest() {
        let date = monday(12)
        let engine = AlarmEngine(now: { date }, calendar: gmtCalendar)
        engine.add(Alarm(hour: 7, minute: 0))
        engine.add(Alarm(hour: 18, minute: 0))
        engine.add(Alarm(hour: 20, minute: 0, isEnabled: false))
        XCTAssertEqual(engine.nextAlarm?.alarm.hour, 18)
    }
}

final class WorldClockTests: XCTestCase {
    func testCityNames() {
        XCTAssertEqual(WorldClock.cityName(for: "Asia/Kolkata"), "Kolkata")
        XCTAssertEqual(WorldClock.cityName(for: "America/Port_of_Spain"), "Port of Spain")
        XCTAssertEqual(WorldClock.cityName(for: "Asia/Calcutta"), "Kolkata")
        XCTAssertFalse(WorldClock.search("kolk").isEmpty)
    }

    func testRelationDescribesDayAndOffset() {
        let london = TimeZone(identifier: "Europe/London")!
        let date = monday(20) // 8 PM in London in winter
        XCTAssertEqual(
            WorldClock.relation(of: TimeZone(identifier: "Asia/Kolkata")!, to: london, at: date, calendar: gmtCalendar),
            "Tomorrow, +5:30"
        )
        XCTAssertEqual(
            WorldClock.relation(of: TimeZone(identifier: "America/New_York")!, to: london, at: date, calendar: gmtCalendar),
            "Today, −5h"
        )
        XCTAssertEqual(WorldClock.relation(of: london, to: london, at: date, calendar: gmtCalendar), "Today, same time")
    }
}
