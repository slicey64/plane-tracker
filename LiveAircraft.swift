import Foundation
import CoreLocation
import SwiftUI

/// Model representing an aircraft photo scraped from JetPhotos via jetapi.dev
nonisolated struct JetPhoto: Sendable, Identifiable {
    var id: String { link ?? imageURL }
    let imageURL: String
    let thumbnailURL: String?
    let link: String?
    let photographer: String?
    let location: String?
    let dateTaken: String?
    let aircraftModel: String?
    let airline: String?
}

/// Model representing a live aircraft fetched from ADS-B feeders
nonisolated struct LiveAircraft: Identifiable, Hashable, Sendable {
    let id: String // hex icao address
    let hex: String
    var callsign: String?
    var registration: String?
    var aircraftType: String?
    let latitude: Double
    let longitude: Double
    let altitudeBaro: Int? // feet
    let groundSpeed: Double? // knots
    let track: Double? // degrees heading (0-360)
    let verticalRate: Int? // feet per min
    let squawk: String?
    let category: String?
    let seen: Double?

    // Optional metadata enriched by adsbdb fallback
    var airlineName: String?
    var registeredOwner: String?
    var manufacturer: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Display flight number or registration or hex
    var displayName: String {
        if let callsign = callsign, !callsign.isEmpty {
            return callsign
        }
        if let reg = registration, !reg.isEmpty {
            return reg
        }
        return hex.uppercased()
    }

    /// Formatted altitude string
    var formattedAltitude: String {
        guard let alt = altitudeBaro else { return "Ground" }
        return "\(alt.formatted()) ft"
    }

    /// Formatted speed string
    var formattedSpeed: String {
        guard let speed = groundSpeed else { return "N/A" }
        return "\(Int(speed)) kts (\(Int(speed * 1.15078)) mph)"
    }

    /// Formatted heading string
    var formattedHeading: String {
        guard let t = track else { return "N/A" }
        return String(format: "%.0f°", t)
    }

    /// Formatted climb / descent rate
    var formattedVerticalRate: String {
        guard let rate = verticalRate else { return "Level" }
        if rate > 64 {
            return "+\(rate) ft/min (Climbing)"
        } else if rate < -64 {
            return "\(rate) ft/min (Descending)"
        }
        return "Level"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hex)
    }

    static func == (lhs: LiveAircraft, rhs: LiveAircraft) -> Bool {
        lhs.hex == rhs.hex
    }
}

/// Model representing route information for an aircraft from route services
nonisolated struct FlightRoute: Sendable {
    let callsign: String
    let airlineCode: String?
    let flightNumber: String?
    let originAirport: RouteAirport?
    let destinationAirport: RouteAirport?
    let airportCodesIata: String?

    var summary: String {
        if let iata = airportCodesIata, !iata.isEmpty {
            return iata
        }
        if let orig = originAirport?.displayCode, let dest = destinationAirport?.displayCode {
            return "\(orig) → \(dest)"
        }
        return "Route unavailable"
    }
}

/// Airport data in flight route
nonisolated struct RouteAirport: Sendable {
    let name: String
    let icao: String?
    let iata: String?
    let location: String?
    let latitude: Double?
    let longitude: Double?

    var displayCode: String {
        if let iata = iata, !iata.isEmpty { return iata }
        if let icao = icao, !icao.isEmpty { return icao }
        return name
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
