import AppKit
import Combine
import CoreAudio
import ServiceManagement

/// This seam also lets the tests verify audio decisions without changing system settings.
@MainActor
protocol CompletionAudioPlaying: AnyObject {
    @discardableResult func play() -> Bool
    func stop()
}

@MainActor
final class CompletionSound {
    enum Outcome: Equatable {
        case disabled
        case silentOutput
        case played
        case unavailable
    }

    private let isOutputSilent: @MainActor () -> Bool
    private let player: any CompletionAudioPlaying
    private(set) var lastOutcome: Outcome?

    init(
        isOutputSilent: @escaping @MainActor () -> Bool = { SystemAudioOutput.isSilent() },
        player: any CompletionAudioPlaying = NativeCompletionAudioPlayer()
    ) {
        self.isOutputSilent = isOutputSilent
        self.player = player
    }

    func playIfEnabled(_ enabled: Bool) {
        // Never overlap two completion sounds, including a wake-up completion.
        stop()
        guard enabled else {
            lastOutcome = .disabled
            return
        }
        guard !isOutputSilent() else {
            lastOutcome = .silentOutput
            return
        }
        lastOutcome = player.play() ? .played : .unavailable
    }

    func stop() {
        player.stop()
    }
}

/// NSSound follows the current normal output device when its identifier is nil.
/// It consequently follows the user's volume and mute controls, including changes
/// during playback. It does not use the separate sound-effects output device.
@MainActor
final class NativeCompletionAudioPlayer: NSObject, CompletionAudioPlaying, NSSoundDelegate {
    private var sound: NSSound?

    func play() -> Bool {
        stop()
        guard let sound = Self.makeSound() else { return false }
        sound.delegate = self
        self.sound = sound
        if sound.play() { return true }
        self.sound = nil
        return false
    }

    static func makeSound() -> NSSound? {
        // A macOS-provided sound: no bundled media, network, audio engine or loop.
        guard let sound = NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound else {
            return nil
        }
        sound.playbackDeviceIdentifier = nil
        sound.volume = 1 // Per-stream gain only; this never changes system volume.
        sound.loops = false
        return sound
    }

    func stop() {
        sound?.stop()
        sound = nil
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if self.sound === sound { self.sound = nil }
    }
}

/// Read hardware only at completion; there are no audio listeners or polling.
enum SystemAudioOutput {
    struct Controls {
        var muted: Bool?
        var volume: Float32?

        fileprivate var silent: Bool {
            muted == true || volume.map { $0 <= 0 } == true
        }
    }

    struct State {
        var deviceAvailable: Bool
        var main: Controls
        var channels: [Controls]
    }

    static func isSilent() -> Bool {
        isSilent(state())
    }

    static func isSilent(_ state: State) -> Bool {
        guard state.deviceAvailable else { return true }
        if state.main.silent { return true }
        // Some devices expose volume/mute per channel instead of on the main
        // element. If controls are unavailable, playback still respects the
        // device's own hardware settings; we never modify those controls.
        return !state.channels.isEmpty && state.channels.allSatisfy(\.silent)
    }

    static func state() -> State {
        guard let device = defaultDevice() else {
            return State(deviceAvailable: false, main: Controls(), channels: [])
        }
        let channels = outputChannelCount(device)
        let main = controls(device: device, element: kAudioObjectPropertyElementMain)
        let channelControls = channels > 0 ? (1...channels).map { controls(device: device, element: $0) } : []
        return State(deviceAvailable: true, main: main, channels: channelControls)
    }

    private static func controls(device: AudioDeviceID, element: AudioObjectPropertyElement) -> Controls {
        Controls(
            muted: readUInt32(device, selector: kAudioDevicePropertyMute, element: element).map { $0 != 0 },
            volume: readFloat(device, selector: kAudioDevicePropertyVolumeScalar, element: element)
        )
    }

    private static func defaultDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func readUInt32(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readFloat(_ device: AudioDeviceID, selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func outputChannelCount(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + $1.mNumberChannels }
    }
}

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    private let service: any LoginItemServicing
    private static let approvalMessage = "To open Pomodoro at login, allow it in System Settings › General › Login Items & Extensions."

    init(service: any LoginItemServicing = SMAppService.mainApp) {
        self.service = service
        refresh()
    }

    func refresh() {
        let status = service.status
        enabled = status == .enabled
        requiresApproval = status == .requiresApproval
        errorMessage = requiresApproval ? Self.approvalMessage : nil
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if service.status != .enabled && service.status != .requiresApproval {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            refresh()
        } catch {
            refresh()
            if !requiresApproval {
                errorMessage = "Could not update Open at Login. Move Pomodoro to Applications and try again."
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
