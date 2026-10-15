import Foundation

public enum Phase: String, CaseIterable, Sendable {
    case focus
    case relax

    public var title: String {
        switch self {
        case .focus: "Focus"
        case .relax: "Relax"
        }
    }

    public var next: Phase { self == .focus ? .relax : .focus }
}

public enum TimerStatus: Equatable, Sendable {
    case ready
    case running
    case paused
    case waiting
}

public struct CompletionEvent: Equatable, Sendable {
    public let lastCompletedPhase: Phase
    public let completedCount: Int

    public init(lastCompletedPhase: Phase, completedCount: Int) {
        self.lastCompletedPhase = lastCompletedPhase
        self.completedCount = completedCount
    }
}

/// A timer state machine with no clocks, scheduled work, or UI dependencies.
///
/// Callers supply a monotonic clock that includes system sleep. A running phase
/// retains its original deadline when its duration or preferences are edited.
public struct TimerEngine: Sendable {
    public private(set) var phase: Phase = .focus
    public private(set) var status: TimerStatus = .ready
    public private(set) var deadline: TimeInterval?
    public var automaticallyContinues: Bool

    private var focusDuration: TimeInterval
    private var relaxDuration: TimeInterval
    private var pausedRemaining: TimeInterval?

    public init(
        focusMinutes: Int = 25,
        relaxMinutes: Int = 5,
        automaticallyContinues: Bool = false
    ) {
        focusDuration = Self.duration(minutes: focusMinutes)
        relaxDuration = Self.duration(minutes: relaxMinutes)
        self.automaticallyContinues = automaticallyContinues
    }

    public func duration(for phase: Phase) -> TimeInterval {
        phase == .focus ? focusDuration : relaxDuration
    }

    public func remaining(at now: TimeInterval) -> TimeInterval {
        switch status {
        case .ready:
            duration(for: phase)
        case .running:
            max(0, (deadline ?? now) - now)
        case .paused:
            pausedRemaining ?? 0
        case .waiting:
            0
        }
    }

    public mutating func start(at now: TimeInterval) {
        guard status == .ready || status == .waiting else { return }
        if status == .waiting { phase = phase.next }
        status = .running
        pausedRemaining = nil
        deadline = now + duration(for: phase)
    }

    public mutating func pause(at now: TimeInterval) {
        guard status == .running, let deadline else { return }
        // Preserve an overdue phase for advance(to:), which owns delivery of
        // completion events. Pausing must never consume a pending completion.
        let remaining = deadline - now
        guard remaining > 0 else { return }
        pausedRemaining = remaining
        self.deadline = nil
        status = .paused
    }

    public mutating func resume(at now: TimeInterval) {
        guard status == .paused, let pausedRemaining else { return }
        deadline = now + pausedRemaining
        self.pausedRemaining = nil
        status = .running
    }

    public mutating func reset() {
        deadline = nil
        pausedRemaining = nil
        status = .ready
    }

    public mutating func select(_ phase: Phase) {
        guard status != .running && status != .paused else { return }
        self.phase = phase
        reset()
    }

    public mutating func setMinutes(_ minutes: Int, for phase: Phase) {
        switch phase {
        case .focus: focusDuration = Self.duration(minutes: minutes)
        case .relax: relaxDuration = Self.duration(minutes: minutes)
        }
    }

    /// Advances directly to `now`, coalescing all overdue phases into one event.
    /// Catch-up is constant time, even after a long system suspension.
    @discardableResult
    public mutating func advance(to now: TimeInterval) -> CompletionEvent? {
        guard status == .running, let deadline, now >= deadline else { return nil }

        guard automaticallyContinues else {
            status = .waiting
            self.deadline = nil
            return CompletionEvent(lastCompletedPhase: phase, completedCount: 1)
        }

        let completedPhase = phase
        let nextPhase = completedPhase.next
        let nextDuration = duration(for: nextPhase)
        let cycleDuration = focusDuration + relaxDuration
        let elapsed = now - deadline
        let fullCycles = floor(elapsed / cycleDuration)
        let remainder = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        let cycleStart = deadline + fullCycles * cycleDuration
        let nextAlsoCompleted = remainder >= nextDuration

        phase = nextAlsoCompleted ? completedPhase : nextPhase
        self.deadline = cycleStart + (nextAlsoCompleted ? cycleDuration : nextDuration)

        // Clock values normally fit comfortably in Int. Saturating the count
        // also keeps synthetic extreme times from trapping on conversion.
        let count = 1 + 2 * fullCycles + (nextAlsoCompleted ? 1 : 0)
        let completedCount = count >= Double(Int.max) ? Int.max : Int(count)
        return CompletionEvent(
            lastCompletedPhase: nextAlsoCompleted ? nextPhase : completedPhase,
            completedCount: completedCount
        )
    }

    private static func duration(minutes: Int) -> TimeInterval {
        TimeInterval(min(180, max(1, minutes))) * 60
    }
}
