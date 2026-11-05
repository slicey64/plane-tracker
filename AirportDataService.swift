import Foundation
import SwiftUI
import CoreLocation
import Observation

/// Service responsible for high-performance loading, querying, and managing international and US airports.
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

    private static var cacheDirectoryURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private static var intlCacheURL: URL? {
        cacheDirectoryURL?.appendingPathComponent("intl_airports_v1.plist")
    }

    init() {
        Task {
            await loadAirports()
        }
    }

    /// Load airports with priority: fast disk cache first, falling back to optimized UTF-8 byte parser
    func loadAirports() async {
        guard allAirports.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        // Step 1: Check fast disk cache for instant startup
        let cachedIntl = await Task.detached(priority: .userInitiated) { () -> [Airport]? in
            guard let cacheURL = AirportDataService.intlCacheURL,
                  let data = try? Data(contentsOf: cacheURL) else { return nil }
            return try? PropertyListDecoder().decode([Airport].self, from: data)
        }.value

        if let cached = cachedIntl, !cached.isEmpty {
            self.internationalAirports = cached
            self.pinnedAirports = cached
            self.isLoading = false

            // Load complete database in background for searches
            Task.detached(priority: .utility) {
                await self.loadFullDataset()
            }
            return
        }

        // Step 2: Parse CSV using high-speed UTF-8 scanner
        await loadFullDataset()
    }

    private func loadFullDataset() async {
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

            guard let url = fileURL, let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                return ([], [])
            }

            return AirportDataService.parseCSVDataFast(data)
        }.value

        self.isLoading = false

        if allLoaded.isEmpty {
            if pinnedAirports.isEmpty {
                pinnedAirports = [Self.erieAirport]
            }
            internationalAirports = [Self.erieAirport]
            errorMessage = "Could not load airports.csv."
        } else {
            allAirports = allLoaded
            internationalAirports = intlLoaded.isEmpty ? [Self.erieAirport] : intlLoaded
            pinnedAirports = internationalAirports

            // Save international airports to disk cache for instantaneous future launches (<30ms)
            Task.detached(priority: .background) {
                if let cacheURL = AirportDataService.intlCacheURL,
                   let data = try? PropertyListEncoder().encode(intlLoaded) {
                    try? data.write(to: cacheURL, options: .atomic)
                }
            }
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

    /// Fast, non-blocking query and filtering with early-exit capping at 100 items
    func queryAirports(text: String, typeFilter: AirportType?) -> [Airport] {
        let cleanQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanQuery.isEmpty && typeFilter == nil {
            return internationalAirports
        }

        let baseList = cleanQuery.isEmpty ? internationalAirports : (allAirports.isEmpty ? internationalAirports : allAirports)
        var results: [Airport] = []
        results.reserveCapacity(100)

        for airport in baseList {
            if let typeFilter = typeFilter, airport.type != typeFilter {
                continue
            }

            if cleanQuery.isEmpty {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }

            // High-speed case-insensitive checks without string allocations in loop
            if let iata = airport.iataCode, iata.localizedCaseInsensitiveContains(cleanQuery) {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }

            if let icao = airport.icaoCode, icao.localizedCaseInsensitiveContains(cleanQuery) {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }

            if airport.ident.localizedCaseInsensitiveContains(cleanQuery) {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }

            if airport.name.localizedCaseInsensitiveContains(cleanQuery) {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }

            if !airport.municipality.isEmpty && airport.municipality.localizedCaseInsensitiveContains(cleanQuery) {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }

            if !airport.isoRegion.isEmpty && airport.isoRegion.localizedCaseInsensitiveContains(cleanQuery) {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }

            if !airport.isoCountry.isEmpty && airport.isoCountry.localizedCaseInsensitiveContains(cleanQuery) {
                results.append(airport)
                if results.count >= 100 { break }
                continue
            }
        }

        return results
    }

    /// Ultra-fast UTF-8 byte scanner: avoids string line splits and Character arrays
    nonisolated static func parseCSVDataFast(_ data: Data) -> ([Airport], [Airport]) {
        var all: [Airport] = []
        all.reserveCapacity(75000)
        var intl: [Airport] = []
        intl.reserveCapacity(2000)

        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = data.count
            var idx = 0

            // Skip header line
            while idx < count && base[idx] != UInt8(ascii: "\n") && base[idx] != UInt8(ascii: "\r") {
                idx += 1
            }
            while idx < count && (base[idx] == UInt8(ascii: "\n") || base[idx] == UInt8(ascii: "\r")) {
                idx += 1
            }

            var fieldStarts = [Int](repeating: 0, count: 25)
            var fieldLengths = [Int](repeating: 0, count: 25)

            while idx < count {
                var fieldCount = 0
                var inQuotes = false
                var fieldStart = idx

                while idx < count {
                    let byte = base[idx]
                    if inQuotes {
                        if byte == UInt8(ascii: "\"") {
                            if idx + 1 < count && base[idx + 1] == UInt8(ascii: "\"") {
                                idx += 1
                            } else {
                                inQuotes = false
                            }
                        }
                    } else {
                        if byte == UInt8(ascii: "\"") {
                            inQuotes = true
                            fieldStart = idx + 1
                        } else if byte == UInt8(ascii: ",") {
                            if fieldCount < 25 {
                                fieldStarts[fieldCount] = fieldStart
                                var len = idx - fieldStart
                                if len > 0 && base[idx - 1] == UInt8(ascii: "\"") { len -= 1 }
                                fieldLengths[fieldCount] = max(0, len)
                                fieldCount += 1
                            }
                            fieldStart = idx + 1
                        } else if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                            if fieldCount < 25 {
                                fieldStarts[fieldCount] = fieldStart
                                var len = idx - fieldStart
                                if len > 0 && base[idx - 1] == UInt8(ascii: "\"") { len -= 1 }
                                fieldLengths[fieldCount] = max(0, len)
                                fieldCount += 1
                            }
                            while idx < count && (base[idx] == UInt8(ascii: "\n") || base[idx] == UInt8(ascii: "\r")) {
                                idx += 1
                            }
                            break
                        }
                    }
                    idx += 1
                }

                if fieldCount >= 12 {
                    // Quick check for "closed"
                    let typeLen = fieldLengths[2]
                    let typeStart = fieldStarts[2]
                    if typeLen == 6 && base[typeStart] == UInt8(ascii: "c") && base[typeStart + 1] == UInt8(ascii: "l") {
                        continue
                    }

                    func getString(_ fIdx: Int) -> String {
                        guard fIdx < fieldCount else { return "" }
                        let len = fieldLengths[fIdx]
                        guard len > 0 else { return "" }
                        let ptr = base + fieldStarts[fIdx]
                        return String(decoding: UnsafeBufferPointer(start: ptr, count: len), as: UTF8.self).replacingOccurrences(of: "\"\"", with: "\"")
                    }

                    func getOptString(_ fIdx: Int) -> String? {
                        let s = getString(fIdx)
                        return s.isEmpty ? nil : s
                    }

                    let idStr = getString(0)
                    let latStr = getString(4)
                    let lonStr = getString(5)
                    guard let id = Int(idStr), let lat = Double(latStr), let lon = Double(lonStr) else {
                        continue
                    }

                    let ident = getString(1)
                    let typeRaw = getString(2)
                    let name = getString(3)
                    let elevation = Int(getString(6))
                    let continent = getString(7)
                    let isoCountry = getString(8)
                    let isoRegion = getString(9)
                    let municipality = getString(10)
                    let scheduled = getString(11).lowercased() == "yes"
                    let icao = getOptString(12)
                    let iata = getOptString(13)
                    let gps = getOptString(14)
                    let local = getOptString(15)
                    let home = getOptString(16)
                    let wiki = getOptString(17)
                    let keywords = getOptString(18)

                    let airport = Airport(
                        id: id,
                        ident: ident,
                        type: AirportType(rawString: typeRaw),
                        name: name,
                        latitude: lat,
                        longitude: lon,
                        elevationFt: elevation,
                        continent: continent.isEmpty ? "NA" : continent,
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
                    all.append(airport)
                    if airport.isInternational {
                        intl.append(airport)
                    }
                }
            }
        }
        return (all, intl)
    }
}
