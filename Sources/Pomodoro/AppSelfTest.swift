import AppKit
import Foundation
#if canImport(PomodoroCore)
import PomodoroCore
#endif

/// Opt-in integration checks run against the real menu item, popover and run loop.
/// A separate defaults suite prevents changes to the user's preferences.
@MainActor
enum AppSelfTest {
    private static var offset: TimeInterval = 0
    static func now() -> TimeInterval { SessionClock.now() + offset }

    static func run(delegate: AppDelegate, reportPath: String) {
        Task { @MainActor in
            var checks: [[String: Any]] = []
            func check(_ name: String, _ result: Bool) {
                checks.append(["name": name, "passed": result])
            }
            let model = delegate.model!
            var events: [CompletionEvent] = []
            let completionHandler = model.onCompletion
            model.onCompletion = { event in
                events.append(event)
                completionHandler?(event)
            }
            try? await Task.sleep(for: .milliseconds(350))
            check("Avvio: icona nella barra dei menu", delegate.statusItem?.button?.window != nil)
            check("Nessuna icona nel Dock", NSApplication.shared.activationPolicy() == .accessory)
            check("Durate iniziali 25/5", model.minutes(for: .focus) == 25 && model.minutes(for: .relax) == 5)
            check("Inattivo senza timer programmati", !model.hasDeadlineTimer && !model.hasDisplayTimer)

            delegate.showPanel()
            try? await Task.sleep(for: .milliseconds(200))
            check("Pannello ancorato aperto", delegate.popover.isShown && model.panelVisible)
            model.soundEnabled = false
            model.setMinutes(1, for: .focus)
            model.setMinutes(1, for: .relax)
            model.performPrimaryAction()
            check("Avvio Focus", model.engine.status == .running && model.engine.phase == .focus)
            check("Aggiornamenti UI solo a pannello visibile", model.hasDisplayTimer && model.hasDeadlineTimer)
            delegate.popover.performClose(nil)
            check("Chiusura pannello: conteggio continua, aggiornamenti UI sospesi", !model.panelVisible && model.hasDeadlineTimer && !model.hasDisplayTimer)
            offset += 8.25
            model.performPrimaryAction()
            let paused = model.engine.remaining(at: now())
            check("Pausa senza timer programmati", model.engine.status == .paused && !model.hasDeadlineTimer && !model.hasDisplayTimer)
            offset += 300
            check("Pausa conserva il tempo", abs(model.engine.remaining(at: now()) - paused) < 0.001)
            model.performPrimaryAction()
            check("Ripresa mantiene il residuo", model.engine.status == .running && abs(model.engine.remaining(at: now()) - paused) < 0.1)
            offset += 60
            model.reconcile()
            check("Scadenza manuale apre il pannello", model.engine.status == .waiting && delegate.popover.isShown && events.count == 1)
            check("Scadenza indica Focus terminato", model.completion?.lastCompletedPhase == .focus && model.displayedSeconds == 0)
            for _ in 0..<10 { model.reconcile() }
            check("Nessun avviso ripetuto", events.count == 1)
            delegate.popover.performClose(nil)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            check("Nessuna riapertura dopo avviso già chiuso", !delegate.popover.isShown)
            model.performPrimaryAction()
            check("Pulsante avvia la fase successiva", model.engine.phase == .relax && model.engine.status == .running)
            model.reset()
            check("Reimposta la fase corrente", model.engine.status == .ready && model.displayedSeconds == 60 && !model.hasDeadlineTimer)

            model.select(.focus)
            model.automatic = true
            model.performPrimaryAction()
            offset += 181
            model.reconcile()
            check("Alternanza automatica ciclica", model.engine.phase == .relax && model.engine.status == .running && model.completion?.completedCount == 3)
            check("Più scadenze aggregate in un avviso", events.count == 2 && delegate.popover.isShown)
            delegate.popover.performClose(nil)
            model.willSleep()
            check("Durante sospensione nessun timer programmato", !model.hasDeadlineTimer && !model.hasDisplayTimer)
            offset += 3600
            model.didWake()
            check("Risveglio: recupero 60 periodi e un solo avviso", events.count == 3 && model.completion?.completedCount == 60 && delegate.popover.isShown)
            model.didWake()
            check("Risveglio ripetuto senza duplicati", events.count == 3)

            // Exercise the actual Foundation deadline timer with a full real minute,
            // panel closed; the previous checks simulate elapsed sleep deterministically.
            model.reset()
            model.select(.focus)
            model.automatic = false
            model.performPrimaryAction()
            delegate.popover.performClose(nil)
            let countBeforeRealDeadline = events.count
            try? await Task.sleep(for: .seconds(60))
            try? await Task.sleep(for: .milliseconds(350))
            check("Scadenza reale a pannello chiuso (60 s)", events.count == countBeforeRealDeadline + 1 && model.engine.status == .waiting)
            check("Apertura automatica reale alla scadenza", delegate.popover.isShown && model.panelVisible)

            let sound = CompletionSound()
            sound.playIfEnabled(false)
            check("Suono disattivato", sound.lastOutcome == .disabled)
            sound.playIfEnabled(true)
            let audioOutcome = String(describing: sound.lastOutcome!)
            check("Audio nativo rispetta uscita silenziosa", SystemAudioOutput.isSilent() ? sound.lastOutcome == .silentOutput : sound.lastOutcome == .played)
            try? await Task.sleep(for: .seconds(2))
            sound.stop()

            let failures = checks.filter { ($0["passed"] as? Bool) != true }.count
            let report: [String: Any] = [
                "app": "Pomodoro", "date": ISO8601DateFormatter().string(from: Date()),
                "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
                "architecture": "arm64", "checks": checks,
                "passed": checks.count - failures, "failed": failures,
                "nativeAudioOutcome": audioOutcome,
                "audioNote": "Verificata richiesta di riproduzione nativa e decisione mute. L’ascolto umano non è automatizzabile.",
                "sleepNote": "Sospensione simulata sul clock iniettato; nessuna sospensione fisica del Mac."
            ]
            do {
                let url = URL(fileURLWithPath: reportPath)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: url, options: .atomic)
            } catch {
                FileHandle.standardError.write(Data("Self-test report: \(error)\n".utf8))
            }
            UserDefaults.standard.removePersistentDomain(forName: "it.nicologavagni.Pomodoro.SelfTest.\(ProcessInfo.processInfo.processIdentifier)")
            NSApplication.shared.terminate(nil)
        }
    }

}
