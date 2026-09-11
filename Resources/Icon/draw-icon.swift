import AppKit

/// App and menu-bar artwork share the exact same geometry in BrandIcon.
@main struct DrawAppIcon {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4096, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                                xRadius: 185, yRadius: 185)
        NSColor(red: 0.085, green: 0.12, blue: 0.14, alpha: 1).setFill()
        tile.fill()
        let symbol = BrandIcon.menuBar.copy() as! NSImage
        symbol.isTemplate = false
        // Tint on a separate transparent bitmap so the tile remains untouched.
        let mark = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 576,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 2560, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mark)
        symbol.draw(in: NSRect(x: 0, y: 0, width: 640, height: 576))
        NSColor(red: 0.48, green: 0.82, blue: 0.74, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 640, height: 576).fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        NSImage(cgImage: mark.cgImage!, size: .zero).draw(in: NSRect(x: 192, y: 256, width: 640, height: 576))
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
        print(output.path)
    }
}
