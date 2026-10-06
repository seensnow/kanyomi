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
        image.isTemplate = true
        return image
    }()
}
