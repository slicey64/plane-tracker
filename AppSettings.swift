import SwiftUI

/// App Settings for ADS-B data sources, map styles, and refresh options
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - ADS-B Data Source Settings
    enum ADSBDataSource: String, CaseIterable, Identifiable {
        case adsbLol = "adsb.lol"
        case airplanesLive = "airplanes.live"
        case adsbFi = "adsb.fi"
        case customDump1090 = "dump1090 (Local / Self-Hosted)"

        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .adsbLol:
                return "api.adsb.lol — Open community feeder network (will require API key soon...)"
            case .airplanesLive:
                return "api.airplanes.live — Global live aircraft feed"
            case .adsbFi:
                return "opendata.adsb.fi/api — global ADS-B feed"
            case .customDump1090:
                return "Local feeder feed (e.g., dump1090 / readsb / tar1090)"
            }
        }

        var description: String {
            switch self {
            case .adsbLol:
                return "Queries https://api.adsb.lol/v2/ for live positions and /api/0/route for flight plans."
            case .airplanesLive:
                return "Queries https://api.airplanes.live/v2/point/{lat}/{lon}/{dist} (subject to airplanes.live API access policies)."
            case .adsbFi:
                return "Queries https://opendata.adsb.fi/api/v3/lat/{lat}/lon/{lon}/dist/{dist}."
            case .customDump1090:
                return "Connects directly to your local SDR receiver or receiver network running dump1090 / readsb aircraft.json."
            }
        }

        var isConfigurableURL: Bool {
            self == .customDump1090
        }
    }

    var selectedSource: ADSBDataSource = .adsbLol
    var customDump1090URL: String = "http://127.0.0.1:8080/data/aircraft.json"
    var autoRefreshInterval: Double = 5.0 // seconds

    // MARK: - UI Customization Settings
    enum AppMapStyle: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case imagery = "Satellite"
        case hybrid = "Hybrid"

        var id: String { rawValue }
    }

    enum PlaneColorTheme: String, CaseIterable, Identifiable {
        case altitudeBased = "Altitude Gradient"
        case monochromaticBlue = "Aviation Blue"
        case vibrantYellow = "Radar Amber / Yellow"
        case highContrastGreen = "High-Contrast Green"

        var id: String { rawValue }
    }

    var mapStyle: AppMapStyle = .standard
    var planeColorTheme: PlaneColorTheme = .altitudeBased
    var showPlaneLabelsAlways: Bool = false
    var planeIconScaleMultiplier: Double = 1.0 // 0.8x to 1.6x
    var showRouteLines: Bool = true
    var showAirportCodesOnMap: Bool = true
}
