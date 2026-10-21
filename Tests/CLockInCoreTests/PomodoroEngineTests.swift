import XCTest
@testable import CLockInCore

@MainActor
final class PomodoroEngineTests: XCTestCase {
    private let config = PomodoroConfig(focus: 100, shortBreak: 10, longBreak: 30, roundsBeforeLongBreak: 4)

    private func finishPhase(_ engine: PomodoroEngine, _ clock: TestClock) {
        engine.start()
        clock.advance(engine.countdown.duration)
        XCTAssertTrue(engine.tick())
    }

    func testPhasesCycleWithLongBreakEveryFourthRound() {
        let clock = TestClock()
        let engine = PomodoroEngine(config: config, now: { clock.now })
        var phases: [PomodoroPhase] = [engine.phase]
        for _ in 0..<8 {
            finishPhase(engine, clock)
            phases.append(engine.phase)
        }
        XCTAssertEqual(phases, [
            .focus, .shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak, .focus,
        ])
        XCTAssertEqual(engine.completedFocusRounds, 0)
        XCTAssertEqual(engine.roundsToday, 4)
    }

    func testFinishedPhaseReportsNextAndWaitsWithoutAutoAdvance() {
        let clock = TestClock()
        let engine = PomodoroEngine(config: config, now: { clock.now })
        var reported: (PomodoroPhase, PomodoroPhase)?
        engine.onPhaseFinished = { reported = ($0, $1) }
        finishPhase(engine, clock)
        XCTAssertEqual(reported?.0, .focus)
        XCTAssertEqual(reported?.1, .shortBreak)
        XCTAssertFalse(engine.isActive)
        XCTAssertEqual(engine.countdown.duration, 10)
    }

    func testAutoAdvanceStartsNextPhase() {
        let clock = TestClock()
        var auto = config
        auto.autoAdvance = true
        let engine = PomodoroEngine(config: auto, now: { clock.now })
        finishPhase(engine, clock)
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertTrue(engine.isRunning)
    }

    func testSkipDoesNotCountTowardToday() {
        let clock = TestClock()
        let engine = PomodoroEngine(config: config, now: { clock.now })
        engine.start()
        engine.skip()
        XCTAssertEqual(engine.phase, .shortBreak)
        XCTAssertEqual(engine.roundsToday, 0)
        XCTAssertEqual(engine.completedFocusRounds, 1)
    }

    func testRoundsTodayResetsOnNewDay() {
        let clock = TestClock()
        let engine = PomodoroEngine(config: config, now: { clock.now })
        finishPhase(engine, clock)
        XCTAssertEqual(engine.roundsToday, 1)
        clock.advance(86_400)
        engine.tick()
        XCTAssertEqual(engine.roundsToday, 0)
    }

    func testRestoreCompletesExpiredPhaseSilently() {
        let clock = TestClock()
        let original = PomodoroEngine(config: config, now: { clock.now })
        original.start()
        let saved = original.snapshot
        clock.advance(500)
        let restored = PomodoroEngine(now: { clock.now })
        var notified = false
        restored.onPhaseFinished = { _, _ in notified = true }
        restored.restore(saved)
        XCTAssertEqual(restored.phase, .shortBreak)
        XCTAssertEqual(restored.roundsToday, 1)
        XCTAssertFalse(restored.isActive)
        XCTAssertFalse(notified)
    }
}
