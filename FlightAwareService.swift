import Foundation
import Observation

/// Models for FlightAware AeroAPI data structures

public struct FlightAwareFlightDetails: Sendable, Identifiable {
    public var id: String { ident + (scheduledOut ?? "") }
    public let ident: String
    public let identIata: String?
    public let identIcao: String?
    public let status: String?
    public let flightType: String?

    // Origin Gate & Times
    public let originIcao: String?
    public let originIata: String?
    public let originName: String?
    public let originTerminal: String?
    public let originGate: String?
    public let scheduledOut: String?
    public let estimatedOut: String?
    public let actualOut: String?

    // Destination Gate & Times
    public let destinationIcao: String?
    public let destinationIata: String?
    public let destinationName: String?
    public let destinationTerminal: String?
    public let destinationGate: String?
    public let baggageClaim: String?
    public let scheduledIn: String?
    public let estimatedIn: String?
    public let actualIn: String?

    // Delays (seconds)
    public let departureDelaySeconds: Int?
    public let arrivalDelaySeconds: Int?

    // Route info
    public let filedRoute: String?
    public let filedAltitude: Int?
    public let filedSpeed: Int?

    // Aircraft reference
    public let aircraftType: String?
    public let registration: String?

    public var originDisplay: String {
        originIata ?? originIcao ?? originName ?? "Origin"
    }

    public var destinationDisplay: String {
        destinationIata ?? destinationIcao ?? destinationName ?? "Destination"
    }

    public var departureDelayFormatted: String? {
        guard let delay = departureDelaySeconds, delay != 0 else { return nil }
        let minutes = delay / 60
        if minutes > 0 {
            return "+\(minutes) min delay"
        } else {
            return "\(abs(minutes)) min early"
        }
    }

    public var arrivalDelayFormatted: String? {
        guard let delay = arrivalDelaySeconds, delay != 0 else { return nil }
        let minutes = delay / 60
        if minutes > 0 {
            return "+\(minutes) min delay"
        } else {
            return "\(abs(minutes)) min early"
        }
    }
}

public struct FlightAwareHistoricalFlight: Sendable, Identifiable {
    public var id: String { ident + (date ?? UUID().uuidString) }
    public let ident: String
    public let date: String?
    public let origin: String?
    public let destination: String?
    public let status: String?
    public let durationFormatted: String?
    public let aircraftType: String?
}

public struct FlightAwareAircraftSpecs: Sendable, Identifiable {
    public var id: String { registration }
    public let registration: String
    public let manufacturer: String?
    public let model: String?
    public let typeIcao: String?
    public let yearBuilt: Int?
    public let engineType: String?
    public let engineCount: Int?
    public let registeredOwner: String?
    public let ownerLocation: String?

    /// Formatted age string: e.g. "8 years old (Built 2016)"
    public var ageFormatted: String? {
        guard let year = yearBuilt, year > 1900 else { return nil }
        let currentYear = Calendar.current.component(.year, from: Date())
        let age = currentYear - year
        if age <= 0 {
            return "New aircraft (Built \(year))"
        } else if age == 1 {
            return "1 year old (Built \(year))"
        } else {
            return "\(age) years old (Built \(year))"
        }
    }

    /// Full aircraft model line: e.g. "Boeing 737-824 (B738)"
    public var fullModelDescription: String {
        var parts: [String] = []
        if let mfg = manufacturer { parts.append(mfg) }
        if let mdl = model { parts.append(mdl) }
        let mfgModel = parts.joined(separator: " ")
        if let type = typeIcao, !mfgModel.contains(type) {
            return "\(mfgModel) (\(type))"
        }
        return mfgModel.isEmpty ? (typeIcao ?? "Unknown Model") : mfgModel
    }

    /// Engine description: e.g. "2x Turbofan"
    public var enginesDescription: String? {
        guard let type = engineType else { return nil }
        if let count = engineCount, count > 0 {
            return "\(count)× \(type)"
        }
        return type
    }
}

public struct FlightAwareAirportFlight: Sendable, Identifiable {
    public var id: String { ident + (scheduledTime ?? UUID().uuidString) }
    public let ident: String
    public let airportCode: String?
    public let airportName: String?
    public let terminal: String?
    public let gate: String?
    public let scheduledTime: String?
    public let status: String?
    public let aircraftType: String?
}

public struct FlightAwareAirportBoards: Sendable {
    public let departures: [FlightAwareAirportFlight]
    public let arrivals: [FlightAwareAirportFlight]
}

/// FlightAware AeroAPI (v3) client service
@Observable
@MainActor
final class FlightAwareService {
    static let shared = FlightAwareService()

    private let baseURL = "https://aeroapi.flightaware.com/aeroapi"

    // In-memory caches to save API calls
    private var flightDetailsCache: [String: FlightAwareFlightDetails] = [:]
    private var historicalFlightsCache: [String: [FlightAwareHistoricalFlight]] = [:]
    private var aircraftSpecsCache: [String: FlightAwareAircraftSpecs] = [:]
    private var airportBoardsCache: [String: (boards: FlightAwareAirportBoards, timestamp: Date)] = [:]

    // Loading states
    var isLoadingFlightData: Bool = false
    var isLoadingSpecs: Bool = false
    var isLoadingAirportBoards: Bool = false
    var lastError: String? = nil

    init() {}

    // MARK: - API Key Validation

    /// Test if an API key is valid by querying the light /airports/{id} or /flights endpoint
    func testAPIKey(_ key: String) async -> (isValid: Bool, message: String) {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            return (false, "Please enter an API key.")
        }

        guard let url = URL(string: "\(baseURL)/airports/KJFK") else {
            return (false, "Invalid endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.setValue(cleanKey, forHTTPHeaderField: "x-apikey")
        request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Network error: No response.")
            }

            if httpResponse.statusCode == 200 {
                return (true, "Key successfully verified! Connected to AeroAPI v3.")
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return (false, "Invalid API key or unauthorized (HTTP \(httpResponse.statusCode)).")
            } else {
                return (false, "Server returned status \(httpResponse.statusCode).")
            }
        } catch {
            return (false, "Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Flight Details (Gates, Delays, Schedule, Route)

    /// Fetch live flight details (gates, times, baggage, route) for a callsign or registration
    func fetchFlightDetails(ident: String, apiKey: String) async -> (active: FlightAwareFlightDetails?, history: [FlightAwareHistoricalFlight]) {
        let cleanIdent = ident.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanIdent.isEmpty, !apiKey.isEmpty else { return (nil, []) }

        // Check cache
        if let cached = flightDetailsCache[cleanIdent] {
            let hist = historicalFlightsCache[cleanIdent] ?? []
            return (cached, hist)
        }

        isLoadingFlightData = true
        defer { isLoadingFlightData = false }

        guard let url = URL(string: "\(baseURL)/flights/\(cleanIdent)?max_pages=1") else {
            return (nil, [])
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (nil, [])
            }

            let (active, history) = FlightAwareService.parseFlightsResponse(data, queryIdent: cleanIdent)
            if let act = active {
                flightDetailsCache[cleanIdent] = act
            }
            if !history.isEmpty {
                historicalFlightsCache[cleanIdent] = history
            }
            return (active, history)
        } catch {
            lastError = error.localizedDescription
            return (nil, [])
        }
    }

    // MARK: - Aircraft Specifications & Age

    /// Fetch detailed aircraft specs (exact type, manufacturer, year built/age, engines, owner)
    func fetchAircraftSpecs(ident: String, apiKey: String) async -> FlightAwareAircraftSpecs? {
        let cleanIdent = ident.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanIdent.isEmpty, !apiKey.isEmpty else { return nil }

        // Check cache
        if let cached = aircraftSpecsCache[cleanIdent] {
            return cached
        }

        isLoadingSpecs = true
        defer { isLoadingSpecs = false }

        // Try /aircraft/{ident} endpoint
        guard let url = URL(string: "\(baseURL)/aircraft/\(cleanIdent)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            if let specs = FlightAwareService.parseAircraftSpecs(data, fallbackIdent: cleanIdent) {
                aircraftSpecsCache[cleanIdent] = specs
                return specs
            }
        } catch {
            // Silently fall through
        }

        return nil
    }

    // MARK: - Airport Flight Boards (Departures & Arrivals)

    /// Fetch airport flight boards (scheduled departures & arrivals with gates)
    func fetchAirportBoards(airportCode: String, apiKey: String) async -> FlightAwareAirportBoards? {
        let cleanCode = airportCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCode.isEmpty, !apiKey.isEmpty else { return nil }

        // Cache for 60 seconds
        if let cached = airportBoardsCache[cleanCode], Date().timeIntervalSince(cached.timestamp) < 60.0 {
            return cached.boards
        }

        isLoadingAirportBoards = true
        defer { isLoadingAirportBoards = false }

        guard let url = URL(string: "\(baseURL)/airports/\(cleanCode)/flights?max_pages=1") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let boards = FlightAwareService.parseAirportBoards(data)
            airportBoardsCache[cleanCode] = (boards, Date())
            return boards
        } catch {
            return nil
        }
    }

    // MARK: - Parsing Helpers

    nonisolated static func parseFlightsResponse(_ data: Data, queryIdent: String) -> (active: FlightAwareFlightDetails?, history: [FlightAwareHistoricalFlight]) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flights = json["flights"] as? [[String: Any]] else {
            return (nil, [])
        }

        var activeFlight: FlightAwareFlightDetails? = nil
        var historyList: [FlightAwareHistoricalFlight] = []

        for flight in flights {
            let ident = (flight["ident"] as? String) ?? queryIdent
            let identIata = flight["ident_iata"] as? String
            let identIcao = flight["ident_icao"] as? String
            let status = flight["status"] as? String
            let flightType = flight["flight_type"] as? String

            let origin = flight["origin"] as? [String: Any]
            let dest = flight["destination"] as? [String: Any]

            let origIcao = origin?["code_icao"] as? String
            let origIata = origin?["code_iata"] as? String
            let origName = origin?["name"] as? String
            let origTerm = origin?["terminal"] as? String
            let origGate = origin?["gate"] as? String

            let destIcao = dest?["code_icao"] as? String
            let destIata = dest?["code_iata"] as? String
            let destName = dest?["name"] as? String
            let destTerm = dest?["terminal"] as? String
            let destGate = dest?["gate"] as? String
            let baggage = dest?["baggage_claim"] as? String

            let schedOut = flight["scheduled_out"] as? String
            let estOut = flight["estimated_out"] as? String
            let actOut = flight["actual_out"] as? String

            let schedIn = flight["scheduled_in"] as? String
            let estIn = flight["estimated_in"] as? String
            let actIn = flight["actual_in"] as? String

            let depDelay = flight["departure_delay"] as? Int
            let arrDelay = flight["arrival_delay"] as? Int

            let route = flight["route"] as? String
            let alt = flight["filed_altitude"] as? Int
            let spd = flight["filed_ete"] as? Int

            let acType = flight["aircraft_type"] as? String
            let reg = flight["registration"] as? String

            let parsed = FlightAwareFlightDetails(
                ident: ident,
                identIata: identIata,
                identIcao: identIcao,
                status: status,
                flightType: flightType,
                originIcao: origIcao,
                originIata: origIata,
                originName: origName,
                originTerminal: origTerm,
                originGate: origGate,
                scheduledOut: schedOut,
                estimatedOut: estOut,
                actualOut: actOut,
                destinationIcao: destIcao,
                destinationIata: destIata,
                destinationName: destName,
                destinationTerminal: destTerm,
                destinationGate: destGate,
                baggageClaim: baggage,
                scheduledIn: schedIn,
                estimatedIn: estIn,
                actualIn: actIn,
                departureDelaySeconds: depDelay,
                arrivalDelaySeconds: arrDelay,
                filedRoute: route,
                filedAltitude: alt,
                filedSpeed: spd,
                aircraftType: acType,
                registration: reg
            )

            // First active or en-route flight is primary
            if activeFlight == nil {
                activeFlight = parsed
            } else {
                // Subsequent flights added to history
                let oCode = origIata ?? origIcao ?? "???"
                let dCode = destIata ?? destIcao ?? "???"
                let histItem = FlightAwareHistoricalFlight(
                    ident: identIata ?? ident,
                    date: schedOut?.prefix(10).description,
                    origin: oCode,
                    destination: dCode,
                    status: status,
                    durationFormatted: nil,
                    aircraftType: acType
                )
                historyList.append(histItem)
            }
        }

        return (activeFlight, historyList)
    }

    nonisolated static func parseAircraftSpecs(_ data: Data, fallbackIdent: String) -> FlightAwareAircraftSpecs? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let reg = (json["registration"] as? String) ?? (json["tail_number"] as? String) ?? fallbackIdent
        let mfg = json["manufacturer"] as? String
        let model = (json["model"] as? String) ?? (json["type"] as? String)
        let typeIcao = json["icao_type"] as? String ?? (json["type"] as? String)
        let yearBuilt = json["year_built"] as? Int
        let engineType = json["engine_type"] as? String
        let engineCount = json["engine_count"] as? Int
        let owner = (json["registered_owner"] as? String) ?? (json["owner"] as? String)
        let ownerLoc = json["owner_location"] as? String

        return FlightAwareAircraftSpecs(
            registration: reg,
            manufacturer: mfg,
            model: model,
            typeIcao: typeIcao,
            yearBuilt: yearBuilt,
            engineType: engineType,
            engineCount: engineCount,
            registeredOwner: owner,
            ownerLocation: ownerLoc
        )
    }

    nonisolated static func parseAirportBoards(_ data: Data) -> FlightAwareAirportBoards {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FlightAwareAirportBoards(departures: [], arrivals: [])
        }

        var deps: [FlightAwareAirportFlight] = []
        var arrs: [FlightAwareAirportFlight] = []

        if let departures = json["scheduled_departures"] as? [[String: Any]] ?? json["departures"] as? [[String: Any]] {
            for dep in departures.prefix(15) {
                let id = (dep["ident_iata"] as? String) ?? (dep["ident"] as? String) ?? "Flight"
                let dest = dep["destination"] as? [String: Any]
                let orig = dep["origin"] as? [String: Any]
                let dCode = (dest?["code_iata"] as? String) ?? (dest?["code_icao"] as? String)
                let dName = dest?["name"] as? String
                let term = orig?["terminal"] as? String
                let gate = orig?["gate"] as? String
                let sched = dep["scheduled_out"] as? String
                let status = dep["status"] as? String
                let type = dep["aircraft_type"] as? String

                deps.append(FlightAwareAirportFlight(
                    ident: id,
                    airportCode: dCode,
                    airportName: dName,
                    terminal: term,
                    gate: gate,
                    scheduledTime: sched,
                    status: status,
                    aircraftType: type
                ))
            }
        }

        if let arrivals = json["scheduled_arrivals"] as? [[String: Any]] ?? json["arrivals"] as? [[String: Any]] {
            for arr in arrivals.prefix(15) {
                let id = (arr["ident_iata"] as? String) ?? (arr["ident"] as? String) ?? "Flight"
                let orig = arr["origin"] as? [String: Any]
                let dest = arr["destination"] as? [String: Any]
                let oCode = (orig?["code_iata"] as? String) ?? (orig?["code_icao"] as? String)
                let oName = orig?["name"] as? String
                let term = dest?["terminal"] as? String
                let gate = dest?["gate"] as? String
                let sched = arr["scheduled_in"] as? String
                let status = arr["status"] as? String
                let type = arr["aircraft_type"] as? String

                arrs.append(FlightAwareAirportFlight(
                    ident: id,
                    airportCode: oCode,
                    airportName: oName,
                    terminal: term,
                    gate: gate,
                    scheduledTime: sched,
                    status: status,
                    aircraftType: type
                ))
            }
        }

        return FlightAwareAirportBoards(departures: deps, arrivals: arrs)
    }
}
