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
let sourceRect = NSRect(x: 655, y: 150, width: 1532, height: 2047)
let markRect = NSRect(x: 249.343942, y: 174.001287, width: 478.983879, height: 640)
let tintedMark = NSImage(size: mark.size)
tintedMark.lockFocus()
mark.draw(in: NSRect(origin: .zero, size: mark.size))
NSColor(calibratedRed: 77 / 255, green: 102 / 255, blue: 87 / 255, alpha: 1).setFill()
NSRect(origin: .zero, size: mark.size).fill(using: .sourceAtop)
tintedMark.unlockFocus()
tintedMark.draw(in: markRect, from: sourceRect, operation: .sourceOver, fraction: 1)
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
