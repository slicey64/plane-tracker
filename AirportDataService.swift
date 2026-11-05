import Foundation
import SwiftUI
import CoreLocation
import Observation

/// Service responsible for loading, parsing, querying, and managing international and US airports from airports.csv.
@Observable
@MainActor
final class AirportDataService {
    /// Erie International Tom Ridge Field (KERI) in Erie, PA
    static let erieAirport = Airport(
        id: 3515,
        ident: "KERI",
        type: .mediumAirport,
        name: "Erie International Tom Ridge Field",
        latitude: 42.083127,
        longitude: -80.173867,
        elevationFt: 732,
        continent: "NA",
        isoCountry: "US",
        isoRegion: "US-PA",
        municipality: "Erie",
        scheduledService: true,
        icaoCode: "KERI",
        iataCode: "ERI",
        gpsCode: "KERI",
        localCode: "ERI",
        homeLink: nil,
        wikipediaLink: "https://en.wikipedia.org/wiki/Erie_International_Airport",
        keywords: nil
    )

    /// Airports consistently displayed as pins on the map
    var pinnedAirports: [Airport] = [AirportDataService.erieAirport]

    /// All international airports parsed from airports.csv (consistently shown on map)
    private(set) var internationalAirports: [Airport] = [AirportDataService.erieAirport]

    /// All queried airports parsed from airports.csv
    private(set) var allAirports: [Airport] = []

    /// Current loading state
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    init() {
        Task {
            await loadAirportsFromCSV()
        }
    }

    /// Load and parse airports.csv asynchronously in a background task
    func loadAirportsFromCSV() async {
        guard allAirports.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        let (allLoaded, intlLoaded) = await Task.detached(priority: .userInitiated) { () -> ([Airport], [Airport]) in
            var fileURL: URL?

            if let bundleURL = Bundle.main.url(forResource: "airports", withExtension: "csv") {
                fileURL = bundleURL
            } else {
                let fallback = Bundle.main.bundleURL.appendingPathComponent("airports.csv")
                if FileManager.default.fileExists(atPath: fallback.path) {
                    fileURL = fallback
                }
            }

            guard let url = fileURL, let content = try? String(contentsOf: url, encoding: .utf8) else {
                return ([], [])
            }

            return AirportDataService.parseCSV(content)
        }.value

        isLoading = false

        if allLoaded.isEmpty {
            if pinnedAirports.isEmpty {
                pinnedAirports = [Self.erieAirport]
            }
            internationalAirports = [Self.erieAirport]
            errorMessage = "Could not load airports.csv."
        } else {
            allAirports = allLoaded
            internationalAirports = intlLoaded.isEmpty ? [Self.erieAirport] : intlLoaded

            // Consistently show all international airports on the map
            pinnedAirports = internationalAirports
        }
    }

    /// Pin an airport to the map
    func pinAirport(_ airport: Airport) {
        if !pinnedAirports.contains(where: { $0.id == airport.id }) {
            pinnedAirports.append(airport)
        }
    }

    /// Unpin an airport from the map
    func unpinAirport(_ airport: Airport) {
        pinnedAirports.removeAll(where: { $0.id == airport.id })
    }

    /// Toggle pin state for an airport
    func togglePin(for airport: Airport) {
        if isPinned(airport) {
            unpinAirport(airport)
        } else {
            pinAirport(airport)
        }
    }

    /// Check if an airport is currently pinned
    func isPinned(_ airport: Airport) -> Bool {
        pinnedAirports.contains(where: { $0.id == airport.id })
    }

    /// Reset pinned airports back to all international airports
    func resetToAllInternational() {
        pinnedAirports = internationalAirports
    }

    /// Query and filter airports
    func queryAirports(text: String, typeFilter: AirportType?) -> [Airport] {
        let cleanQuery = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let baseList = cleanQuery.isEmpty && typeFilter == nil ? internationalAirports : allAirports

        return baseList.filter { airport in
            if let typeFilter = typeFilter, airport.type != typeFilter {
                return false
            }

            if cleanQuery.isEmpty {
                return true
            }

            if let iata = airport.iataCode, iata.lowercased().contains(cleanQuery) { return true }
            if let icao = airport.icaoCode, icao.lowercased().contains(cleanQuery) { return true }
            if airport.ident.lowercased().contains(cleanQuery) { return true }
            if airport.name.lowercased().contains(cleanQuery) { return true }
            if airport.municipality.lowercased().contains(cleanQuery) { return true }
            if airport.isoRegion.lowercased().contains(cleanQuery) { return true }
            if airport.isoCountry.lowercased().contains(cleanQuery) { return true }

            return false
        }
    }

    /// Helper to parse CSV data into an array of airports and international airports
    nonisolated static func parseCSV(_ content: String) -> ([Airport], [Airport]) {
        var allList: [Airport] = []
        var intlList: [Airport] = []

        var lines = content.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return ([], []) }

        // Skip header line
        lines.removeFirst()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let fields = parseCSVLine(trimmed)
            guard fields.count >= 12 else { continue }

            let typeRaw = fields[2]
            // Skip closed facilities
            if typeRaw == "closed" { continue }

            guard let id = Int(fields[0]),
                  let lat = Double(fields[4]),
                  let lon = Double(fields[5]) else {
                continue
            }

            let ident = fields[1]
            let type = AirportType(rawString: typeRaw)
            let name = fields[3]
            let elevation = fields.count > 6 ? Int(fields[6]) : nil
            let continent = fields.count > 7 ? fields[7] : "NA"
            let isoCountry = fields[8]
            let isoRegion = fields.count > 9 ? fields[9] : ""
            let municipality = fields.count > 10 ? fields[10] : ""
            let scheduled = fields.count > 11 ? (fields[11].lowercased() == "yes") : false
            let icao = (fields.count > 12 && !fields[12].isEmpty) ? fields[12] : nil
            let iata = (fields.count > 13 && !fields[13].isEmpty) ? fields[13] : nil
            let gps = (fields.count > 14 && !fields[14].isEmpty) ? fields[14] : nil
            let local = (fields.count > 15 && !fields[15].isEmpty) ? fields[15] : nil
            let home = (fields.count > 16 && !fields[16].isEmpty) ? fields[16] : nil
            let wiki = (fields.count > 17 && !fields[17].isEmpty) ? fields[17] : nil
            let keywords = (fields.count > 18 && !fields[18].isEmpty) ? fields[18] : nil

            let airport = Airport(
                id: id,
                ident: ident,
                type: type,
                name: name,
                latitude: lat,
                longitude: lon,
                elevationFt: elevation,
                continent: continent,
                isoCountry: isoCountry,
                isoRegion: isoRegion,
                municipality: municipality,
                scheduledService: scheduled,
                icaoCode: icao,
                iataCode: iata,
                gpsCode: gps,
                localCode: local,
                homeLink: home,
                wikipediaLink: wiki,
                keywords: keywords
            )

            allList.append(airport)

            if airport.isInternational {
                intlList.append(airport)
            }
        }

        return (allList, intlList)
    }

    /// RFC 4180 compliant CSV line tokenizer
    nonisolated static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let chars = Array(line)
        var i = 0
        let count = chars.count

        while i < count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < count && chars[i + 1] == "\"" {
                        current.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            i += 1
        }
        fields.append(current)
        return fields
    }
}
