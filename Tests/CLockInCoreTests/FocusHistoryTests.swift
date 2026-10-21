import XCTest
@testable import CLockInCore

@MainActor
final class FocusHistoryTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "GMT")!
        return calendar
    }()

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func session(day: Int, hour: Int, minutes: Double, label: String? = nil, completed: Bool = true) -> FocusSession {
        let end = date(day: day, hour: hour)
        return FocusSession(
            start: end.addingTimeInterval(-minutes * 60), end: end, focused: minutes * 60,
            planned: 25 * 60, label: label, completed: completed
        )
    }

    func testDailyTotalsAndLabels() {
        let history = FocusHistory(calendar: calendar)
        history.record(session(day: 9, hour: 10, minutes: 25, label: "Code"))
        history.record(session(day: 9, hour: 11, minutes: 25, label: "Thesis"))
        history.record(session(day: 10, hour: 9, minutes: 10, label: "Code", completed: false))
        let days = history.days(3, endingAt: date(day: 10, hour: 20))
        XCTAssertEqual(days.map { $0.focused / 60 }, [0, 50, 10])
        XCTAssertEqual(days[1].completedRounds, 2)
        XCTAssertEqual(days[1].byLabel["Thesis"], 25 * 60)
        XCTAssertEqual(history.labels, ["Code", "Thesis"])

        let week = DateInterval(start: date(day: 4, hour: 0), end: date(day: 11, hour: 0))
        XCTAssertEqual(history.totalsByLabel(in: week).first?.label, "Code")
        XCTAssertEqual(history.totalFocused(in: week), 60 * 60)
    }

    func testShortPartialRoundsAreNotRecorded() {
        let history = FocusHistory(calendar: calendar)
        history.record(session(day: 9, hour: 10, minutes: 0.5, completed: false))
        XCTAssertTrue(history.sessions.isEmpty)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        let history = FocusHistory(calendar: calendar)
        for day in [6, 7, 8] { history.record(session(day: day, hour: 10, minutes: 25)) }
        history.record(session(day: 9, hour: 10, minutes: 12, completed: false))
        // Nothing finished on the 9th yet, so the streak runs through yesterday.
        XCTAssertEqual(history.streak(at: date(day: 9, hour: 18)), 3)
        XCTAssertEqual(history.streak(at: date(day: 11, hour: 18)), 0)
    }

    func testRenamingALabelUpdatesPastSessions() {
        let history = FocusHistory(calendar: calendar)
        history.record(session(day: 9, hour: 10, minutes: 25, label: "Thsis"))
        history.renameLabel("Thsis", to: "Thesis")
        XCTAssertEqual(history.sessions[0].label, "Thesis")
        XCTAssertEqual(history.labels, ["Thesis"])
    }

    func testCSVExport() {
        let history = FocusHistory(calendar: calendar)
        history.record(session(day: 9, hour: 10, minutes: 25, label: "Say \"hi\""))
        let lines = history.csv(timeZone: TimeZone(identifier: "GMT")!).split(separator: "\n")
        XCTAssertEqual(lines[0], "start,end,focused_minutes,planned_minutes,label,completed")
        XCTAssertEqual(lines[1], #"2026-03-09T09:35:00Z,2026-03-09T10:00:00Z,25.0,25.0,"Say ""hi""",yes"#)
    }

    func testPomodoroRecordsFinishedAndCutShortRounds() {
        let clock = TestClock()
        let engine = PomodoroEngine(config: PomodoroConfig(focus: 600, shortBreak: 60), now: { clock.now })
        var recorded: [FocusSession] = []
        engine.onFocusSession = { recorded.append($0) }
        engine.setLabel("Code")
        engine.start()
        clock.advance(600)
        engine.tick()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].focused, 600)
        XCTAssertTrue(recorded[0].completed)
        XCTAssertEqual(recorded[0].label, "Code")

        engine.skip() // the break, which isn't recorded
        engine.start()
        clock.advance(240)
        engine.reset()
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded[1].focused, 240, accuracy: 0.001)
        XCTAssertFalse(recorded[1].completed)

        engine.skip() // a focus round that never started records nothing
        XCTAssertEqual(recorded.count, 2)
    }
}
