#!/usr/bin/env swift
// Renders Resources/AppIcon.icns: a dual-legend keycap (Cyrillic П, Latin P) on an indigo squircle.
// Usage: swift scripts/make-icon.swift [output.icns]
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

let indigoTop = NSColor(srgbRed: 0.27, green: 0.33, blue: 0.85, alpha: 1)
let indigoBottom = NSColor(srgbRed: 0.12, green: 0.16, blue: 0.47, alpha: 1)
let keycapTop = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let keycapBottom = NSColor(srgbRed: 0.91, green: 0.92, blue: 0.96, alpha: 1)
let keycapSide = NSColor(srgbRed: 0.74, green: 0.77, blue: 0.87, alpha: 1)
let cyrillicColor = indigoBottom
let latinColor = NSColor(srgbRed: 0.88, green: 0.25, blue: 0.29, alpha: 1)

main()

func main() {
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Pismo.iconset")
    try? FileManager.default.removeItem(at: iconset)

    do {
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            try writePNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
            try writePNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
        try runIconutil(iconset: iconset, output: outputPath)
        print("Wrote \(outputPath)")
    } catch {
        FileHandle.standardError.write("Error: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

func writePNG(pixels: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
}

/// Draws on a 1024×1024 canvas following the macOS icon grid (824pt body, 100pt margin).
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(starting: indigoTop, ending: indigoBottom)?.draw(in: bodyPath, angle: -90)

    let keycap = NSRect(x: 252, y: 278, width: 520, height: 500)
    let side = keycap.offsetBy(dx: 0, dy: -34)

    withShadow(offsetY: -24, blur: 40, alpha: 0.35) {
        keycapSide.setFill()
        NSBezierPath(roundedRect: side, xRadius: 96, yRadius: 96).fill()
    }
    keycapSide.setFill()
    NSBezierPath(roundedRect: side, xRadius: 96, yRadius: 96).fill()

    let topPath = NSBezierPath(roundedRect: keycap, xRadius: 96, yRadius: 96)
    NSGradient(starting: keycapTop, ending: keycapBottom)?.draw(in: topPath, angle: -90)

    drawLegend("П", color: cyrillicColor, size: 230, center: NSPoint(x: keycap.minX + 150, y: keycap.maxY - 150))
    drawLegend("P", color: latinColor, size: 230, center: NSPoint(x: keycap.maxX - 150, y: keycap.minY + 150))
}

func drawLegend(_ text: String, color: NSColor, size: CGFloat, center: NSPoint) {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let bounds = string.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
    string.draw(at: NSPoint(x: center.x - bounds.midX, y: center.y - bounds.midY))
}

func withShadow(offsetY: CGFloat, blur: CGFloat, alpha: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: offsetY)
    shadow.shadowBlurRadius = blur
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func runIconutil(iconset: URL, output: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", output]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "make-icon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
}
