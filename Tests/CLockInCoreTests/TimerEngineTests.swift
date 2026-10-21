import XCTest
@testable import CLockInCore

final class TestClock {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}

@MainActor
final class TimerEngineTests: XCTestCase {
    func testRemainingCountsDownFromEndDate() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 300, now: { clock.now })
        let id = timer.start()!
        clock.advance(30)
        let running = timer.timer(id: id)!.countdown
        XCTAssertEqual(running.remaining(at: clock.now), 270, accuracy: 0.001)
        XCTAssertEqual(running.progress(at: clock.now), 0.1, accuracy: 0.001)
    }

    func testPauseAndResumeKeepsRemainingTime() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 300, now: { clock.now })
        let id = timer.start()!
        clock.advance(60)
        timer.pause(id: id)
        clock.advance(500)
        XCTAssertEqual(timer.timer(id: id)!.countdown.remaining(at: clock.now), 240, accuracy: 0.001)
        timer.resume(id: id)
        clock.advance(40)
        XCTAssertEqual(timer.timer(id: id)!.countdown.remaining(at: clock.now), 200, accuracy: 0.001)
    }

    func testAddMinuteExtendsRunningTimer() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 60, now: { clock.now })
        let id = timer.start()!
        clock.advance(50)
        timer.addMinute(id: id)
        XCTAssertEqual(timer.timer(id: id)!.countdown.remaining(at: clock.now), 70, accuracy: 0.001)
    }

    func testTickFinishesOnceAndRemovesTheTimer() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 60, now: { clock.now })
        var finished: [String] = []
        timer.onFinish = { finished.append($0.label) }
        let id = timer.start()!
        timer.addMinute(id: id)
        clock.advance(119)
        XCTAssertTrue(timer.tick().isEmpty)
        clock.advance(1)
        XCTAssertEqual(timer.tick().count, 1)
        XCTAssertTrue(timer.tick().isEmpty)
        XCTAssertEqual(finished, ["1m"])
        XCTAssertFalse(timer.isActive)
        XCTAssertEqual(timer.selectedDuration, 60)
    }

    func testSeveralTimersRunIndependently() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 600, now: { clock.now })
        let long = timer.start()!
        timer.setDuration(120)
        let short = timer.start()!
        XCTAssertEqual(timer.timers.count, 2)
        XCTAssertEqual(timer.primary?.id, short, "the one ending soonest comes first")

        timer.pause(id: short)
        XCTAssertEqual(timer.primary?.id, long, "running beats paused")

        timer.resume(id: short)
        clock.advance(121)
        XCTAssertEqual(timer.tick().map(\.id), [short])
        XCTAssertEqual(timer.timers.map(\.id), [long])
    }

    func testTimerCountIsCapped() {
        let timer = TimerEngine(duration: 60)
        for _ in 0..<TimerEngine.maxTimers { XCTAssertNotNil(timer.start()) }
        XCTAssertNil(timer.start())
        XCTAssertFalse(timer.canStartAnother)
    }

    func testDurationIsClamped() {
        let timer = TimerEngine(duration: 0)
        XCTAssertEqual(timer.selectedDuration, 1)
        timer.setDuration(30 * 3600)
        XCTAssertEqual(timer.selectedDuration, 24 * 3600 - 1)
    }

    func testCustomDurationsAreRememberedNewestFirst() {
        let timer = TimerEngine()
        let durations: [TimeInterval] = [90, 300, 420, 90, 1200, 180]
        for duration in durations {
            timer.setDuration(duration)
            timer.start()
            timer.cancelAll()
        }
        // 5m is a preset, so it isn't kept. Reusing 90s moved it up, so 7m is the one that fell off.
        let expected: [TimeInterval] = [180, 1200, 90]
        XCTAssertEqual(timer.recentDurations, expected)
    }

    func testDurationDigitsShiftInFromTheRight() {
        var entry = DurationDigits()
        for digit in "0130" { entry.append(digit) }
        XCTAssertEqual(entry.padded, "000130")
        XCTAssertEqual(entry.duration, 90)
        entry.append("0")
        XCTAssertEqual(entry.duration, 13 * 60)
        entry.deleteLast()
        entry.deleteLast()
        XCTAssertEqual(entry.duration, 13)
        var overflow = DurationDigits(digits: "90")
        XCTAssertEqual(overflow.duration, 90)
        for digit in "12345678" { overflow.append(digit) }
        XCTAssertEqual(overflow.padded, "901234")
    }

    func testRestoreKeepsRunningTimersAndDropsExpiredOnes() {
        let clock = TestClock()
        let original = TimerEngine(duration: 600, now: { clock.now })
        original.start()
        original.setDuration(60)
        original.start()
        let saved = original.snapshot
        clock.advance(100)
        let restored = TimerEngine(now: { clock.now })
        restored.restore(saved)
        XCTAssertEqual(restored.timers.count, 1)
        XCTAssertEqual(restored.timers[0].countdown.remaining(at: clock.now), 500, accuracy: 0.001)
    }

    func testRestoreMigratesSingleTimerSnapshots() throws {
        let clock = TestClock()
        var countdown = Countdown(duration: 300)
        countdown.start(at: clock.now)
        let legacy = TimerSnapshot(selectedDuration: 300, countdown: countdown, recentDurations: [90])
        let data = try JSONEncoder().encode(legacy)
        let restored = TimerEngine(now: { clock.now })
        restored.restore(try JSONDecoder().decode(TimerSnapshot.self, from: data))
        XCTAssertEqual(restored.timers.count, 1)
        XCTAssertEqual(restored.recentDurations, [90])
    }

    func testClockFormatting() {
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(0.2), "0:01")
        XCTAssertEqual(TimeFormat.clock(299.5), "5:00")
        XCTAssertEqual(TimeFormat.clock(300), "5:00")
        XCTAssertEqual(TimeFormat.clock(3725), "1:02:05")
        XCTAssertEqual(TimeFormat.short(45 * 60), "45m")
        XCTAssertEqual(TimeFormat.short(90 * 60), "1h 30m")
        XCTAssertEqual(TimeFormat.short(150), "2m 30s")
    }
}
