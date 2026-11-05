import Foundation

/// Structured specifications and aviation data for an aircraft type/model
public struct AircraftModelSpecs: Sendable, Identifiable {
    public var id: String { icaoType ?? modelName }
    public let icaoType: String?
    public let modelName: String
    public let manufacturer: String
    public let engines: String
    public let wingspan: String
    public let maxSeating: String
    public let mtow: String // Max Takeoff Weight
    public let range: String
    public let maxSpeed: String
    public let cruiseSpeed: String?
    public let ceiling: String?
    public let dimensions: String?
    public let variants: [String]
    public let productionYears: String
    public let dataSource: String
}

/// Flexible JSON property wrapper that accepts strings, numbers, or nil without failing
public struct FlexibleString: Codable, Sendable {
    public let value: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = nil
        } else if let str = try? container.decode(String.self) {
            self.value = str
        } else if let intVal = try? container.decode(Int.self) {
            self.value = String(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = String(doubleVal)
        } else {
            self.value = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public init(_ value: String?) {
        self.value = value
    }
}

/// Raw record returned by https://api.api-ninjas.com/v1/aircraft
public struct ApiNinjasAircraftRecord: Codable, Sendable {
    public let manufacturer: String?
    public let model: String?
    public let engineType: String?
    public let engineCount: Int?
    public let engineThrustLbf: FlexibleString?
    public let engineThrustLbFt: FlexibleString?
    public let engineHorsepower: FlexibleString?
    public let maxSpeedKnots: FlexibleString?
    public let cruiseSpeedKnots: FlexibleString?
    public let stallKnots: FlexibleString?
    public let ceilingFt: FlexibleString?
    public let rateOfClimbFtPerMin: FlexibleString?
    public let grossWeightLbs: FlexibleString?
    public let emptyWeightLbs: FlexibleString?
    public let lengthFt: FlexibleString?
    public let heightFt: FlexibleString?
    public let wingSpanFt: FlexibleString?
    public let rangeNauticalMiles: FlexibleString?
    public let icaoType: String?
    public let aircraftClass: String?
    public let faaWeightClass: String?
    public let icaoWakeCategory: String?

    enum CodingKeys: String, CodingKey {
        case manufacturer
        case model
        case engineType = "engine_type"
        case engineCount = "engine_count"
        case engineThrustLbf = "engine_thrust_lbf"
        case engineThrustLbFt = "engine_thrust_lb_ft"
        case engineHorsepower = "engine_horsepower"
        case maxSpeedKnots = "max_speed_knots"
        case cruiseSpeedKnots = "cruise_speed_knots"
        case stallKnots = "stall_knots"
        case ceilingFt = "ceiling_ft"
        case rateOfClimbFtPerMin = "rate_of_climb_ft_per_min"
        case grossWeightLbs = "gross_weight_lbs"
        case emptyWeightLbs = "empty_weight_lbs"
        case lengthFt = "length_ft"
        case heightFt = "height_ft"
        case wingSpanFt = "wing_span_ft"
        case rangeNauticalMiles = "range_nautical_miles"
        case icaoType = "icao_type"
        case aircraftClass = "aircraft_class"
        case faaWeightClass = "faa_weight_class"
        case icaoWakeCategory = "icao_wake_category"
    }
}

/// Service managing API-Ninjas Aircraft API and built-in aviation specifications database
@MainActor
final class AircraftSpecsService {
    static let shared = AircraftSpecsService()

    private var specsCache: [String: AircraftModelSpecs] = [:]

    private init() {}

    /// Test an API-Ninjas API Key against the aircraft endpoint
    func testAPIKey(_ key: String) async -> (isValid: Bool, message: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (false, "Please enter an API-Ninjas key.")
        }

        guard let url = URL(string: "https://api.api-ninjas.com/v1/aircraft?icao=B738") else {
            return (false, "Invalid endpoint URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(trimmed, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return (false, "No network response.")
            }

            if http.statusCode == 200 {
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    return (true, "Verified! API-Ninjas Aircraft API is active (\(jsonArray.count) records found).")
                }
                return (true, "Verified! Connection to API-Ninjas Aircraft API succeeded.")
            } else if http.statusCode == 401 || http.statusCode == 403 {
                return (false, "Authentication failed (HTTP \(http.statusCode)). Please check your API key.")
            } else {
                return (false, "Server returned status code \(http.statusCode).")
            }
        } catch {
            return (false, "Connection error: \(error.localizedDescription)")
        }
    }

    /// Retrieve full specifications for an aircraft type from API-Ninjas or built-in database
    func fetchSpecs(
        icaoType: String?,
        modelQuery: String?,
        manufacturerQuery: String? = nil,
        apiKey: String
    ) async -> AircraftModelSpecs? {
        let cleanIcao = icaoType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanModel = modelQuery?.trimmingCharacters(in: .whitespacesAndNewlines)

        let cacheKey = "\(cleanIcao ?? "")_\(cleanModel ?? "")"
        if let cached = specsCache[cacheKey], !cacheKey.isEmpty {
            return cached
        }

        // 1. Try querying API-Ninjas if key is configured
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            if let apiRecord = await queryApiNinjas(icao: cleanIcao, model: cleanModel, manufacturer: manufacturerQuery, apiKey: trimmedKey) {
                let merged = buildMergedSpecs(from: apiRecord, fallbackIcao: cleanIcao, fallbackModel: cleanModel)
                if !cacheKey.isEmpty {
                    specsCache[cacheKey] = merged
                }
                return merged
            }
        }

        // 2. Fall back to the built-in comprehensive Aviation Database
        if let fallback = AircraftTypeDatabase.lookup(icao: cleanIcao, modelName: cleanModel) {
            if !cacheKey.isEmpty {
                specsCache[cacheKey] = fallback
            }
            return fallback
        }

        return nil
    }

    /// Query the API-Ninjas aircraft endpoint
    private func queryApiNinjas(
        icao: String?,
        model: String?,
        manufacturer: String?,
        apiKey: String
    ) async -> ApiNinjasAircraftRecord? {
        var queryItems: [URLQueryItem] = []

        if let icao = icao, !icao.isEmpty {
            queryItems.append(URLQueryItem(name: "icao", value: icao))
        } else if let model = model, !model.isEmpty {
            queryItems.append(URLQueryItem(name: "model", value: model))
        }

        if let manufacturer = manufacturer, !manufacturer.isEmpty {
            queryItems.append(URLQueryItem(name: "manufacturer", value: manufacturer))
        }

        guard !queryItems.isEmpty else { return nil }

        var components = URLComponents(string: "https://api.api-ninjas.com/v1/aircraft")
        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.timeoutInterval = 7.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            let records = try JSONDecoder().decode([ApiNinjasAircraftRecord].self, from: data)
            return records.first
        } catch {
            return nil
        }
    }

    /// Merge API-Ninjas live data with curated database for seating, variants, and timelines
    private func buildMergedSpecs(
        from record: ApiNinjasAircraftRecord,
        fallbackIcao: String?,
        fallbackModel: String?
    ) -> AircraftModelSpecs {
        let icao = record.icaoType ?? fallbackIcao
        let dbMatch = AircraftTypeDatabase.lookup(icao: icao, modelName: record.model ?? fallbackModel)

        let manufacturer = record.manufacturer ?? dbMatch?.manufacturer ?? "Aviation"
        let model = record.model ?? dbMatch?.modelName ?? fallbackModel ?? "Aircraft"

        // Engines
        let engineCount = record.engineCount ?? 2
        let engineType = record.engineType ?? "Turbofan"
        let engineThrust = record.engineThrustLbf?.value
        let enginesDesc: String
        if let thrust = engineThrust, !thrust.isEmpty, let numThrust = Double(thrust) {
            enginesDesc = "\(engineCount)× \(engineType) (\(Int(numThrust).formatted()) lbf thrust each)"
        } else if let dbEngines = dbMatch?.engines {
            enginesDesc = dbEngines
        } else {
            enginesDesc = "\(engineCount)× \(engineType)"
        }

        // Wingspan
        let wingspanDesc: String
        if let span = record.wingSpanFt?.value, let spanNum = Double(span), spanNum > 0 {
            let meters = spanNum * 0.3048
            wingspanDesc = String(format: "%.1f ft (%.1f m)", spanNum, meters)
        } else if let dbSpan = dbMatch?.wingspan {
            wingspanDesc = dbSpan
        } else {
            wingspanDesc = "Standard Class"
        }

        // MTOW
        let mtowDesc: String
        if let gross = record.grossWeightLbs?.value, let grossNum = Double(gross), grossNum > 0 {
            let kg = grossNum * 0.453592
            mtowDesc = "\(Int(grossNum).formatted()) lbs (\(Int(kg).formatted()) kg)"
        } else if let dbMtow = dbMatch?.mtow {
            mtowDesc = dbMtow
        } else {
            mtowDesc = "N/A"
        }

        // Range
        let rangeDesc: String
        if let rng = record.rangeNauticalMiles?.value, let rngNum = Double(rng), rngNum > 0 {
            let miles = rngNum * 1.15078
            let km = rngNum * 1.852
            rangeDesc = "\(Int(rngNum).formatted()) NM (\(Int(miles).formatted()) mi / \(Int(km).formatted()) km)"
        } else if let dbRange = dbMatch?.range {
            rangeDesc = dbRange
        } else {
            rangeDesc = "N/A"
        }

        // Max Speed
        let maxSpeedDesc: String
        if let spd = record.maxSpeedKnots?.value, let spdNum = Double(spd), spdNum > 0 {
            let mph = spdNum * 1.15078
            maxSpeedDesc = "\(Int(spdNum)) kts (\(Int(mph)) mph)"
        } else if let dbSpeed = dbMatch?.maxSpeed {
            maxSpeedDesc = dbSpeed
        } else {
            maxSpeedDesc = "Subsonic"
        }

        // Cruise Speed
        let cruiseSpeedDesc: String?
        if let crz = record.cruiseSpeedKnots?.value, let crzNum = Double(crz), crzNum > 0 {
            cruiseSpeedDesc = "\(Int(crzNum)) kts (\(Int(crzNum * 1.15078)) mph)"
        } else {
            cruiseSpeedDesc = dbMatch?.cruiseSpeed
        }

        // Ceiling
        let ceilingDesc: String?
        if let ceil = record.ceilingFt?.value, let ceilNum = Double(ceil), ceilNum > 0 {
            ceilingDesc = "\(Int(ceilNum).formatted()) ft"
        } else {
            ceilingDesc = dbMatch?.ceiling
        }

        // Dimensions
        let dimensionsDesc: String?
        if let len = record.lengthFt?.value, let hgt = record.heightFt?.value,
           let l = Double(len), let h = Double(hgt), l > 0 {
            dimensionsDesc = String(format: "%.1f ft length × %.1f ft height", l, h)
        } else {
            dimensionsDesc = dbMatch?.dimensions
        }

        return AircraftModelSpecs(
            icaoType: icao,
            modelName: model,
            manufacturer: manufacturer,
            engines: enginesDesc,
            wingspan: wingspanDesc,
            maxSeating: dbMatch?.maxSeating ?? "Typical Airline Configuration",
            mtow: mtowDesc,
            range: rangeDesc,
            maxSpeed: maxSpeedDesc,
            cruiseSpeed: cruiseSpeedDesc,
            ceiling: ceilingDesc,
            dimensions: dimensionsDesc,
            variants: dbMatch?.variants ?? [model],
            productionYears: dbMatch?.productionYears ?? "Modern Production",
            dataSource: "API-Ninjas Aircraft API"
        )
    }
}

// MARK: - Curated Aviation Database for Models, Seating, Variants & Timelines

struct AircraftTypeDatabase {
    static func lookup(icao: String?, modelName: String?) -> AircraftModelSpecs? {
        let code = icao?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = modelName?.lowercased() ?? ""

        // Boeing 737 Next Generation (-800)
        if code == "B738" || (code.hasPrefix("B73") && model.contains("800")) {
            return AircraftModelSpecs(
                icaoType: "B738",
                modelName: "Boeing 737-800 Next Gen",
                manufacturer: "Boeing",
                engines: "2× CFM56-7B26 Turbofan (27,300 lbf each)",
                wingspan: "117 ft 5 in (35.8 m) with winglets",
                maxSeating: "162 – 189 passengers (Typical 175)",
                mtow: "174,200 lbs (79,015 kg)",
                range: "2,935 NM (3,377 mi / 5,436 km)",
                maxSpeed: "473 kts (544 mph / Mach 0.82)",
                cruiseSpeed: "453 kts (521 mph / Mach 0.789)",
                ceiling: "41,000 ft",
                dimensions: "129 ft 6 in length × 41 ft 2 in height",
                variants: ["737-600", "737-700", "737-800", "737-900", "737-900ER", "MAX 7", "MAX 8", "MAX 9", "MAX 10"],
                productionYears: "1997 – 2020 (Next Generation)",
                dataSource: "Aviation Specs Database"
            )
        }

        // Boeing 737 Next Generation (-900 / -900ER)
        if code == "B739" || (code.hasPrefix("B73") && model.contains("900")) {
            return AircraftModelSpecs(
                icaoType: "B739",
                modelName: "Boeing 737-900 / 737-900ER",
                manufacturer: "Boeing",
                engines: "2× CFM56-7B27 Turbofan (27,300 lbf each)",
                wingspan: "117 ft 5 in (35.8 m) with winglets",
                maxSeating: "180 – 220 passengers (Max 220)",
                mtow: "187,700 lbs (85,139 kg)",
                range: "2,950 NM (3,395 mi / 5,463 km)",
                maxSpeed: "473 kts (544 mph / Mach 0.82)",
                cruiseSpeed: "453 kts (521 mph / Mach 0.789)",
                ceiling: "41,000 ft",
                dimensions: "138 ft 2 in length × 41 ft 2 in height",
                variants: ["737-600", "737-700", "737-800", "737-900", "737-900ER", "MAX 8", "MAX 9", "MAX 10"],
                productionYears: "2000 – 2019 (Next Generation)",
                dataSource: "Aviation Specs Database"
            )
        }

        // Boeing 737 Next Generation (-700)
        if code == "B737" || (code.hasPrefix("B73") && model.contains("700")) {
            return AircraftModelSpecs(
                icaoType: "B737",
                modelName: "Boeing 737-700 Next Gen",
                manufacturer: "Boeing",
                engines: "2× CFM56-7B24 Turbofan (24,200 lbf each)",
                wingspan: "117 ft 5 in (35.8 m)",
                maxSeating: "128 – 149 passengers",
                mtow: "154,500 lbs (70,080 kg)",
                range: "3,010 NM (3,464 mi / 5,575 km)",
                maxSpeed: "473 kts (544 mph / Mach 0.82)",
                cruiseSpeed: "453 kts (Mach 0.789)",
                ceiling: "41,000 ft",
                dimensions: "110 ft 4 in length × 41 ft 2 in height",
                variants: ["737-600", "737-700", "737-700ER", "737-800", "737-900ER", "MAX 7", "MAX 8"],
                productionYears: "1996 – 2019",
                dataSource: "Aviation Specs Database"
            )
        }

        // Boeing 737 MAX 8
        if code == "B38M" || model.contains("max 8") || model.contains("max-8") {
            return AircraftModelSpecs(
                icaoType: "B38M",
                modelName: "Boeing 737 MAX 8",
                manufacturer: "Boeing",
                engines: "2× CFM LEAP-1B Turbofan (29,300 lbf each)",
                wingspan: "117 ft 10 in (35.9 m) with AT winglets",
                maxSeating: "178 – 210 passengers (Max 210 in 8-200)",
                mtow: "182,200 lbs (82,644 kg)",
                range: "3,500 NM (4,028 mi / 6,482 km)",
                maxSpeed: "473 kts (544 mph / Mach 0.82)",
                cruiseSpeed: "453 kts (Mach 0.79)",
                ceiling: "41,000 ft",
                dimensions: "129 ft 8 in length × 40 ft 4 in height",
                variants: ["MAX 7", "MAX 8", "MAX 8-200", "MAX 9", "MAX 10"],
                productionYears: "2015 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Boeing 737 MAX 9
        if code == "B39M" || model.contains("max 9") || model.contains("max-9") {
            return AircraftModelSpecs(
                icaoType: "B39M",
                modelName: "Boeing 737 MAX 9",
                manufacturer: "Boeing",
                engines: "2× CFM LEAP-1B Turbofan (29,300 lbf each)",
                wingspan: "117 ft 10 in (35.9 m)",
                maxSeating: "193 – 220 passengers",
                mtow: "194,700 lbs (88,314 kg)",
                range: "3,300 NM (3,800 mi / 6,110 km)",
                maxSpeed: "473 kts (Mach 0.82)",
                cruiseSpeed: "453 kts (Mach 0.79)",
                ceiling: "41,000 ft",
                dimensions: "138 ft 4 in length × 40 ft 4 in height",
                variants: ["MAX 7", "MAX 8", "MAX 9", "MAX 10"],
                productionYears: "2016 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Airbus A320
        if code == "A320" || model.contains("a320-200") || (model.contains("a320") && !model.contains("neo")) {
            return AircraftModelSpecs(
                icaoType: "A320",
                modelName: "Airbus A320-200 ceo",
                manufacturer: "Airbus",
                engines: "2× CFM56-5B or IAE V2500 Turbofan (27,000 lbf each)",
                wingspan: "117 ft 5 in (35.8 m) with Sharklets",
                maxSeating: "150 – 180 passengers",
                mtow: "172,000 lbs (78,000 kg)",
                range: "3,300 NM (3,800 mi / 6,110 km)",
                maxSpeed: "470 kts (541 mph / Mach 0.82)",
                cruiseSpeed: "447 kts (Mach 0.78)",
                ceiling: "39,800 ft",
                dimensions: "123 ft 3 in length × 38 ft 7 in height",
                variants: ["A318", "A319ceo", "A320ceo", "A321ceo", "A320neo family"],
                productionYears: "1986 – 2021",
                dataSource: "Aviation Specs Database"
            )
        }

        // Airbus A320neo
        if code == "A20N" || (model.contains("a320") && model.contains("neo")) {
            return AircraftModelSpecs(
                icaoType: "A20N",
                modelName: "Airbus A320neo",
                manufacturer: "Airbus",
                engines: "2× CFM LEAP-1A or PW1100G Turbofan (27,120 lbf each)",
                wingspan: "117 ft 5 in (35.8 m)",
                maxSeating: "165 – 195 passengers (Max 195 with Space-Flex)",
                mtow: "174,000 lbs (79,000 kg)",
                range: "3,500 NM (4,030 mi / 6,480 km)",
                maxSpeed: "470 kts (Mach 0.82)",
                cruiseSpeed: "447 kts (Mach 0.78)",
                ceiling: "39,800 ft",
                dimensions: "123 ft 3 in length × 38 ft 7 in height",
                variants: ["A319neo", "A320neo", "A321neo", "A321LR", "A321XLR"],
                productionYears: "2014 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Airbus A321
        if code == "A321" || (model.contains("a321") && !model.contains("neo")) {
            return AircraftModelSpecs(
                icaoType: "A321",
                modelName: "Airbus A321-200 ceo",
                manufacturer: "Airbus",
                engines: "2× CFM56-5B or IAE V2500 Turbofan (33,000 lbf each)",
                wingspan: "117 ft 5 in (35.8 m)",
                maxSeating: "185 – 220 passengers",
                mtow: "206,000 lbs (93,500 kg)",
                range: "3,200 NM (3,680 mi / 5,930 km)",
                maxSpeed: "473 kts (Mach 0.82)",
                cruiseSpeed: "447 kts (Mach 0.78)",
                ceiling: "39,800 ft",
                dimensions: "146 ft length × 38 ft 7 in height",
                variants: ["A318", "A319", "A320", "A321", "A321neo"],
                productionYears: "1993 – 2021",
                dataSource: "Aviation Specs Database"
            )
        }

        // Airbus A321neo
        if code == "A21N" || (model.contains("a321") && model.contains("neo")) {
            return AircraftModelSpecs(
                icaoType: "A21N",
                modelName: "Airbus A321neo / A321LR",
                manufacturer: "Airbus",
                engines: "2× CFM LEAP-1A or PW1100G Turbofan (33,110 lbf each)",
                wingspan: "117 ft 5 in (35.8 m)",
                maxSeating: "206 – 244 passengers (Max 244 Cabin Flex)",
                mtow: "213,800 lbs (97,000 kg)",
                range: "4,000 NM (4,600 mi / 7,400 km) [4,700 NM on XLR]",
                maxSpeed: "473 kts (Mach 0.82)",
                cruiseSpeed: "447 kts (Mach 0.78)",
                ceiling: "39,800 ft",
                dimensions: "146 ft length × 38 ft 7 in height",
                variants: ["A321neo", "A321LR", "A321XLR"],
                productionYears: "2016 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Boeing 777-300ER
        if code == "B77W" || model.contains("777-300er") {
            return AircraftModelSpecs(
                icaoType: "B77W",
                modelName: "Boeing 777-300ER",
                manufacturer: "Boeing",
                engines: "2× GE90-115B Turbofan (115,300 lbf each)",
                wingspan: "212 ft 7 in (64.8 m) with raked wingtips",
                maxSeating: "365 – 396 passengers (Max 550 all-economy)",
                mtow: "775,000 lbs (351,534 kg)",
                range: "7,370 NM (8,480 mi / 13,650 km)",
                maxSpeed: "510 kts (587 mph / Mach 0.89)",
                cruiseSpeed: "482 kts (Mach 0.84)",
                ceiling: "43,100 ft",
                dimensions: "242 ft 4 in length × 60 ft 8 in height",
                variants: ["777-200", "777-200ER", "777-200LR", "777-300", "777-300ER", "777F", "777-8", "777-9"],
                productionYears: "2004 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Boeing 787-9 Dreamliner
        if code == "B789" || model.contains("787-9") {
            return AircraftModelSpecs(
                icaoType: "B789",
                modelName: "Boeing 787-9 Dreamliner",
                manufacturer: "Boeing",
                engines: "2× GEnx-1B or Rolls-Royce Trent 1000 (76,000 lbf each)",
                wingspan: "197 ft 4 in (60.1 m)",
                maxSeating: "290 – 330 passengers (Max 420)",
                mtow: "560,000 lbs (254,011 kg)",
                range: "7,565 NM (8,705 mi / 14,010 km)",
                maxSpeed: "510 kts (Mach 0.89)",
                cruiseSpeed: "488 kts (Mach 0.85)",
                ceiling: "43,000 ft",
                dimensions: "206 ft 1 in length × 55 ft 10 in height",
                variants: ["787-8", "787-9", "787-10"],
                productionYears: "2013 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Airbus A350-900
        if code == "A359" || model.contains("a350-900") {
            return AircraftModelSpecs(
                icaoType: "A359",
                modelName: "Airbus A350-900 XWB",
                manufacturer: "Airbus",
                engines: "2× Rolls-Royce Trent XWB-84 Turbofan (84,200 lbf each)",
                wingspan: "212 ft 5 in (64.75 m)",
                maxSeating: "315 – 369 passengers (Max 440)",
                mtow: "617,000 lbs (280,000 kg)",
                range: "8,100 NM (9,320 mi / 15,000 km)",
                maxSpeed: "510 kts (Mach 0.89)",
                cruiseSpeed: "488 kts (Mach 0.85)",
                ceiling: "43,100 ft",
                dimensions: "219 ft 2 in length × 56 ft 1 in height",
                variants: ["A350-900", "A350-900ULR", "A350-1000", "A350F"],
                productionYears: "2014 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Boeing 747-400
        if code == "B744" || model.contains("747-400") {
            return AircraftModelSpecs(
                icaoType: "B744",
                modelName: "Boeing 747-400 Queen of the Skies",
                manufacturer: "Boeing",
                engines: "4× GE CF6-80C2 or PW4056 or RB211 (63,300 lbf each)",
                wingspan: "211 ft 5 in (64.4 m)",
                maxSeating: "416 – 524 passengers (Max 660 all-economy)",
                mtow: "875,000 lbs (396,890 kg)",
                range: "7,260 NM (8,350 mi / 13,450 km)",
                maxSpeed: "530 kts (Mach 0.855)",
                cruiseSpeed: "493 kts (Mach 0.80)",
                ceiling: "45,000 ft",
                dimensions: "231 ft 10 in length × 63 ft 8 in height",
                variants: ["747-100", "747-200", "747-300", "747-400", "747-400F", "747-8I", "747-8F"],
                productionYears: "1988 – 2009",
                dataSource: "Aviation Specs Database"
            )
        }

        // Embraer E175
        if code == "E175" || code == "E75L" || model.contains("e175") {
            return AircraftModelSpecs(
                icaoType: "E175",
                modelName: "Embraer E175",
                manufacturer: "Embraer",
                engines: "2× GE CF34-8E Turbofan (14,200 lbf each)",
                wingspan: "85 ft 4 in (26.0 m)",
                maxSeating: "76 – 88 passengers",
                mtow: "89,000 lbs (40,370 kg)",
                range: "2,200 NM (2,530 mi / 4,074 km)",
                maxSpeed: "470 kts (Mach 0.82)",
                cruiseSpeed: "447 kts (Mach 0.78)",
                ceiling: "41,000 ft",
                dimensions: "103 ft 11 in length × 32 ft 4 in height",
                variants: ["E170", "E175", "E190", "E195", "E175-E2"],
                productionYears: "2002 – Present",
                dataSource: "Aviation Specs Database"
            )
        }

        // Bombardier CRJ-900
        if code == "CRJ9" || code == "CRJX" || model.contains("crj-900") || model.contains("crj900") {
            return AircraftModelSpecs(
                icaoType: "CRJ9",
                modelName: "Bombardier CRJ-900",
                manufacturer: "Bombardier / Mitsubishi",
                engines: "2× GE CF34-8C5 Turbofan (14,510 lbf each)",
                wingspan: "81 ft 7 in (24.9 m)",
                maxSeating: "76 – 90 passengers",
                mtow: "84,500 lbs (38,330 kg)",
                range: "1,515 NM (1,743 mi / 2,805 km)",
                maxSpeed: "473 kts (Mach 0.82)",
                cruiseSpeed: "447 kts (Mach 0.78)",
                ceiling: "41,000 ft",
                dimensions: "118 ft 11 in length × 24 ft 7 in height",
                variants: ["CRJ100", "CRJ200", "CRJ700", "CRJ900", "CRJ1000"],
                productionYears: "2001 – 2020",
                dataSource: "Aviation Specs Database"
            )
        }

        // Cessna 172 Skyhawk
        if code == "C172" || model.contains("172") {
            return AircraftModelSpecs(
                icaoType: "C172",
                modelName: "Cessna 172 Skyhawk",
                manufacturer: "Textron Aviation (Cessna)",
                engines: "1× Lycoming IO-360-L2A Piston (180 hp)",
                wingspan: "36 ft 1 in (11.0 m)",
                maxSeating: "4 passengers (1 pilot + 3 passengers)",
                mtow: "2,550 lbs (1,157 kg)",
                range: "640 NM (736 mi / 1,185 km)",
                maxSpeed: "140 kts (161 mph)",
                cruiseSpeed: "124 kts (143 mph)",
                ceiling: "14,000 ft",
                dimensions: "27 ft 2 in length × 8 ft 11 in height",
                variants: ["172A through 172S", "172RG Cutlass"],
                productionYears: "1956 – Present (World's Most Produced Aircraft)",
                dataSource: "Aviation Specs Database"
            )
        }

        // Generic fallback for any aircraft code with manufacturer estimation
        if !code.isEmpty {
            let mfg = code.hasPrefix("B") ? "Boeing" : (code.hasPrefix("A") ? "Airbus" : (code.hasPrefix("E") ? "Embraer" : "Aviation"))
            return AircraftModelSpecs(
                icaoType: code,
                modelName: modelName ?? "\(mfg) \(code)",
                manufacturer: mfg,
                engines: "Dual Turbofan Powerplants",
                wingspan: "Commercial Airliner Class",
                maxSeating: "Commercial Configuration",
                mtow: "Standard Category Weight",
                range: "Commercial Airline Sector Range",
                maxSpeed: "Standard Cruise Airspeed",
                cruiseSpeed: "Subsonic Jet Cruise",
                ceiling: "Flight Level 350-410",
                dimensions: "Standard Airframe",
                variants: [code],
                productionYears: "Commercial Aviation Production",
                dataSource: "Aviation Specs Database"
            )
        }

        return nil
    }
}
