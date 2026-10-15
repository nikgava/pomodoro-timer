#if POMODORO_STANDALONE_TESTS
import Foundation
#else
import XCTest
@testable import PomodoroCore
#endif

final class TimerEngineTests: XCTestCase {
    func testDefaultsAndStart() {
        var engine = TimerEngine()
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.status, .ready)
        XCTAssertEqual(engine.remaining(at: 90), 1_500)
        XCTAssertEqual(engine.duration(for: .relax), 300)
        XCTAssertNil(engine.deadline)

        engine.start(at: 100)
        XCTAssertEqual(engine.status, .running)
        XCTAssertEqual(engine.deadline, 1_600)
        XCTAssertEqual(engine.remaining(at: 115.25), 1_484.75)
        engine.start(at: 200)
        XCTAssertEqual(engine.deadline, 1_600)
    }

    func testPausePreservesFractionalTimeAndResumeEstablishesNewDeadline() {
        var engine = TimerEngine(focusMinutes: 1)
        engine.start(at: 10)
        engine.pause(at: 22.375)

        XCTAssertEqual(engine.status, .paused)
        XCTAssertNil(engine.deadline)
        XCTAssertEqual(engine.remaining(at: 10_000), 47.625)
        XCTAssertNil(engine.advance(to: 10_000))
        engine.resume(at: 10_000)
        XCTAssertEqual(engine.deadline, 10_047.625)
        XCTAssertEqual(engine.remaining(at: 10_010), 37.625)
        XCTAssertNil(engine.advance(to: 10_047.624))
        XCTAssertEqual(engine.advance(to: 10_047.625)?.completedCount, 1)
    }

    func testManualCompletionWaitsAndStartBeginsNextPhase() {
        var engine = TimerEngine(focusMinutes: 1, relaxMinutes: 2)
        engine.start(at: 20)
        XCTAssertEqual(engine.advance(to: 100), CompletionEvent(lastCompletedPhase: .focus, completedCount: 1))
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.status, .waiting)
        XCTAssertEqual(engine.remaining(at: 100), 0)
        XCTAssertNil(engine.deadline)
        XCTAssertNil(engine.advance(to: 100_000))

        engine.start(at: 200)
        XCTAssertEqual(engine.phase, .relax)
        XCTAssertEqual(engine.status, .running)
        XCTAssertEqual(engine.deadline, 320)
        XCTAssertEqual(engine.advance(to: 320)?.lastCompletedPhase, .relax)
        engine.start(at: 400)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.deadline, 460)
    }

    func testAutomaticAlternationAtExactBoundaries() {
        var engine = TimerEngine(focusMinutes: 1, relaxMinutes: 2, automaticallyContinues: true)
        engine.start(at: 0)
        XCTAssertEqual(engine.advance(to: 60), CompletionEvent(lastCompletedPhase: .focus, completedCount: 1))
        XCTAssertEqual(engine.phase, .relax)
        XCTAssertEqual(engine.deadline, 180)
        XCTAssertEqual(engine.remaining(at: 60), 120)
        XCTAssertNil(engine.advance(to: 60))

        XCTAssertEqual(engine.advance(to: 180), CompletionEvent(lastCompletedPhase: .relax, completedCount: 1))
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.deadline, 240)
        XCTAssertNil(engine.advance(to: 180))
    }

    func testWakeAfterMultipleCompletedPhasesPreservesOriginalSchedule() {
        var engine = TimerEngine(focusMinutes: 1, relaxMinutes: 2, automaticallyContinues: true)
        engine.start(at: 1_000)

        // Focus ends at 1060, Relax at 1180, Focus at 1240, Relax at 1360.
        XCTAssertEqual(engine.advance(to: 1_370), CompletionEvent(lastCompletedPhase: .relax, completedCount: 4))
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.deadline, 1_420)
        XCTAssertEqual(engine.remaining(at: 1_370), 50)
        XCTAssertNil(engine.advance(to: 1_370))
    }

    func testManyMissedCyclesAreCoalescedWithoutDuplicateEvents() {
        var engine = TimerEngine(focusMinutes: 1, relaxMinutes: 2, automaticallyContinues: true)
        engine.start(at: 10)
        let cycles = 10_000_000
        let now = 70 + Double(cycles) * 180 + 30
        XCTAssertEqual(
            engine.advance(to: now),
            CompletionEvent(lastCompletedPhase: .focus, completedCount: 1 + 2 * cycles)
        )
        XCTAssertEqual(engine.phase, .relax)
        XCTAssertEqual(engine.remaining(at: now), 90)
        XCTAssertNil(engine.advance(to: now))
    }

    func testResetAndSelectionCannotSwitchRunningOrPausedTimer() {
        var engine = TimerEngine()
        engine.select(.relax)
        XCTAssertEqual(engine.phase, .relax)
        engine.start(at: 0)
        engine.select(.focus)
        XCTAssertEqual(engine.phase, .relax)
        engine.pause(at: 10)
        engine.select(.focus)
        XCTAssertEqual(engine.phase, .relax)

        engine.reset()
        XCTAssertEqual(engine.status, .ready)
        XCTAssertNil(engine.deadline)
        XCTAssertEqual(engine.remaining(at: 100), 300)
        engine.select(.focus)
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertEqual(engine.remaining(at: 100), 1_500)
    }

    func testDurationEditsDoNotChangeRunningOrPausedPhase() {
        var engine = TimerEngine(focusMinutes: 2, relaxMinutes: 1, automaticallyContinues: true)
        engine.start(at: 0)
        engine.setMinutes(3, for: .focus)
        XCTAssertEqual(engine.deadline, 120)
        XCTAssertEqual(engine.remaining(at: 30), 90)
        engine.pause(at: 30)
        engine.setMinutes(4, for: .focus)
        XCTAssertEqual(engine.remaining(at: 500), 90)
        engine.resume(at: 500)
        XCTAssertEqual(engine.deadline, 590)
        XCTAssertEqual(engine.advance(to: 590)?.lastCompletedPhase, .focus)
        XCTAssertEqual(engine.deadline, 650)
        XCTAssertEqual(engine.advance(to: 650)?.lastCompletedPhase, .relax)
        XCTAssertEqual(engine.deadline, 890)
    }

    func testDurationClampingAndReadyEdits() {
        var engine = TimerEngine(focusMinutes: Int.min, relaxMinutes: Int.max)
        XCTAssertEqual(engine.duration(for: .focus), 60)
        XCTAssertEqual(engine.duration(for: .relax), 10_800)
        engine.setMinutes(30, for: .focus)
        XCTAssertEqual(engine.remaining(at: 0), 1_800)
        engine.setMinutes(-1, for: .focus)
        engine.setMinutes(181, for: .relax)
        XCTAssertEqual(engine.duration(for: .focus), 60)
        XCTAssertEqual(engine.duration(for: .relax), 10_800)
    }

    func testAutomaticPreferenceChangesPreserveCurrentDeadline() {
        var engine = TimerEngine(focusMinutes: 1, relaxMinutes: 1)
        engine.start(at: 0)
        engine.automaticallyContinues = true
        XCTAssertEqual(engine.deadline, 60)
        XCTAssertEqual(engine.advance(to: 60)?.lastCompletedPhase, .focus)
        engine.automaticallyContinues = false
        XCTAssertEqual(engine.deadline, 120)
        XCTAssertEqual(engine.advance(to: 500), CompletionEvent(lastCompletedPhase: .relax, completedCount: 1))
        XCTAssertEqual(engine.phase, .relax)
        XCTAssertEqual(engine.status, .waiting)
        engine.automaticallyContinues = true
        XCTAssertNil(engine.advance(to: 500))
        XCTAssertEqual(engine.status, .waiting)
    }

    func testPauseAtExpiryDoesNotLosePendingCompletion() {
        var engine = TimerEngine(focusMinutes: 1)
        engine.start(at: 0)
        engine.pause(at: 60)
        XCTAssertEqual(engine.status, .running)
        XCTAssertEqual(engine.advance(to: 60)?.lastCompletedPhase, .focus)
        XCTAssertNil(engine.advance(to: 61))
    }

    func testElapsedTimeAdvancesWhileNoUIReadsOccur() {
        var engine = TimerEngine(focusMinutes: 25)
        engine.start(at: 500)
        // Simulates a closed popover and sleep: there are no intermediary ticks.
        XCTAssertEqual(engine.remaining(at: 1_900), 100)
        XCTAssertEqual(engine.advance(to: 20_000)?.lastCompletedPhase, .focus)
        XCTAssertEqual(engine.status, .waiting)
        XCTAssertNil(engine.advance(to: 30_000))
    }
}
