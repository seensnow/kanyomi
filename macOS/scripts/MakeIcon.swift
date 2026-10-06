import AppKit
import Foundation
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.91, green: 0.87, blue: 0.77, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 215, yRadius: 215).fill()
// Use a Japanese typeface for the requested kanji mark, with no extra motifs.
let mark = NSString(string: "簡")
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "HiraginoSans-W3", size: 650) ?? .systemFont(ofSize: 650),
    .foregroundColor: NSColor(calibratedRed: 0.30, green: 0.40, blue: 0.34, alpha: 1)
]
let markSize = mark.size(withAttributes: attrs)
mark.draw(at: NSPoint(x: (1024 - markSize.width) / 2, y: (1024 - markSize.height) / 2), withAttributes: attrs)
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
