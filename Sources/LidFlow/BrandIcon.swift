import AppKit

enum BrandIcon {
    /// A wide screen and thin base; AppKit tints the template for menu appearance.
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let screen = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 4.5, width: 15, height: 9.5),
                                      xRadius: 1.2, yRadius: 1.2)
            screen.lineWidth = 1.3
            screen.stroke()
            let wave = NSBezierPath()
            wave.move(to: NSPoint(x: 4.7, y: 8.9))
            wave.curve(to: NSPoint(x: 15.3, y: 8.6), controlPoint1: NSPoint(x: 8.2, y: 11.4),
                       controlPoint2: NSPoint(x: 11.5, y: 6.2))
            wave.lineWidth = 1.15; wave.lineCapStyle = .round; wave.stroke()
            let base = NSBezierPath()
            base.move(to: NSPoint(x: 1, y: 3))
            base.line(to: NSPoint(x: 19, y: 3))
            base.lineWidth = 1.5; base.lineCapStyle = .round; base.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LidFlow"
        return image
    }()
}
