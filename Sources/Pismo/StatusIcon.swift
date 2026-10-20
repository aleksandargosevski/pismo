import AppKit

/// Menu bar icon: a keycap outline with a Cyrillic П and a Latin P legend, matching the app icon.
/// Drawn as a template image so it adapts to light and dark menu bars.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 19), flipped: false) { rect in
            let keycap = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 4.5, yRadius: 4.5)
            keycap.lineWidth = 1.5
            NSColor.black.setStroke()
            keycap.stroke()

            drawLegend("П", center: NSPoint(x: rect.minX + 6.5, y: rect.maxY - 6.5))
            drawLegend("P", center: NSPoint(x: rect.maxX - 6.5, y: rect.minY + 6.5))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Pismo"
        return image
    }

    private static func drawLegend(_ text: String, center: NSPoint) {
        let size: CGFloat = 9.5
        let base = NSFont.systemFont(ofSize: size, weight: .heavy)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let baselineY = center.y - font.capHeight / 2
        string.draw(at: NSPoint(x: center.x - string.size().width / 2, y: baselineY + font.descender))
    }
}
