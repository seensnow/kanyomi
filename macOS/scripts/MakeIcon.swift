import AppKit
import Foundation
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.91, green: 0.87, blue: 0.77, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 215, yRadius: 215).fill()
// Preserve the supplied calligraphy image’s proportions and transparent background.
let markURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let mark = NSImage(contentsOf: markURL) else { fatalError("Missing brand mark: \(markURL.path)") }
let markScale = min(640 / mark.size.width, 640 / mark.size.height)
let markSize = NSSize(width: mark.size.width * markScale, height: mark.size.height * markScale)
// The ink’s horizontal center of mass is 60% across the supplied image.
// Move it left by 10% of its fitted width to center the visible strokes.
let tintedMark = NSImage(size: mark.size)
tintedMark.lockFocus()
mark.draw(in: NSRect(origin: .zero, size: mark.size))
NSColor(calibratedRed: 77 / 255, green: 102 / 255, blue: 87 / 255, alpha: 1).setFill()
NSRect(origin: .zero, size: mark.size).fill(using: .sourceAtop)
tintedMark.unlockFocus()
tintedMark.draw(in: NSRect(x: (1024 - markSize.width) / 2 - markSize.width * 0.10, y: (1024 - markSize.height) / 2, width: markSize.width, height: markSize.height))
image.unlockFocus()
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        rep.size = NSSize(width: pixels,height: pixels)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep); image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels)); NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
