import Foundation
import CoreLocation
import SwiftUI

/// Represents the classification type of an aviation facility with ranking for LOD filtering.
nonisolated enum AirportType: String, CaseIterable, Identifiable, Sendable, Codable {
    case largeAirport = "large_airport"
    case mediumAirport = "medium_airport"
    case smallAirport = "small_airport"
    case heliport = "heliport"
    case seaplaneBase = "seaplane_base"
    case balloonport = "balloonport"
    case closed = "closed"
    case other = "other"

    var id: String { rawValue }

    init(rawString: String) {
        if let match = AirportType(rawValue: rawString) {
            self = match
        } else {
            self = .other
        }
    }

    /// Numeric importance ranking (higher = more prominent facility)
    var rank: Int {
        switch self {
        case .largeAirport:
            return 3 // Major hub
        case .mediumAirport:
            return 2 // Regional / city-level
        case .smallAirport, .seaplaneBase:
            return 1 // Local / GA
        case .heliport, .balloonport, .closed, .other:
            return 0
        }
    }

    /// User-friendly title for display
    var displayName: String {
        switch self {
        case .largeAirport:
            return "Major Airport"
        case .mediumAirport:
            return "Medium Airport"
        case .smallAirport:
            return "Small / General Aviation"
        case .heliport:
            return "Heliport"
        case .seaplaneBase:
            return "Seaplane Base"
        case .balloonport:
            return "Balloonport"
        case .closed:
            return "Closed Facility"
        case .other:
            return "Other Facility"
        }
    }

    /// SF Symbol icon associated with this category.
    /// Note: "h.circle.fill" is the standard aviation symbol for heliports; "helicopter.fill" is not a system symbol in iOS.
    var systemImage: String {
        switch self {
        case .largeAirport:
            return "airplane.circle.fill"
        case .mediumAirport:
            return "airplane"
        case .smallAirport:
            return "airplane.departure"
        case .heliport:
            return "h.circle.fill"
        case .seaplaneBase:
            return "water.waves"
        case .balloonport:
            return "circle.circle.fill"
        case .closed:
            return "xmark.octagon.fill"
        case .other:
            return "mappin.and.ellipse"
        }
    }

    /// Default tint color for map pin and badges (customizable in AppSettings)
    var defaultTintColor: Color {
        switch self {
        case .largeAirport:
            return .blue
        case .mediumAirport:
            return .indigo
        case .smallAirport:
            return .teal
        case .heliport:
            return .orange
        case .seaplaneBase:
            return .cyan
        case .balloonport:
            return .purple
        case .closed:
            return .gray
        case .other:
            return .secondary
        }
    }

    var tintColor: Color {
        defaultTintColor
    }
}

/// Represents an airport queried from the airports dataset.
nonisolated struct Airport: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    let ident: String
    let type: AirportType
    let name: String
    let latitude: Double
    let longitude: Double
    let elevationFt: Int?
    let continent: String
    let isoCountry: String
    let isoRegion: String
    let municipality: String
    let scheduledService: Bool
    let icaoCode: String?
    let iataCode: String?
    let gpsCode: String?
    let localCode: String?
    let homeLink: String?
    let wikipediaLink: String?
    let keywords: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Checks if this facility is designated as an international airport
    var isInternational: Bool {
        let nameLower = name.lowercased()
        let kwLower = (keywords ?? "").lowercased()
        return nameLower.contains("international") || nameLower.contains("intl") || kwLower.contains("international")
    }

    /// The best code to display on markers and badges (IATA preferred, fallback to ICAO, local, or ident)
    var displayCode: String {
        if let iata = iataCode, !iata.isEmpty { return iata }
        if let icao = icaoCode, !icao.isEmpty { return icao }
        if let local = localCode, !local.isEmpty { return local }
        return ident
    }

    /// Clean country / state / region presentation
    var formattedRegion: String {
        if isoRegion.hasPrefix("US-") {
            let state = isoRegion.replacingOccurrences(of: "US-", with: "")
            return "\(state), USA"
        }
        if !isoRegion.isEmpty {
            return "\(isoRegion), \(isoCountry)"
        }
        return isoCountry
    }

    /// Formatted elevation in feet and meters
    var formattedElevation: String {
        guard let ft = elevationFt else { return "Not reported" }
        let meters = Int(Double(ft) * 0.3048)
        return "\(ft) ft (\(meters) m)"
    }

    /// Formatted coordinate string
    var formattedCoordinates: String {
        let latDirection = latitude >= 0 ? "N" : "S"
        let lonDirection = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@", abs(latitude), latDirection, abs(longitude), lonDirection)
    }

    /// Apple Maps URL for this airport
    var mapsURL: URL? {
        URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(ident)
    }

    static func == (lhs: Airport, rhs: Airport) -> Bool {
        lhs.id == rhs.id && lhs.ident == rhs.ident
    }
}
