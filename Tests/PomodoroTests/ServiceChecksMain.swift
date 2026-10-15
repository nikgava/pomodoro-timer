import AppKit
import Foundation
import ServiceManagement

@MainActor
private final class StubAudioPlayer: CompletionAudioPlaying {
    var plays = 0
    var stops = 0
    var succeeds = true

    func play() -> Bool {
        plays += 1
        return succeeds
    }

    func stop() { stops += 1 }
}

@MainActor
private final class StubLoginService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    var nextRegistrationStatus: SMAppService.Status = .enabled
    var registrations = 0
    var unregistrations = 0
    var registrationFails = false
    var unregistrationFails = false

    func register() throws {
        registrations += 1
        if registrationFails { throw Failure.simulated }
        status = nextRegistrationStatus
    }

    func unregister() throws {
        unregistrations += 1
        if unregistrationFails { throw Failure.simulated }
        status = .notRegistered
    }

    enum Failure: Error { case simulated }
}

/// Standalone checks run without XCTest or a full Xcode installation. All login
/// changes and audio routing decisions below use controlled dependencies.
@MainActor
enum SystemServiceChecks {
    static func run() -> [(String, Bool)] {
        var checks: [(String, Bool)] = []
        func check(_ name: String, _ passed: Bool) { checks.append((name, passed)) }

        do {
            let player = StubAudioPlayer()
            var silenceReads = 0
            let audio = CompletionSound(isOutputSilent: { silenceReads += 1; return false }, player: player)
            audio.playIfEnabled(false)
            check("Audio disabled never reads hardware or plays", player.plays == 0 && silenceReads == 0 && audio.lastOutcome == .disabled)
            audio.playIfEnabled(true)
            check("Audio enabled plays exactly once", player.plays == 1 && silenceReads == 1 && audio.lastOutcome == .played)
            audio.playIfEnabled(true)
            check("Next completion stops previous sound before playback", player.plays == 2 && player.stops == 3)
            audio.stop()
            check("Explicit sound stop reaches the player", player.stops == 4)
        }

        do {
            let player = StubAudioPlayer()
            let audio = CompletionSound(isOutputSilent: { true }, player: player)
            audio.playIfEnabled(true)
            check("Muted or zero-volume output suppresses playback", player.plays == 0 && audio.lastOutcome == .silentOutput)
        }

        do {
            let player = StubAudioPlayer()
            player.succeeds = false
            let audio = CompletionSound(isOutputSilent: { false }, player: player)
            audio.playIfEnabled(true)
            check("Audio failure is reported without a fallback beep", player.plays == 1 && audio.lastOutcome == .unavailable)
        }

        do {
            typealias Controls = SystemAudioOutput.Controls
            typealias State = SystemAudioOutput.State
            check("Main hardware mute is respected", SystemAudioOutput.isSilent(State(deviceAvailable: true, main: Controls(muted: true, volume: 0.8), channels: [])))
            check("Main system volume zero is respected", SystemAudioOutput.isSilent(State(deviceAvailable: true, main: Controls(muted: false, volume: 0), channels: [])))
            check("All silent output channels suppress playback", SystemAudioOutput.isSilent(State(deviceAvailable: true, main: Controls(), channels: [Controls(muted: true, volume: 0.5), Controls(muted: false, volume: 0)])))
            check("One audible output channel permits playback", !SystemAudioOutput.isSilent(State(deviceAvailable: true, main: Controls(), channels: [Controls(muted: true, volume: 0.5), Controls(muted: false, volume: 0.3)])))
            check("Unavailable controls defer to device hardware", !SystemAudioOutput.isSilent(State(deviceAvailable: true, main: Controls(), channels: [])))
            check("Absent output device suppresses playback", SystemAudioOutput.isSilent(State(deviceAvailable: false, main: Controls(), channels: [])))
        }

        do {
            let sound = NativeCompletionAudioPlayer.makeSound()
            check("Native completion sound is available and short", sound.map { $0.duration > 0 && $0.duration <= 3 } == true)
            check("Native sound follows default system output and gain", sound.map { $0.playbackDeviceIdentifier == nil && $0.volume == 1 && !$0.loops } == true)
        }

        do {
            let service = StubLoginService()
            let login = LoginItemController(service: service)
            check("Login refresh never registers on launch", !login.enabled && !login.requiresApproval && service.registrations == 0)
            login.setEnabled(true)
            check("Explicit login enable registers main app", login.enabled && service.registrations == 1)
            login.setEnabled(true)
            check("Repeated login enable does not register twice", service.registrations == 1)
            login.setEnabled(false)
            check("Explicit login disable unregisters main app", !login.enabled && service.unregistrations == 1)
            login.setEnabled(false)
            check("Repeated login disable does not unregister twice", service.unregistrations == 1)
            service.status = .enabled
            login.refresh()
            check("Login reflects changes made in System Settings", login.enabled)
        }

        do {
            let service = StubLoginService()
            service.nextRegistrationStatus = .requiresApproval
            let login = LoginItemController(service: service)
            login.setEnabled(true)
            check("Pending login approval is explained", !login.enabled && login.requiresApproval && login.errorMessage?.contains("System Settings") == true)
            login.setEnabled(true)
            check("Pending login approval does not register again", service.registrations == 1)
            login.setEnabled(false)
            check("Pending login registration can be cancelled", !login.requiresApproval && service.unregistrations == 1 && login.errorMessage == nil)
        }

        do {
            let service = StubLoginService()
            service.registrationFails = true
            let login = LoginItemController(service: service)
            login.setEnabled(true)
            check("Login registration failure preserves disabled state", !login.enabled && login.errorMessage != nil && service.registrations == 1)
            service.registrationFails = false
            login.setEnabled(true)
            check("Successful login retry clears previous error", login.enabled && login.errorMessage == nil)
            service.unregistrationFails = true
            login.setEnabled(false)
            check("Failed login disable preserves enabled state", login.enabled && login.errorMessage != nil)
            service.status = .notFound
            login.refresh()
            check("Missing login service reports disabled", !login.enabled && !login.requiresApproval)
        }
        return checks
    }
}

@main
struct ServiceChecksMain {
    @MainActor
    static func main() {
        let checks = SystemServiceChecks.run()
        for (name, passed) in checks {
            print("\(passed ? "PASS" : "FAIL") \(name)")
        }
        print("System service checks: \(checks.filter { $0.1 }.count)/\(checks.count) passed")

        if CommandLine.arguments.contains("--play-audio") {
            let audio = CompletionSound()
            audio.playIfEnabled(true)
            print("Native playback requested once: \(String(describing: audio.lastOutcome)). System output, volume and mute were not changed.")
            print("This confirms the native playback request; audible output requires a person listening on the selected device.")
            if audio.lastOutcome == .played {
                RunLoop.main.run(until: Date().addingTimeInterval(2))
            }
            audio.stop()
        }

        if checks.contains(where: { !$0.1 }) { exit(EXIT_FAILURE) }
    }
}
