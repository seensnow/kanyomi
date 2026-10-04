import AppKit
import Foundation
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.91, green: 0.87, blue: 0.77, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 215, yRadius: 215).fill()
NSColor(calibratedRed: 0.30, green: 0.40, blue: 0.34, alpha: 1).setFill()
let book = NSBezierPath(); book.move(to: NSPoint(x: 185, y: 240)); book.line(to: NSPoint(x: 185, y: 740)); book.curve(to: NSPoint(x: 510, y: 705), controlPoint1: NSPoint(x: 330, y: 785), controlPoint2: NSPoint(x: 450, y: 745)); book.curve(to: NSPoint(x: 835, y: 740), controlPoint1: NSPoint(x: 570, y: 745), controlPoint2: NSPoint(x: 690, y: 785)); book.line(to: NSPoint(x: 835, y: 240)); book.curve(to: NSPoint(x: 510, y: 215), controlPoint1: NSPoint(x: 690, y: 275), controlPoint2: NSPoint(x: 570, y: 255)); book.curve(to: NSPoint(x: 185, y: 240), controlPoint1: NSPoint(x: 450, y: 255), controlPoint2: NSPoint(x: 330, y: 275)); book.close(); book.fill()
NSColor(calibratedRed: 0.86, green: 0.69, blue: 0.43, alpha: 1).setStroke(); let line = NSBezierPath(); line.lineWidth = 8; line.move(to: NSPoint(x: 510,y:235)); line.line(to: NSPoint(x:510,y:685)); line.stroke()
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Hiragino Mincho ProN", size: 260) ?? .systemFont(ofSize: 260), .foregroundColor: NSColor(calibratedRed: 0.94, green: 0.90, blue: 0.81, alpha: 1)]
NSString(string: "読").draw(at: NSPoint(x: 240, y: 380), withAttributes: attrs)
NSColor(calibratedRed: 0.76, green: 0.52, blue: 0.29, alpha: 1).setFill(); let star = NSBezierPath(); star.move(to: NSPoint(x:755,y:895)); star.line(to:NSPoint(x:779,y:825)); star.line(to:NSPoint(x:849,y:801)); star.line(to:NSPoint(x:779,y:777)); star.line(to:NSPoint(x:755,y:707)); star.line(to:NSPoint(x:731,y:777)); star.line(to:NSPoint(x:661,y:801)); star.line(to:NSPoint(x:731,y:825)); star.close(); star.fill()
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
