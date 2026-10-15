import SwiftUI
#if canImport(PomodoroCore)
import PomodoroCore
#endif

struct PanelView: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var loginItem: LoginItemController

    private var phase: Phase { model.engine.phase }
    private var status: TimerStatus { model.engine.status }
    private var canSelect: Bool { status == .ready || status == .waiting }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Pomodoro").font(.headline)
                Spacer()
                Menu {
                    Toggle("Open at Login", isOn: Binding(
                        get: { loginItem.enabled },
                        set: { loginItem.setEnabled($0) }
                    ))
                    if loginItem.requiresApproval {
                        Button("Approve in System Settings…") { loginItem.openSystemSettings() }
                    }
                    Divider()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .accessibilityLabel("Options")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Options")
            }

            VStack(spacing: 10) {
                Picker("Phase", selection: Binding(get: { phase }, set: { model.select($0) })) {
                    Text("Focus").tag(Phase.focus)
                    Text("Relax").tag(Phase.relax)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!canSelect)
                .accessibilityIdentifier("phasePicker")

                HStack(spacing: 24) {
                    durationControl(.focus)
                    durationControl(.relax)
                }
            }

            Divider()

            VStack(spacing: 7) {
                Label(phase.title, systemImage: phase == .focus ? "timer" : "leaf")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "%02d:%02d", model.displayedSeconds / 60, model.displayedSeconds % 60))
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.identity)
                    .accessibilityLabel("Time remaining")
                    .accessibilityValue("\(model.displayedSeconds / 60) minutes and \(model.displayedSeconds % 60) seconds")
                    .accessibilityIdentifier("countdown")

                VStack(spacing: 4) {
                    Text(messageTitle)
                        .font(.system(size: 13, weight: model.completion == nil ? .regular : .semibold))
                        .foregroundStyle(model.completion == nil ? Color.secondary : Color.primary)
                    Text(messageDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(height: 40)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("timerStatus")
            }

            HStack(spacing: 10) {
                Button(action: model.performPrimaryAction) {
                    Label(primaryTitle, systemImage: status == .running ? "pause.fill" : "play.fill")
                        .frame(width: 108)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("primaryAction")

                Button(action: model.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 20)
                }
                .controlSize(.large)
                .help("Reset timer (⌘R)")
                .accessibilityLabel("Reset")
                .keyboardShortcut("r", modifiers: .command)
                .accessibilityIdentifier("resetTimer")
            }

            Divider()

            VStack(spacing: 13) {
                Toggle(isOn: Binding(get: { model.automatic }, set: { model.automatic = $0 })) {
                    Text("Start next phase automatically")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("autoContinue")
                Toggle(isOn: $model.soundEnabled) {
                    Text("Sound when timer ends")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("completionSound")
            }
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.small)

            if let error = loginItem.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 366)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginItem.refresh() }
    }

    private func durationControl(_ phase: Phase) -> some View {
        Stepper(value: Binding(get: { model.minutes(for: phase) },
                               set: { model.setMinutes($0, for: phase) }), in: 1...180) {
            Text("\(model.minutes(for: phase)) min")
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .accessibilityLabel("\(phase.title) duration")
        .help("\(phase.title) duration, from 1 to 180 minutes. Changes apply the next time this phase starts.")
    }

    private var primaryTitle: String {
        switch status {
        case .running: "Pause"
        case .paused: "Resume"
        case .ready, .waiting: "Start"
        }
    }

    private var messageTitle: String {
        if let event = model.completion { return "\(event.lastCompletedPhase.title) finished" }
        switch status {
        case .ready: return phase == .focus ? "Ready to focus" : "Ready for a break"
        case .running: return "\(phase.title) in progress"
        case .paused: return "Timer paused"
        case .waiting: return "\(phase.title) finished"
        }
    }

    private var messageDetail: String {
        if status == .waiting { return "Start \(phase.next.title) when you’re ready." }
        if let event = model.completion, status == .running {
            return event.completedCount > 1
                ? "\(event.completedCount) phases finished. \(phase.title) in progress."
                : "\(phase.title) started automatically."
        }
        if status == .paused { return "Resume when you’re ready." }
        if status == .running { return "You can close this panel." }
        return "One moment at a time."
    }
}
