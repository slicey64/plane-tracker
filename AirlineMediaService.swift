import Foundation
import UIKit
import SwiftUI

/// Service providing access to airline banners and logos packaged in AirlineMedia.bundle
@MainActor
final class AirlineMediaService {
    static let shared = AirlineMediaService()

    private let cache = NSCache<NSString, UIImage>()
    private var bundle: Bundle?

    private init() {
        if let bundleURL = Bundle.main.url(forResource: "AirlineMedia", withExtension: "bundle"),
           let b = Bundle(url: bundleURL) {
            self.bundle = b
        } else {
            self.bundle = Bundle.main
        }
    }

    /// Derives the 3-letter ICAO airline code from a callsign, flight identity, or route airline code
    static func extractAirlineICAO(
        callsign: String?,
        airlineCode: String? = nil,
        identIcao: String? = nil
    ) -> String? {
        // 1. Try explicit airline code if provided (e.g. "AAL", "DAL", "UAL")
        if let code = airlineCode?.trimmingCharacters(in: .whitespacesAndNewlines), code.count == 3 {
            let upper = code.uppercased()
            if upper.allSatisfy({ $0.isLetter }) {
                return upper
            }
        }

        // 2. Try FlightAware ident_icao (e.g. "AAL123" -> "AAL")
        if let ident = identIcao?.trimmingCharacters(in: .whitespacesAndNewlines), ident.count >= 3 {
            let prefix = String(ident.prefix(3)).uppercased()
            if prefix.allSatisfy({ $0.isLetter }) {
                return prefix
            }
        }

        // 3. Try callsign prefix (e.g. "AAL123" -> "AAL", "SWA450" -> "SWA")
        guard let cs = callsign?.trimmingCharacters(in: .whitespacesAndNewlines), cs.count >= 3 else {
            return nil
        }
        let prefix = String(cs.prefix(3)).uppercased()
        if prefix.allSatisfy({ $0.isLetter }) {
            return prefix
        }

        return nil
    }

    /// Retrieve the banner image (e.g. 255x60) for a given 3-letter airline ICAO code
    func banner(for icao: String) -> UIImage? {
        let code = icao.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 3 else { return nil }

        let cacheKey = "banner_\(code)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Check inside AirlineMedia.bundle/banners/{ICAO}.png
        if let bundle = bundle,
           let path = bundle.path(forResource: code, ofType: "png", inDirectory: "banners"),
           let image = UIImage(contentsOfFile: path) {
            cache.setObject(image, forKey: cacheKey)
            return image
        }

        // Fallback: search AirlineMedia.bundle directly by path
        if let bundleURL = Bundle.main.url(forResource: "AirlineMedia", withExtension: "bundle") {
            let fileURL = bundleURL.appendingPathComponent("banners/\(code).png")
            if let image = UIImage(contentsOfFile: fileURL.path) {
                cache.setObject(image, forKey: cacheKey)
                return image
            }
        }

        return nil
    }

    /// Retrieve the square logo image (e.g. 90x90) for a given 3-letter airline ICAO code
    func logo(for icao: String) -> UIImage? {
        let code = icao.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 3 else { return nil }

        let cacheKey = "logo_\(code)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Check inside AirlineMedia.bundle/logos/{ICAO}.png
        if let bundle = bundle,
           let path = bundle.path(forResource: code, ofType: "png", inDirectory: "logos"),
           let image = UIImage(contentsOfFile: path) {
            cache.setObject(image, forKey: cacheKey)
            return image
        }

        // Fallback: search AirlineMedia.bundle directly by path
        if let bundleURL = Bundle.main.url(forResource: "AirlineMedia", withExtension: "bundle") {
            let fileURL = bundleURL.appendingPathComponent("logos/\(code).png")
            if let image = UIImage(contentsOfFile: fileURL.path) {
                cache.setObject(image, forKey: cacheKey)
                return image
            }
        }

        return nil
    }
}
