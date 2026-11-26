import SwiftUI

/// Microphone choice as a list with a live level on the chosen one, so you hear that it works before dictating.
struct MicrophoneList: View {
    @Bindable var settings: Settings
    @State private var devices: [InputDevice] = []
    @State private var monitor = MicLevelMonitor()
    private let controller = AppController.shared

    /// A phone has to wake its microphone up first, and Bluetooth needs a moment too.
    private func grace(for uid: String) -> Int {
        switch devices.first(where: { $0.uid == uid })?.kind {
        case .iPhone: 10
        case .bluetooth: 6
        default: 3
        }
    }

    /// Restarts only when something changed, and gives a short window first, so a short loss of key focus
    /// does not close and reopen the microphone.
    @State private var pendingStop: Task<Void, Never>?

    private var chosenIsMissing: Bool {
        !settings.inputDeviceUID.isEmpty && !devices.contains { $0.uid == settings.inputDeviceUID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(
                title: "Automatisch (\(AudioDevices.defaultInputName() ?? "systeemstandaard"))",
                subtitle: "Gebruikt de standaardmicrofoon van macOS",
                recommended: false,
                uid: ""
            )
            ForEach(devices) { device in
                Divider()
                row(
                    title: device.name,
                    subtitle: device.kind.isRecommended ? "Aanbevolen microfoon" : device.kind.summary,
                    recommended: device.kind.isRecommended,
                    uid: device.uid
                )
            }
            if chosenIsMissing {
                Divider()
                row(
                    title: "Gekozen microfoon (niet aangesloten)",
                    subtitle: "Spraakwater gebruikt nu de systeemstandaard",
                    recommended: false,
                    uid: settings.inputDeviceUID
                )
            }
        }
        .onAppear {
            devices = AudioDevices.inputDevices()
            monitor.start(deviceUID: settings.inputDeviceUID, grace: grace(for: settings.inputDeviceUID))
        }
        .onDisappear {
            pendingStop?.cancel()
            monitor.stop()
        }
        // The level meter holds the microphone open, so it only runs while this window is in front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            pendingStop?.cancel()
            pendingStop = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                monitor.stop()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            pendingStop?.cancel()
            if controller.phase == .idle {
                devices = AudioDevices.inputDevices()
                monitor.start(deviceUID: settings.inputDeviceUID, grace: grace(for: settings.inputDeviceUID))
            }
        }
        // A recording needs the microphone itself.
        .onChange(of: controller.phase) {
            if controller.phase == .idle {
                monitor.start(deviceUID: settings.inputDeviceUID, grace: grace(for: settings.inputDeviceUID))
            } else {
                monitor.stop()
            }
        }
    }

    private func row(title: String, subtitle: String, recommended: Bool, uid: String) -> some View {
        let selected = settings.inputDeviceUID == uid
        return Button {
            settings.inputDeviceUID = uid
            monitor.start(deviceUID: uid, grace: grace(for: uid))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(recommended ? Color.green : Color.secondary)
                    if selected, let problem = monitor.problem {
                        Text(problem)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.red)
                    }
                }
                Spacer()
                if selected {
                    LevelBars(monitor: monitor)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.red)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Ten bars that follow the input level.
private struct LevelBars: View {
    let monitor: MicLevelMonitor
    @State private var ease = LevelEase()

    var body: some View {
        TimelineView(.animation(paused: !monitor.isRunning)) { timeline in
            let level = ease.advance(to: timeline.date, target: monitor.isRunning ? monitor.store.level : 0)
            Canvas { context, size in
                let count = 10
                let barWidth: CGFloat = 3.5
                let gap: CGFloat = 2.5
                for index in 0..<count {
                    let height = 6 + CGFloat(index) * 1.3
                    let rect = CGRect(
                        x: CGFloat(index) * (barWidth + gap),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    let active = Float(index + 1) / Float(count) <= level + 0.001
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(active ? Theme.red : Color.primary.opacity(0.12))
                    )
                }
            }
        }
        .frame(width: 10 * 3.5 + 9 * 2.5, height: 18)
        .accessibilityHidden(true)
    }
}

/// Eases the raw level so the bars glide instead of flickering.
private final class LevelEase {
    private var value: Float = 0
    private var last: Date?

    func advance(to date: Date, target: Float) -> Float {
        let dt = Float(min(0.1, date.timeIntervalSince(last ?? date)))
        last = date
        let rate: Float = target > value ? 18 : 5
        value += (target - value) * (1 - exp(-dt * rate))
        return value
    }
}
