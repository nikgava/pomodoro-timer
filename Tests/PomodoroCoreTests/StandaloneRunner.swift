// The Command Line Tools SDK does not ship XCTest. This runner exercises the
// exact same test methods with swiftc; normal SwiftPM/Xcode builds use XCTest.
#if POMODORO_STANDALONE_TESTS
import Foundation
import Darwin

@MainActor
class XCTestCase {}

@MainActor
private enum Assertions {
    static var failureCount = 0

    static func fail(_ message: String, file: StaticString, line: UInt) {
        failureCount += 1
        print("\(file):\(line): error: \(message)")
    }
}

@MainActor
func XCTAssertEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if actual != expected {
        Assertions.fail("Expected \(expected), got \(actual)", file: file, line: line)
    }
}

@MainActor
func XCTAssertNil<T>(
    _ actual: T?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if let actual {
        Assertions.fail("Expected nil, got \(actual)", file: file, line: line)
    }
}

@main
struct TimerEngineTestRunner {
    @MainActor
    static func main() {
        let suite = TimerEngineTests()
        let tests: [(String, () -> Void)] = [
            ("defaults and start", suite.testDefaultsAndStart),
            ("fractional pause and resume", suite.testPausePreservesFractionalTimeAndResumeEstablishesNewDeadline),
            ("manual next phase", suite.testManualCompletionWaitsAndStartBeginsNextPhase),
            ("automatic exact boundaries", suite.testAutomaticAlternationAtExactBoundaries),
            ("wake and original schedule", suite.testWakeAfterMultipleCompletedPhasesPreservesOriginalSchedule),
            ("ten million missed cycles", suite.testManyMissedCyclesAreCoalescedWithoutDuplicateEvents),
            ("reset and selection", suite.testResetAndSelectionCannotSwitchRunningOrPausedTimer),
            ("editing active duration", suite.testDurationEditsDoNotChangeRunningOrPausedPhase),
            ("duration clamping", suite.testDurationClampingAndReadyEdits),
            ("automatic preference changes", suite.testAutomaticPreferenceChangesPreserveCurrentDeadline),
            ("pause at expiry", suite.testPauseAtExpiryDoesNotLosePendingCompletion),
            ("elapsed time without UI ticks", suite.testElapsedTimeAdvancesWhileNoUIReadsOccur)
        ]

        for (name, test) in tests {
            let failuresBefore = Assertions.failureCount
            test()
            print("\(Assertions.failureCount == failuresBefore ? "PASS" : "FAIL"): \(name)")
        }
        print("\(tests.count) tests, \(Assertions.failureCount) failures")
        if Assertions.failureCount > 0 { exit(1) }
    }
}
#endif
