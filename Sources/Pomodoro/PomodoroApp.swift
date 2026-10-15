import AppKit
import SwiftUI
#if canImport(PomodoroCore)
import PomodoroCore
#endif

@main
enum PomodoroApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private(set) var statusItem: NSStatusItem?
    private(set) var popover = NSPopover()
    private(set) var model: TimerModel!
    private let loginItem = LoginItemController()
    private let sound = CompletionSound()
    private var isTerminating = false
    private var pendingCompletionPresentation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let testReport = ProcessInfo.processInfo.arguments.firstIndex(of: "--self-test")
            .flatMap { index in
                let args = ProcessInfo.processInfo.arguments
                return index + 1 < args.count ? args[index + 1] : nil
            }
        let defaults: UserDefaults
        if testReport != nil {
            defaults = UserDefaults(suiteName: "it.nicologavagni.Pomodoro.SelfTest.\(ProcessInfo.processInfo.processIdentifier)")!
        } else {
            defaults = .standard
        }
        if testReport != nil {
            model = TimerModel(defaults: defaults, now: { AppSelfTest.now() })
        } else {
            model = TimerModel(defaults: defaults)
        }
        configureStatusItem()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, loginItem: loginItem))
        model.onStateChange = { [weak self] in self?.updateStatusItem() }
        model.onCompletion = { [weak self] _ in
            guard let self else { return }
            self.pendingCompletionPresentation = true
            self.sound.playIfEnabled(self.model.soundEnabled)
            self.showPanel()
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        updateStatusItem()

        if let testReport {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                AppSelfTest.run(delegate: self, reportPath: testReport)
            }
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }
        button.target = self
        button.action = #selector(togglePanel)
        button.setAccessibilityLabel("Pomodoro")
        let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Pomodoro")
        image?.isTemplate = true
        button.image = image
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let state: String
        switch model.engine.status {
        case .ready: state = "ready"
        case .running: state = "in progress"
        case .paused: state = "paused"
        case .waiting: state = "finished"
        }
        button.toolTip = "Pomodoro · \(model.engine.phase.title) \(state)"
        button.setAccessibilityValue("\(model.engine.phase.title) \(state)")
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }

    func showPanel() {
        guard !isTerminating, let button = statusItem?.button else { return }
        loginItem.refresh()
        model.setPanelVisible(true)
        if !popover.isShown {
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
        model.setPanelVisible(popover.isShown)
        if popover.isShown { pendingCompletionPresentation = false }
    }

    func popoverDidClose(_ notification: Notification) { model.setPanelVisible(false) }
    func popoverWillShow(_ notification: Notification) { model.setPanelVisible(true) }

    @objc private func willSleep() { model.willSleep() }
    @objc private func didWake() { model.didWake() }
    @objc private func sessionBecameActive() {
        model.reconcile()
        if pendingCompletionPresentation { showPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        model?.shutdown()
        sound.stop()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
