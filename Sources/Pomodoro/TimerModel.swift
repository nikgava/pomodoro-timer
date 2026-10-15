import AppKit
import Combine
import Foundation
#if canImport(PomodoroCore)
import PomodoroCore
#endif

/// ContinuousClock advances while the Mac sleeps and ignores changes to the wall clock.
enum SessionClock {
    private static let origin = ContinuousClock.now

    static func now() -> TimeInterval {
        let elapsed = origin.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
}

@MainActor
final class TimerModel: ObservableObject {
    @Published private(set) var engine: TimerEngine
    @Published private(set) var displayedSeconds: Int
    @Published private(set) var completion: CompletionEvent?
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled") }
    }

    var onCompletion: ((CompletionEvent) -> Void)?
    var onStateChange: (() -> Void)?
    private let defaults: UserDefaults
    private let now: () -> TimeInterval
    private let schedulesTimers: Bool
    private var deadlineTimer: Timer?
    private var displayTimer: Timer?
    private(set) var panelVisible = false
    private(set) var sleeping = false
    var hasDeadlineTimer: Bool { deadlineTimer != nil }
    var hasDisplayTimer: Bool { displayTimer != nil }

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> TimeInterval = SessionClock.now,
         schedulesTimers: Bool = true) {
        self.defaults = defaults
        self.now = now
        self.schedulesTimers = schedulesTimers
        defaults.register(defaults: ["focusMinutes": 25, "relaxMinutes": 5,
                                     "automaticallyContinues": false, "soundEnabled": true])
        let focus = Self.validMinutes(defaults.integer(forKey: "focusMinutes"), fallback: 25)
        let relax = Self.validMinutes(defaults.integer(forKey: "relaxMinutes"), fallback: 5)
        engine = TimerEngine(focusMinutes: focus, relaxMinutes: relax,
                             automaticallyContinues: defaults.bool(forKey: "automaticallyContinues"))
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        displayedSeconds = focus * 60
    }

    private static func validMinutes(_ value: Int, fallback: Int) -> Int {
        (1...180).contains(value) ? value : fallback
    }

    var automatic: Bool {
        get { engine.automaticallyContinues }
        set {
            // Settle the phase under the preference that applied before this user action.
            reconcile()
            engine.automaticallyContinues = newValue
            defaults.set(newValue, forKey: "automaticallyContinues")
        }
    }

    func minutes(for phase: Phase) -> Int { Int(engine.duration(for: phase) / 60) }

    func setMinutes(_ value: Int, for phase: Phase) {
        reconcile()
        engine.setMinutes(value, for: phase)
        defaults.set(minutes(for: phase), forKey: phase == .focus ? "focusMinutes" : "relaxMinutes")
        updateDisplay()
    }

    func select(_ phase: Phase) {
        reconcile()
        guard engine.status != .running && engine.status != .paused else { return }
        engine.select(phase)
        completion = nil
        stateChanged()
    }

    func performPrimaryAction() {
        let intendedStatus = engine.status
        reconcile()
        // A late click on “Pausa” must not accidentally start the next phase.
        if intendedStatus == .running && engine.status == .waiting { return }
        completion = nil
        let instant = now()
        switch engine.status {
        case .ready, .waiting: engine.start(at: instant)
        case .running: engine.pause(at: instant)
        case .paused: engine.resume(at: instant)
        }
        stateChanged()
    }

    func reset() {
        reconcile()
        engine.reset()
        completion = nil
        stateChanged()
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        reconcile()
        updateDisplay()
        scheduleDisplay()
    }

    func willSleep() {
        sleeping = true
        invalidateTimers()
    }

    func didWake() {
        sleeping = false
        reconcile()
        stateChanged()
    }

    func reconcile() {
        guard let event = engine.advance(to: now()) else { return }
        completion = event
        updateDisplay()
        scheduleDeadline()
        scheduleDisplay()
        onStateChange?()
        // A single event represents all phases elapsed during sleep: one popup, one sound.
        onCompletion?(event)
    }

    func shutdown() {
        invalidateTimers()
        onCompletion = nil
        onStateChange = nil
    }

    private func stateChanged() {
        updateDisplay()
        scheduleDeadline()
        scheduleDisplay()
        onStateChange?()
    }

    private func updateDisplay() {
        let seconds = max(0, Int(ceil(engine.remaining(at: now()))))
        if seconds != displayedSeconds { displayedSeconds = seconds }
    }

    private func scheduleDeadline() {
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        guard schedulesTimers, !sleeping, let deadline = engine.deadline else { return }
        let timer = Timer(timeInterval: max(0.001, deadline - now()), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deadlineTimer = nil
                self.reconcile()
                // Handles an early/coalesced firing without losing the deadline.
                if self.deadlineTimer == nil { self.scheduleDeadline() }
            }
        }
        timer.tolerance = 0.05
        deadlineTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleDisplay() {
        displayTimer?.invalidate()
        displayTimer = nil
        guard schedulesTimers, panelVisible, !sleeping, engine.status == .running else { return }
        // Align one-shot UI refreshes to changes in the displayed second.
        let remaining = engine.remaining(at: now())
        let fractional = remaining - floor(remaining)
        let delay = fractional > 0.005 ? fractional : 1
        let timer = Timer(timeInterval: max(0.02, delay), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.displayTimer = nil
                self.reconcile()
                self.updateDisplay()
                self.scheduleDisplay()
            }
        }
        timer.tolerance = 0.04
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func invalidateTimers() {
        deadlineTimer?.invalidate()
        displayTimer?.invalidate()
        deadlineTimer = nil
        displayTimer = nil
    }
}
