import AppKit
import SwiftUI

/// A small pill at the bottom of the screen that shows live microphone input while dictating.
/// It never takes focus, so the app you are typing in keeps the cursor and the paste lands there.
enum RecordingOverlay {
    private static var panel: NSPanel?

    static func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    static func hide() {
        panel?.orderOut(nil)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: OverlayView.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: OverlayView(controller: AppController.shared))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Centers the pill above the dock on the screen the mouse is on.
    private static func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = OverlayView.size
        panel.setFrame(
            NSRect(
                x: frame.midX - size.width / 2,
                y: frame.minY + 24,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }
}

/// Eases the raw band values toward the screen so the bars glide instead of jumping.
private final class SpectrumDisplay {
    private(set) var values = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var lastUpdate: Date?

    func advance(to date: Date, targets: [Float]) -> [Float] {
        let dt = Float(min(0.1, date.timeIntervalSince(lastUpdate ?? date)))
        lastUpdate = date
        // Fast attack and slower release, based on elapsed time so it looks the same at any frame rate.
        let attack = 1 - exp(-dt * 22)
        let release = 1 - exp(-dt * 6)
        for index in values.indices {
            let target = index < targets.count ? targets[index] : 0
            values[index] += (target - values[index]) * (target > values[index] ? attack : release)
        }
        return values
    }
}

private struct OverlayView: View {
    static let size = NSSize(width: 124, height: 36)

    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 3
    private static let minHeight: CGFloat = 3
    private static let maxHeight: CGFloat = 22

    let controller: AppController
    @State private var display = SpectrumDisplay()

    var body: some View {
        TimelineView(.animation) { timeline in
            let values = display.advance(to: timeline.date, targets: targets(at: timeline.date))
            Canvas { context, size in
                let count = values.count
                let total = CGFloat(count) * Self.barWidth + CGFloat(count - 1) * Self.barSpacing
                var x = (size.width - total) / 2
                for (index, value) in values.enumerated() {
                    // Slightly lower bars toward the edges give the group a rounded outline.
                    let position = abs(Double(index) / Double(count - 1) - 0.5) * 2
                    let envelope = CGFloat(1 - 0.35 * position * position)
                    let height = Self.minHeight + CGFloat(value) * envelope * (Self.maxHeight - Self.minHeight)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: Self.barWidth, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: Self.barWidth / 2), with: .color(.white))
                    x += Self.barWidth + Self.barSpacing
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Capsule().fill(.black.opacity(0.85)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }

    private func targets(at date: Date) -> [Float] {
        if controller.phase == .processing {
            // A calm travelling wave while the transcript is being fetched.
            let time = date.timeIntervalSinceReferenceDate
            return (0..<SpectrumAnalyzer.bandCount).map { index in
                Float((sin(time * 4 - Double(index) * 0.55) + 1) / 2) * 0.3
            }
        }
        return controller.spectrum.store.get()
    }
}
