import SwiftUI

// MARK: - Color Hex Extensions

extension Color {
    init(hex: String, default defaultColor: Color = .blue) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&int) else {
            self = defaultColor
            return
        }
        let a, r, g, b: UInt64
        switch clean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            self = defaultColor
            return
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    func toHex() -> String {
        let uic = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uic.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#007AFF" }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

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
                return "api.adsb.lol — Open community feeder network"
            case .airplanesLive:
                return "api.airplanes.live — Global live aircraft feed"
            case .adsbFi:
                return "opendata.adsb.fi/api — Global ADS-B feed"
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
        case customSingle = "Custom Color"

        var id: String { rawValue }
    }

    var mapStyle: AppMapStyle = .standard
    var planeColorTheme: PlaneColorTheme = .altitudeBased
    var showPlaneLabelsAlways: Bool = false
    var planeIconScaleMultiplier: Double = 1.0 // 0.8x to 1.6x
    var showRouteLines: Bool = true
    var showAirportCodesOnMap: Bool = true
    var enableLiquidGlass: Bool = true

    // MARK: - Customizable Colors

    // Custom Plane Color (used when planeColorTheme == .customSingle)
    var customPlaneColorHex: String {
        get { UserDefaults.standard.string(forKey: "customPlaneColorHex") ?? "#007AFF" }
        set { UserDefaults.standard.set(newValue, forKey: "customPlaneColorHex") }
    }
    var customPlaneColor: Color {
        get { Color(hex: customPlaneColorHex, default: .blue) }
        set { customPlaneColorHex = newValue.toHex() }
    }

    // Airport Facility Colors
    var largeAirportColorHex: String {
        get { UserDefaults.standard.string(forKey: "largeAirportColorHex") ?? "#007AFF" }
        set { UserDefaults.standard.set(newValue, forKey: "largeAirportColorHex") }
    }
    var largeAirportColor: Color {
        get { Color(hex: largeAirportColorHex, default: .blue) }
        set { largeAirportColorHex = newValue.toHex() }
    }

    var mediumAirportColorHex: String {
        get { UserDefaults.standard.string(forKey: "mediumAirportColorHex") ?? "#5856D6" }
        set { UserDefaults.standard.set(newValue, forKey: "mediumAirportColorHex") }
    }
    var mediumAirportColor: Color {
        get { Color(hex: mediumAirportColorHex, default: .indigo) }
        set { mediumAirportColorHex = newValue.toHex() }
    }

    var smallAirportColorHex: String {
        get { UserDefaults.standard.string(forKey: "smallAirportColorHex") ?? "#30B0C7" }
        set { UserDefaults.standard.set(newValue, forKey: "smallAirportColorHex") }
    }
    var smallAirportColor: Color {
        get { Color(hex: smallAirportColorHex, default: .teal) }
        set { smallAirportColorHex = newValue.toHex() }
    }

    var heliportColorHex: String {
        get { UserDefaults.standard.string(forKey: "heliportColorHex") ?? "#FF9500" }
        set { UserDefaults.standard.set(newValue, forKey: "heliportColorHex") }
    }
    var heliportColor: Color {
        get { Color(hex: heliportColorHex, default: .orange) }
        set { heliportColorHex = newValue.toHex() }
    }

    var seaplaneBaseColorHex: String {
        get { UserDefaults.standard.string(forKey: "seaplaneBaseColorHex") ?? "#00C7BE" }
        set { UserDefaults.standard.set(newValue, forKey: "seaplaneBaseColorHex") }
    }
    var seaplaneBaseColor: Color {
        get { Color(hex: seaplaneBaseColorHex, default: .cyan) }
        set { seaplaneBaseColorHex = newValue.toHex() }
    }

    // Flight Route Line Color
    var routeLineColorHex: String {
        get { UserDefaults.standard.string(forKey: "routeLineColorHex") ?? "#007AFF" }
        set { UserDefaults.standard.set(newValue, forKey: "routeLineColorHex") }
    }
    var routeLineColor: Color {
        get { Color(hex: routeLineColorHex, default: .blue) }
        set { routeLineColorHex = newValue.toHex() }
    }

    // Selection Accent Color
    var selectionAccentColorHex: String {
        get { UserDefaults.standard.string(forKey: "selectionAccentColorHex") ?? "#007AFF" }
        set { UserDefaults.standard.set(newValue, forKey: "selectionAccentColorHex") }
    }
    var selectionAccentColor: Color {
        get { Color(hex: selectionAccentColorHex, default: .blue) }
        set { selectionAccentColorHex = newValue.toHex() }
    }

    // Color resolution helpers
    func airportColor(for type: AirportType) -> Color {
        switch type {
        case .largeAirport:
            return largeAirportColor
        case .mediumAirport:
            return mediumAirportColor
        case .smallAirport:
            return smallAirportColor
        case .heliport:
            return heliportColor
        case .seaplaneBase:
            return seaplaneBaseColor
        case .balloonport:
            return .purple
        case .closed:
            return .gray
        case .other:
            return .secondary
        }
    }

    func airportUIColor(for type: AirportType) -> UIColor {
        UIColor(airportColor(for: type))
    }

    var selectionAccentUIColor: UIColor {
        UIColor(selectionAccentColor)
    }

    var routeLineUIColor: UIColor {
        UIColor(routeLineColor)
    }

    func resetColorsToDefaults() {
        customPlaneColorHex = "#007AFF"
        largeAirportColorHex = "#007AFF"
        mediumAirportColorHex = "#5856D6"
        smallAirportColorHex = "#30B0C7"
        heliportColorHex = "#FF9500"
        seaplaneBaseColorHex = "#00C7BE"
        routeLineColorHex = "#007AFF"
        selectionAccentColorHex = "#007AFF"
    }

    // MARK: - FlightAware AeroAPI Settings (App-Specific, Not Hardcoded)
    var flightAwareAPIKey: String {
        get {
            UserDefaults.standard.string(forKey: "flightAwareAPIKey") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "flightAwareAPIKey")
        }
    }

    var isFlightAwareConfigured: Bool {
        !flightAwareAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - API-Ninjas Aircraft API Settings (https://api.api-ninjas.com/v1/aircraft)
    var apiNinjasKey: String {
        get {
            UserDefaults.standard.string(forKey: "apiNinjasKey") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "apiNinjasKey")
        }
    }

    var isApiNinjasConfigured: Bool {
        !apiNinjasKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Granular GET Waypoint / Feature Selectors for FlightAware
    var flightAwareEnableGatesAndSchedule: Bool {
        get { UserDefaults.standard.object(forKey: "fa_gates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fa_gates") }
    }

    var flightAwareEnableHistoricalFlights: Bool {
        get { UserDefaults.standard.object(forKey: "fa_history") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fa_history") }
    }

    var flightAwareEnableAircraftSpecs: Bool {
        get { UserDefaults.standard.object(forKey: "fa_specs") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fa_specs") }
    }

    var flightAwareEnableRoutes: Bool {
        get { UserDefaults.standard.object(forKey: "fa_routes") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fa_routes") }
    }

    var flightAwareEnableAirportBoards: Bool {
        get { UserDefaults.standard.object(forKey: "fa_airport_boards") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "fa_airport_boards") }
    }

    // MARK: - Multi-Source Delegation Providers
    enum GateScheduleProvider: String, CaseIterable, Identifiable {
        case flightAware = "FlightAware AeroAPI"
        case adsbdb = "adsbdb (Open ATC Fallback)"
        case disabled = "Disabled"

        var id: String { rawValue }
    }

    enum AircraftSpecsProvider: String, CaseIterable, Identifiable {
        case flightAware = "FlightAware AeroAPI"
        case adsbdb = "adsbdb (Open Database)"
        case basic = "Basic ADS-B Feed Only"

        var id: String { rawValue }
    }

    enum AirportBoardProvider: String, CaseIterable, Identifiable {
        case flightAware = "FlightAware AeroAPI"
        case disabled = "Disabled"

        var id: String { rawValue }
    }

    var gateScheduleProvider: GateScheduleProvider = .flightAware
    var aircraftSpecsProvider: AircraftSpecsProvider = .flightAware
    var airportBoardProvider: AirportBoardProvider = .flightAware
}
