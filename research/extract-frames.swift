import AppKit
import AVFoundation

let input = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let asset = AVURLAsset(url: URL(fileURLWithPath: input))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 640, height: 600)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let duration = CMTimeGetSeconds(asset.duration)
let count = 12
let cellW = 400, cellH = 340, columns = 4, rows = 3
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cellW * columns,
    pixelsHigh: cellH * rows, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: cellW * columns, height: cellH * rows).fill()
for i in 0..<count {
    let seconds = duration * Double(i) / Double(count)
    let cg = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
    let image = NSImage(cgImage: cg, size: .zero)
    let scale = min(Double(cellW - 12) / Double(cg.width), Double(cellH - 32) / Double(cg.height))
    let w = Double(cg.width) * scale, h = Double(cg.height) * scale
    let x = Double((i % columns) * cellW), y = Double((rows - 1 - i / columns) * cellH)
    image.draw(in: NSRect(x: x + (Double(cellW) - w) / 2, y: y + 28, width: w, height: h))
    (String(format: "%.2fs", seconds) as NSString).draw(at: NSPoint(x: x + 10, y: y + 5),
        withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)])
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("duration=\(duration), frames=\(count), output=\(output)")
