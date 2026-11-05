import Foundation
import CoreLocation
import Observation

/// Service responsible for fetching live plane data, positions, flight routes, and aircraft photos
/// Integrates adsb.lol, airplanes.live, adsb.fi, dump1090, api.adsbdb.com (as full fallback), and jetapi.dev.
@Observable
@MainActor
final class FlightTrackingService {
    /// Live aircraft currently in view
    private(set) var aircraft: [LiveAircraft] = []

    /// Cached flight routes by callsign
    private(set) var routes: [String: FlightRoute] = [:]

    /// Route for the currently selected aircraft
    private(set) var activeRoute: FlightRoute?

    /// Cached JetPhotos by registration or hex
    private(set) var photos: [String: JetPhoto] = [:]

    /// Photo loading state
    private(set) var isLoadingPhoto: Bool = false

    /// Network status flags
    private(set) var isLoading: Bool = false
    private(set) var lastUpdated: Date?
    private(set) var errorMessage: String?

    // Rate limiting & state tracking
    private var lastFetchTime: Date?
    private var lastFetchCoordinate: CLLocationCoordinate2D?

    init() {}

    /// Fetch live planes around given coordinate and radius according to the chosen ADS-B data source
    func updateAircraft(center: CLLocationCoordinate2D, radiusNmi: Int = 100, source: AppSettings.ADSBDataSource = .adsbLol, customURL: String = "") async {
        // Enforce rate limit (minimum 2.0s between requests)
        if let last = lastFetchTime, Date().timeIntervalSince(last) < 2.0 {
            return
        }

        isLoading = true
        errorMessage = nil
        lastFetchTime = Date()
        lastFetchCoordinate = center

        let clampedRadius = min(max(radiusNmi, 25), 250)

        // Formulate target URL based on selected source
        let targetURLString: String
        switch source {
        case .adsbLol:
            targetURLString = "https://api.adsb.lol/v2/lat/\(String(format: "%.4f", center.latitude))/lon/\(String(format: "%.4f", center.longitude))/dist/\(clampedRadius)"
        case .airplanesLive:
            targetURLString = "https://api.airplanes.live/v2/point/\(String(format: "%.4f", center.latitude))/\(String(format: "%.4f", center.longitude))/\(clampedRadius)"
        case .adsbFi:
            targetURLString = "https://opendata.adsb.fi/api/v3/lat/\(String(format: "%.4f", center.latitude))/lon/\(String(format: "%.4f", center.longitude))/dist/\(clampedRadius)"
        case .customDump1090:
            targetURLString = customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "http://127.0.0.1:8080/data/aircraft.json"
                : customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let url = URL(string: targetURLString) else {
            errorMessage = "Invalid source URL"
            isLoading = false
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 8.0

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                isLoading = false
                return
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 403 && source == .airplanesLive {
                    self.errorMessage = "airplanes.live requires email authorization (contact@airplanes.live)."
                } else {
                    self.errorMessage = "Source returned HTTP status \(httpResponse.statusCode)"
                }
                isLoading = false
                return
            }

            let parsedAircraft = try FlightTrackingService.parseAircraftData(data)
            self.aircraft = parsedAircraft
            self.lastUpdated = Date()
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    /// Fetch flight route for an aircraft callsign, using adsb.lol first and api.adsbdb.com as automatic backup
    func fetchRoute(for callsign: String) async -> FlightRoute? {
        let cleanCallsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCallsign.isEmpty else { return nil }

        // 1. Return cached route if already looked up
        if let cached = routes[cleanCallsign] {
            activeRoute = cached
            return cached
        }

        // 2. Primary: adsb.lol route endpoint
        if let route = await fetchRouteFromADSB(callsign: cleanCallsign) {
            routes[cleanCallsign] = route
            activeRoute = route
            return route
        }

        // 3. Backup: api.adsbdb.com flightroute endpoint
        if let route = await fetchRouteFromADSBDatabase(callsign: cleanCallsign) {
            routes[cleanCallsign] = route
            activeRoute = route
            return route
        }

        return nil
    }

    /// Enrich aircraft information (registration, type, owner, airline) using api.adsbdb.com as backup
    func enrichAircraft(_ plane: LiveAircraft) async -> LiveAircraft {
        var updated = plane
        let key = plane.registration ?? plane.hex
        let urlString = "https://api.adsbdb.com/v0/aircraft/\(key)"
        guard let url = URL(string: urlString) else { return updated }

        do {
            var request = URLRequest(url: url)
            request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 4.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return updated }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let respObj = json["response"] as? [String: Any],
               let acObj = respObj["aircraft"] as? [String: Any] {

                if updated.registration == nil, let reg = acObj["registration"] as? String {
                    updated.registration = reg
                }
                if updated.aircraftType == nil, let t = (acObj["icao_type"] as? String) ?? (acObj["type"] as? String) {
                    updated.aircraftType = t
                }
                updated.registeredOwner = acObj["registered_owner"] as? String
                updated.manufacturer = acObj["manufacturer"] as? String
            }
        } catch {
            // Silently ignore backup lookup errors
        }
        return updated
    }

    /// Fetch aircraft photo from jetphotos.com via jetapi.dev
    func fetchPhoto(for registration: String) async -> JetPhoto? {
        let cleanReg = registration.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanReg.isEmpty else { return nil }

        // Check local cache
        if let cached = photos[cleanReg] {
            return cached
        }

        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        let encodedReg = cleanReg.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanReg
        let urlString = "https://www.jetapi.dev/api?reg=\(encodedReg)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 6.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            if let photo = FlightTrackingService.parseJetPhoto(data) {
                photos[cleanReg] = photo
                return photo
            }
        } catch {
            // Photo not found or network error
        }

        return nil
    }

    /// Clear the active route polyline
    func clearActiveRoute() {
        activeRoute = nil
    }

    // MARK: - Internal Route Fetchers

    private func fetchRouteFromADSB(callsign: String) async -> FlightRoute? {
        let urlString = "https://api.adsb.lol/api/0/route/\(callsign)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 4.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return FlightTrackingService.parseRouteResponse(data, callsign: callsign)
        } catch {
            return nil
        }
    }

    private func fetchRouteFromADSBDatabase(callsign: String) async -> FlightRoute? {
        let urlString = "https://api.adsbdb.com/v0/callsign/\(callsign)"
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("FlightTrackerApp/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 4.0

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            return FlightTrackingService.parseADSBDatabaseRoute(data, callsign: callsign)
        } catch {
            return nil
        }
    }

    // MARK: - Parsers

    nonisolated static func parseJetPhoto(_ data: Data) -> JetPhoto? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jp = json["JetPhotos"] as? [String: Any],
              let images = jp["Images"] as? [[String: Any]],
              let first = images.first,
              let fullImage = first["Image"] as? String else {
            return nil
        }

        let thumb = first["Thumbnail"] as? String
        let link = first["Link"] as? String
        let photographer = first["Photographer"] as? String
        let location = first["Location"] as? String
        let dateTaken = first["DateTaken"] as? String
        let model = first["Aircraft"] as? String
        let airline = first["Airline"] as? String

        return JetPhoto(
            imageURL: fullImage,
            thumbnailURL: thumb,
            link: link,
            photographer: photographer,
            location: location,
            dateTaken: dateTaken,
            aircraftModel: model,
            airline: airline
        )
    }

    nonisolated static func parseADSBDatabaseRoute(_ data: Data, callsign: String) -> FlightRoute? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resp = json["response"] as? [String: Any],
              let fr = resp["flightroute"] as? [String: Any] else {
            return nil
        }

        let airlineObj = fr["airline"] as? [String: Any]
        let airlineCode = airlineObj?["icao"] as? String ?? (airlineObj?["iata"] as? String)
        let flightNumber = fr["callsign_iata"] as? String

        var originAirport: RouteAirport?
        var destinationAirport: RouteAirport?

        if let orig = fr["origin"] as? [String: Any] {
            originAirport = RouteAirport(
                name: orig["name"] as? String ?? "",
                icao: orig["icao_code"] as? String,
                iata: orig["iata_code"] as? String,
                location: orig["municipality"] as? String,
                latitude: orig["latitude"] as? Double,
                longitude: orig["longitude"] as? Double
            )
        }

        if let dest = fr["destination"] as? [String: Any] {
            destinationAirport = RouteAirport(
                name: dest["name"] as? String ?? "",
                icao: dest["icao_code"] as? String,
                iata: dest["iata_code"] as? String,
                location: dest["municipality"] as? String,
                latitude: dest["latitude"] as? Double,
                longitude: dest["longitude"] as? Double
            )
        }

        var iataSummary: String? = nil
        if let oIata = originAirport?.iata, let dIata = destinationAirport?.iata {
            iataSummary = "\(oIata)-\(dIata)"
        }

        return FlightRoute(
            callsign: callsign,
            airlineCode: airlineCode,
            flightNumber: flightNumber,
            originAirport: originAirport,
            destinationAirport: destinationAirport,
            airportCodesIata: iataSummary
        )
    }

    nonisolated static func parseAircraftData(_ data: Data) throws -> [LiveAircraft] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let acArray = (json["ac"] as? [[String: Any]]) ?? (json["aircraft"] as? [[String: Any]]) ?? []
        var results: [LiveAircraft] = []

        for item in acArray {
            guard let hex = item["hex"] as? String else { continue }

            guard let lat = (item["lat"] as? Double) ?? (item["latitude"] as? Double),
                  let lon = (item["lon"] as? Double) ?? (item["longitude"] as? Double) else {
                continue
            }

            let flight = ((item["flight"] as? String) ?? (item["callsign"] as? String))?.trimmingCharacters(in: .whitespaces)
            let reg = (item["r"] as? String) ?? (item["registration"] as? String)
            let type = (item["t"] as? String) ?? (item["type"] as? String)
            let alt = (item["alt_baro"] as? Int) ?? (item["altitude"] as? Int) ?? (item["alt_geom"] as? Int)
            let gs = (item["gs"] as? Double) ?? (item["speed"] as? Double)
            let track = (item["track"] as? Double) ?? (item["heading"] as? Double)
            let baroRate = (item["baro_rate"] as? Int) ?? (item["vert_rate"] as? Int)
            let squawk = item["squawk"] as? String
            let category = item["category"] as? String
            let seen = (item["seen"] as? Double) ?? (item["seen_pos"] as? Double)

            let aircraft = LiveAircraft(
                id: hex,
                hex: hex,
                callsign: flight,
                registration: reg,
                aircraftType: type,
                latitude: lat,
                longitude: lon,
                altitudeBaro: alt,
                groundSpeed: gs,
                track: track,
                verticalRate: baroRate,
                squawk: squawk,
                category: category,
                seen: seen
            )
            results.append(aircraft)
        }

        return results
    }

    nonisolated static func parseRouteResponse(_ data: Data, callsign: String) -> FlightRoute? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let airlineCode = json["airline_code"] as? String
        let number = json["number"] as? String
        let iataSummary = json["_airport_codes_iata"] as? String ?? (json["airport_codes"] as? String)

        var originAirport: RouteAirport?
        var destinationAirport: RouteAirport?

        if let airportsList = json["_airports"] as? [[String: Any]] {
            if airportsList.count >= 1 {
                let a = airportsList[0]
                originAirport = RouteAirport(
                    name: a["name"] as? String ?? "",
                    icao: a["icao"] as? String,
                    iata: a["iata"] as? String,
                    location: a["location"] as? String,
                    latitude: a["lat"] as? Double,
                    longitude: a["lon"] as? Double
                )
            }
            if airportsList.count >= 2 {
                let a = airportsList[1]
                destinationAirport = RouteAirport(
                    name: a["name"] as? String ?? "",
                    icao: a["icao"] as? String,
                    iata: a["iata"] as? String,
                    location: a["location"] as? String,
                    latitude: a["lat"] as? Double,
                    longitude: a["lon"] as? Double
                )
            }
        }

        return FlightRoute(
            callsign: callsign,
            airlineCode: airlineCode,
            flightNumber: number,
            originAirport: originAirport,
            destinationAirport: destinationAirport,
            airportCodesIata: iataSummary
        )
    }
}
