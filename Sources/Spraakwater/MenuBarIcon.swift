import AppKit

/// The menu bar glyph: the microphone with sound bars from the logo, drawn so it stays crisp at any scale.
enum MenuBarIcon {
    static func image(for phase: AppController.Phase) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            switch phase {
            case .idle:
                NSColor.black.setStroke()
                NSColor.black.setFill()
                drawGlyph(bars: true)
            case .recording:
                Self.red.setStroke()
                Self.red.setFill()
                drawGlyph(bars: true)
            case .processing:
                NSColor.black.setStroke()
                NSColor.black.setFill()
                drawGlyph(bars: false)
                for index in 0..<3 {
                    let dot = NSBezierPath(ovalIn: NSRect(x: 5.2 + CGFloat(index) * 4.1, y: 7.7, width: 2.2, height: 2.2))
                    dot.fill()
                }
            }
            return true
        }
        // Template images follow the menu bar tint. The recording glyph keeps its red.
        image.isTemplate = phase != .recording
        return image
    }

    private static let red = NSColor(srgbRed: 0.93, green: 0.2, blue: 0.2, alpha: 1)

    private static func drawGlyph(bars: Bool) {
        let line = 1.4

        let capsule = NSBezierPath(roundedRect: NSRect(x: 7.8, y: 7.2, width: 4.4, height: 9), xRadius: 2.2, yRadius: 2.2)
        capsule.fill()

        let cradle = NSBezierPath()
        cradle.appendArc(withCenter: NSPoint(x: 10, y: 9.4), radius: 4.6, startAngle: 180, endAngle: 360)
        cradle.lineWidth = line
        cradle.lineCapStyle = .round
        cradle.stroke()

        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 10, y: 4.8))
        stand.line(to: NSPoint(x: 10, y: 2.4))
        stand.move(to: NSPoint(x: 7.4, y: 2.4))
        stand.line(to: NSPoint(x: 12.6, y: 2.4))
        stand.lineWidth = line
        stand.lineCapStyle = .round
        stand.stroke()

        guard bars else { return }
        for (x, height) in [(4.3, 4.5), (1.6, 8.0), (15.7, 4.5), (18.4, 8.0)] {
            let bar = NSBezierPath()
            bar.move(to: NSPoint(x: x, y: 11.7 - height / 2))
            bar.line(to: NSPoint(x: x, y: 11.7 + height / 2))
            bar.lineWidth = line
            bar.lineCapStyle = .round
            bar.stroke()
        }
    }
}
