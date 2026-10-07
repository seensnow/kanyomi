import Foundation
import AppKit
extension Bundle {
    static var readerResources: Bundle {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("KanyomiMac_Kanyomi.bundle")) { return packaged }
        return .module
    }
}

enum BrandMark {
    static let image: NSImage = {
        guard let url = Bundle.readerResources.url(forResource: "BrandMark", withExtension: "png", subdirectory: "Resources"),
              let image = NSImage(contentsOf: url) else { return NSImage() }
        let centered = NSImage(size: NSSize(width: 1024, height: 1024))
        centered.lockFocus()
        image.draw(in: NSRect(x: 249.343942, y: 174.001287, width: 478.983879, height: 640),
                   from: NSRect(x: 655, y: 150, width: 1532, height: 2047), operation: .sourceOver, fraction: 1)
        centered.unlockFocus()
        centered.isTemplate = true
        return centered
    }()
}
