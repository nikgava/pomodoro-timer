import Foundation
import Darwin

@main
@MainActor
struct ModelChecksMain {
    final class Clock { var value: TimeInterval = 0 }

    static func main() {
        let suite = "it.nicologavagni.Pomodoro.ModelChecks.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock()
        let model = TimerModel(defaults: defaults, now: { clock.value })
        var failures = 0
        var count = 0
        func check(_ name: String, _ result: Bool) {
            count += 1
            if !result { failures += 1 }
            print("\(result ? "PASS" : "FAIL"): \(name)")
        }

        check("model defaults", model.minutes(for: .focus) == 25 && model.minutes(for: .relax) == 5 && model.soundEnabled && !model.automatic)
        check("idle schedules no work", !model.hasDeadlineTimer && !model.hasDisplayTimer)
        model.performPrimaryAction()
        check("running hidden: only deadline scheduled", model.engine.status == .running && model.hasDeadlineTimer && !model.hasDisplayTimer)
        clock.value = 1.25
        model.setPanelVisible(true)
        check("opening panel reads actual remaining time", model.displayedSeconds == 1499 && model.hasDisplayTimer)
        model.performPrimaryAction()
        let paused = model.engine.remaining(at: clock.value)
        check("pause cancels all work", model.engine.status == .paused && !model.hasDeadlineTimer && !model.hasDisplayTimer && paused == 1498.75)
        clock.value = 9000
        model.setPanelVisible(false)
        check("paused time remains frozen", model.engine.remaining(at: clock.value) == paused)
        model.performPrimaryAction()
        check("resume retains fractional seconds", model.engine.deadline == 10498.75 && model.hasDeadlineTimer)
        model.setMinutes(45, for: .focus)
        check("editing active duration keeps deadline", model.engine.deadline == 10498.75 && model.minutes(for: .focus) == 45)
        model.setMinutes(8, for: .relax)
        model.soundEnabled = false
        model.automatic = true
        let restored = TimerModel(defaults: defaults, now: { clock.value }, schedulesTimers: false)
        check("durations and preferences persisted locally", restored.minutes(for: .focus) == 45 && restored.minutes(for: .relax) == 8 && restored.automatic && !restored.soundEnabled)
        check("session not restored as stale active timer", restored.engine.status == .ready && restored.displayedSeconds == 2700)
        restored.shutdown()
        model.automatic = false
        var events: [CompletionEvent] = []
        model.onCompletion = { event in events.append(event) }
        clock.value = 10500
        model.reconcile()
        check("manual expiry delivered once", events.count == 1 && model.engine.status == .waiting && model.displayedSeconds == 0 && !model.hasDeadlineTimer)
        model.reconcile()
        model.didWake()
        check("no duplicate after repeated reconciliation/wake", events.count == 1)
        model.performPrimaryAction()
        check("manual starts next phase", model.engine.phase == .relax && model.engine.deadline == 10980)
        model.reset()
        check("reset cancels and clears completion", model.engine.status == .ready && model.displayedSeconds == 480 && model.completion == nil && !model.hasDeadlineTimer)
        model.select(.focus)
        model.setMinutes(1, for: .focus)
        model.setMinutes(1, for: .relax)
        model.automatic = true
        model.performPrimaryAction()
        model.willSleep()
        check("sleep cancels all scheduled work", model.sleeping && !model.hasDeadlineTimer && !model.hasDisplayTimer)
        clock.value += 3601
        model.didWake()
        check("wake catches up cycles once", events.count == 2 && model.completion?.completedCount == 60 && model.engine.phase == .focus && model.displayedSeconds == 59 && model.hasDeadlineTimer)
        model.reconcile()
        check("cycle recovery no repeated event", events.count == 2)
        model.reset()
        model.select(.relax)
        check("phase selection at rest", model.engine.phase == .relax && model.displayedSeconds == 60)
        model.performPrimaryAction()
        model.select(.focus)
        check("phase selection blocked while running", model.engine.phase == .relax)
        model.performPrimaryAction()
        model.select(.focus)
        check("phase selection blocked while paused", model.engine.phase == .relax)
        model.shutdown()
        check("shutdown cancels work and callbacks", !model.hasDeadlineTimer && !model.hasDisplayTimer && model.onCompletion == nil)

        defaults.set(-3, forKey: "focusMinutes")
        defaults.set(181, forKey: "relaxMinutes")
        let repaired = TimerModel(defaults: defaults, schedulesTimers: false)
        check("invalid local values fall back to defaults", repaired.minutes(for: .focus) == 25 && repaired.minutes(for: .relax) == 5)
        repaired.setMinutes(500, for: .focus)
        check("duration bounds persisted after clamping", repaired.minutes(for: .focus) == 180 && defaults.integer(forKey: "focusMinutes") == 180)
        repaired.shutdown()

        let raceClock = Clock()
        defaults.set(false, forKey: "automaticallyContinues")
        defaults.set(1, forKey: "focusMinutes")
        let race = TimerModel(defaults: defaults, now: { raceClock.value }, schedulesTimers: false)
        race.performPrimaryAction()
        raceClock.value = 61
        race.performPrimaryAction()
        check("late pause click preserves manual completion", race.engine.status == .waiting && race.engine.phase == .focus && race.completion?.lastCompletedPhase == .focus)
        race.performPrimaryAction()
        check("subsequent explicit action starts next phase", race.engine.status == .running && race.engine.phase == .relax)
        race.shutdown()
        print("\(count) model checks, \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
