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
        timer.start()
        clock.advance(30)
        XCTAssertEqual(timer.remaining(at: clock.now), 270, accuracy: 0.001)
        XCTAssertEqual(timer.progress(at: clock.now), 0.1, accuracy: 0.001)
    }

    func testPauseAndResumeKeepsRemainingTime() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 300, now: { clock.now })
        timer.start()
        clock.advance(60)
        timer.pause()
        clock.advance(500)
        XCTAssertEqual(timer.remaining(at: clock.now), 240, accuracy: 0.001)
        timer.start()
        clock.advance(40)
        XCTAssertEqual(timer.remaining(at: clock.now), 200, accuracy: 0.001)
    }

    func testAddMinuteExtendsRunningTimer() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 60, now: { clock.now })
        timer.start()
        clock.advance(50)
        timer.addMinute()
        XCTAssertEqual(timer.remaining(at: clock.now), 70, accuracy: 0.001)
    }

    func testTickFinishesOnceAndReturnsToSelectedDuration() {
        let clock = TestClock()
        let timer = TimerEngine(duration: 60, now: { clock.now })
        var finishCount = 0
        timer.onFinish = { finishCount += 1 }
        timer.start()
        timer.addMinute()
        clock.advance(119)
        XCTAssertFalse(timer.tick())
        clock.advance(1)
        XCTAssertTrue(timer.tick())
        XCTAssertFalse(timer.tick())
        XCTAssertEqual(finishCount, 1)
        XCTAssertFalse(timer.isActive)
        XCTAssertEqual(timer.countdown.duration, 60)
    }

    func testDurationIsClampedAndLockedWhileActive() {
        let timer = TimerEngine(duration: 0)
        XCTAssertEqual(timer.selectedDuration, 1)
        timer.setDuration(30 * 3600)
        XCTAssertEqual(timer.selectedDuration, 24 * 3600 - 1)
        timer.start()
        timer.setDuration(600)
        XCTAssertEqual(timer.selectedDuration, 24 * 3600 - 1)
    }

    func testCustomDurationsAreRememberedNewestFirst() {
        let timer = TimerEngine()
        let durations: [TimeInterval] = [90, 300, 420, 90, 1200, 180]
        for duration in durations {
            timer.setDuration(duration)
            timer.start()
            timer.cancel()
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

    func testRestoreKeepsRunningTimer() {
        let clock = TestClock()
        let original = TimerEngine(duration: 600, now: { clock.now })
        original.start()
        let saved = original.snapshot
        clock.advance(100)
        let restored = TimerEngine(now: { clock.now })
        restored.restore(saved)
        XCTAssertTrue(restored.isRunning)
        XCTAssertEqual(restored.remaining(at: clock.now), 500, accuracy: 0.001)
    }

    func testRestoreExpiredTimerComesBackIdle() {
        let clock = TestClock()
        let original = TimerEngine(duration: 60, now: { clock.now })
        original.start()
        let saved = original.snapshot
        clock.advance(3600)
        let restored = TimerEngine(now: { clock.now })
        restored.restore(saved)
        XCTAssertFalse(restored.isActive)
        XCTAssertEqual(restored.selectedDuration, 60)
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
