import AppKit
import SwiftUI
import ServiceManagement
@preconcurrency import ScreenCaptureKit

@MainActor
private enum PreviewClock {
    static var time: TimeInterval = 0
}

@MainActor
private final class PreviewLoginService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    func register() throws { status = .enabled }
    func unregister() throws { status = .notRegistered }
}

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private let outputDirectory: URL
    private let suiteName = "it.nicologavagni.Pomodoro.Preview.\(ProcessInfo.processInfo.processIdentifier)"
    private var model: TimerModel!
    private var loginItem: LoginItemController!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var finished = false

    init(outputDirectory: URL) { self.outputDirectory = outputDirectory }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard #available(macOS 14.4, *) else {
            finish(error: "L’anteprima richiede macOS 14.4 o successivo.")
            return
        }
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        model = TimerModel(defaults: defaults, now: { PreviewClock.time }, schedulesTimers: false)
        loginItem = LoginItemController(service: PreviewLoginService())
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Anteprima Pomodoro")
        statusItem.button?.image?.isTemplate = true
        popover.behavior = .applicationDefined
        popover.animates = false

        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                try await capture(appearance: .aqua, filename: "Pomodoro-chiaro.png")
                try await capture(appearance: .darkAqua, filename: "Pomodoro-scuro.png")
                model.performPrimaryAction()
                PreviewClock.time = 25 * 60
                model.reconcile()
                try await capture(appearance: .aqua, filename: "Pomodoro-scadenza.png")
                finish()
            } catch {
                finish(error: error.localizedDescription)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, !self.finished else { return }
            self.finish(error: "Tempo massimo di acquisizione superato.")
        }
    }

    @available(macOS 14.4, *)
    private func capture(appearance name: NSAppearance.Name, filename: String) async throws {
        try await Task.sleep(for: .milliseconds(250))
        guard let button = statusItem.button else { throw PreviewError("Icona della barra dei menu non disponibile.") }
        let appearance = NSAppearance(named: name)!
        popover.close()
        NSApp.appearance = appearance
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, loginItem: loginItem))
        popover.contentViewController?.view.appearance = appearance
        NSApp.activate(ignoringOtherApps: true)
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        try await Task.sleep(for: .milliseconds(500))
        guard let window = popover.contentViewController?.view.window else {
            throw PreviewError("Il pannello nativo non dispone di una finestra.")
        }
        window.appearance = appearance
        window.makeKey()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        // This API exposes only content this process may capture without TCC consent.
        // Match the exact popover window; never enumerate global shareable content.
        let ownContent = try await SCShareableContent.currentProcess
        guard let ownWindow = ownContent.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw PreviewError("Il pannello non è disponibile tra le finestre acquisibili di questo processo.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: ownWindow)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * 2).rounded())
        configuration.height = Int((filter.contentRect.height * 2).rounded())
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw PreviewError("Impossibile creare il PNG.")
        }
        let output = outputDirectory.appendingPathComponent(filename)
        try png.write(to: output)
        print("Anteprima: \(output.path) (\(image.width)×\(image.height))")
    }

    private func finish(error: String? = nil) {
        guard !finished else { return }
        finished = true
        popover.close()
        model?.shutdown()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        if let error {
            print("Anteprima non disponibile: \(error)")
            exit(1)
        }
        NSApp.terminate(nil)
    }
}

private struct PreviewError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

@main
private enum PreviewMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs", isDirectory: true)
        let delegate = PreviewDelegate(outputDirectory: output)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
