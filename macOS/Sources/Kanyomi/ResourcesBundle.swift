import Foundation
extension Bundle {
    static var readerResources: Bundle {
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("KanyomiMac_Kanyomi.bundle")) { return packaged }
        return .module
    }
}
