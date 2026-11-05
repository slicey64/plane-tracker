import SwiftUI
import CoreLocation

/// Sheet displaying detailed live aircraft information, FlightAware AeroAPI gate/age specs, airline banners & logos, JetPhotos image, and flight route
struct AircraftDetailSheet: View {
    @State var aircraft: LiveAircraft
    let route: FlightRoute?
    var flightService: FlightTrackingService?
    var onFocus: ((LiveAircraft) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var jetPhoto: JetPhoto?
    @State private var isLoadingPhoto: Bool = false

    // FlightAware AeroAPI State
    @State private var flightAwareDetails: FlightAwareFlightDetails?
    @State private var flightAwareSpecs: FlightAwareAircraftSpecs?
    @State private var flightAwareHistory: [FlightAwareHistoricalFlight] = []
    @State private var isLoadingFlightAware: Bool = false

    // Aircraft Model Specifications State (API-Ninjas & Aviation Database)
    @State private var aircraftSpecs: AircraftModelSpecs?
    @State private var isLoadingSpecs: Bool = false

    private var settings = AppSettings.shared

    // MARK: - Airline Media (Banners & Logos)

    private var airlineICAO: String? {
        AirlineMediaService.extractAirlineICAO(
            callsign: aircraft.callsign,
            airlineCode: route?.airlineCode,
            identIcao: flightAwareDetails?.identIcao
        )
    }

    private var airlineBanner: UIImage? {
        guard let icao = airlineICAO else { return nil }
        return AirlineMediaService.shared.banner(for: icao)
    }

    private var airlineLogo: UIImage? {
        guard let icao = airlineICAO else { return nil }
        return AirlineMediaService.shared.logo(for: icao)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Small Detent Summary: Callsign, route, and altitude/speed at a glance
                    atAGlanceHeader

                    // Aircraft Photo or Header Graphic with Airline Banner & Logo
                    photoHeaderCard

                    // Category 1: Flight Route & Schedule
                    routeCategory

                    // Category 2: FlightAware Gate & Terminal Information
                    if settings.isFlightAwareConfigured && settings.gateScheduleProvider == .flightAware {
                        gateAndTerminalCategory
                    }

                    // Category 3: Live Telemetry & Avionics
                    telemetryCategory

                    // Category 4: Aircraft Model Specifications & Technical Data (API-Ninjas)
                    modelSpecsCategory

                    // Category 5: Airframe, Age & In-Depth Specs
                    airframeCategory

                    // Category 5: Historical Flights & Recent Legs
                    if settings.isFlightAwareConfigured && settings.flightAwareEnableHistoricalFlights && !flightAwareHistory.isEmpty {
                        historicalFlightsCategory
                    }
                }
                .padding()
            }
            .navigationTitle(aircraft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadPhotoAndEnrichment()
            }
        }
    }

    // MARK: - Subviews

    /// At-a-glance header showing callsign, route, and altitude/speed in small sheet detent
    private var atAGlanceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(aircraft.displayName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        if let type = aircraft.aircraftType {
                            Text(type)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    if let route = route {
                        Text(route.summary)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    } else if let reg = aircraft.registration {
                        Text("Reg: \(reg)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let logo = airlineLogo {
                    Image(uiImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Altitude & Speed at a glance
            HStack(spacing: 10) {
                Label(aircraft.formattedAltitude, systemImage: "arrow.up.and.down")
                Text("•")
                    .foregroundStyle(.tertiary)
                Label(aircraft.formattedSpeed, systemImage: "gauge.with.needle")

                if let vrate = aircraft.verticalRate, abs(vrate) > 64 {
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text(vrate > 0 ? "Climbing" : "Descending")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Header card displaying airline banner, real JetPhotos image if available, airline logo, and flight tags
    private var photoHeaderCard: some View {
        VStack(spacing: 12) {
            // Airline Banner Header
            if let banner = airlineBanner {
                Image(uiImage: banner)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 52)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.separator), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            }

            if let photo = jetPhoto, let url = URL(string: photo.thumbnailURL ?? photo.imageURL) {
                VStack(spacing: 6) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                                    .frame(height: 180)
                                ProgressView()
                            }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .bottomTrailing) {
                                    if let photographer = photo.photographer {
                                        Text("© \(photographer) (JetPhotos)")
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                            .padding(6)
                                    }
                                }
                        case .failure:
                            fallbackGraphic
                        @unknown default:
                            fallbackGraphic
                        }
                    }

                    if let model = flightAwareSpecs?.fullModelDescription ?? photo.aircraftModel {
                        Text(model)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isLoadingPhoto {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 140)
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Looking up aircraft photo on JetPhotos...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                fallbackGraphic
            }

            // Callsign and Airline Brand Logo
            HStack(spacing: 12) {
                if let logo = airlineLogo {
                    Image(uiImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                }

                VStack(alignment: airlineLogo != nil ? .leading : .center, spacing: 2) {
                    Text(aircraft.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let airline = flightAwareSpecs?.registeredOwner ?? aircraft.airlineName ?? route?.airlineCode {
                        Text(airline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 6) {
                if let type = flightAwareSpecs?.typeIcao ?? aircraft.aircraftType {
                    Text(type)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color(.systemFill))
                        .clipShape(Capsule())
                }

                if let reg = flightAwareSpecs?.registration ?? aircraft.registration, reg != aircraft.displayName {
                    Text(reg)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }

                if let age = flightAwareSpecs?.ageFormatted {
                    Text(age.components(separatedBy: " (").first ?? age)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let onFocus = onFocus {
                Button {
                    onFocus(aircraft)
                    dismiss()
                } label: {
                    Label("Track On Map", systemImage: "location.fill")
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var fallbackGraphic: some View {
        Image("plane")
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(.blue)
            .frame(width: 54, height: 54)
            .rotationEffect(.degrees(aircraft.track ?? 0))
            .padding(14)
            .background(Color.blue.opacity(0.12))
            .clipShape(Circle())
    }

    private var routeCategory: some View {
        CategoryCard(title: "Flight Route", systemImage: "arrow.triangle.swap", color: .indigo) {
            if let route = route {
                if let orig = route.originAirport, let dest = route.destinationAirport {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(orig.displayCode)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(orig.location ?? orig.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(spacing: 4) {
                            if let logo = airlineLogo {
                                Image(uiImage: logo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(.separator), lineWidth: 0.5)
                                    )
                            } else {
                                Image(systemName: "airplane")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }

                            if let icao = airlineICAO {
                                Text(icao)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(dest.displayCode)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text(dest.location ?? dest.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)

                    Divider()
                }

                DetailRow(label: "Route Summary", value: route.summary, isHighlighted: true)

                if let num = flightAwareDetails?.identIata ?? route.flightNumber {
                    Divider()
                    DetailRow(label: "Flight Number", value: num)
                }

                if let airline = flightAwareSpecs?.registeredOwner ?? aircraft.airlineName ?? route.airlineCode {
                    Divider()
                    HStack {
                        Text("Airline / Operator")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let logo = airlineLogo {
                            Image(uiImage: logo)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(.separator), lineWidth: 0.5)
                                )
                        }
                        Text(airline)
                            .fontWeight(.medium)
                    }
                    .font(.subheadline)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No filed IFR route found for \(aircraft.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Aircraft may be flying VFR, or route data has not been filed with ATC.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Category 2: FlightAware Gate & Terminal Information
    private var gateAndTerminalCategory: some View {
        CategoryCard(title: "Gate & Airport Information", systemImage: "door.left.hand.open", color: .teal) {
            if isLoadingFlightAware {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Querying FlightAware AeroAPI...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let details = flightAwareDetails {
                // Origin Departure Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DEPARTURE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let status = details.status {
                            Text(status)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    HStack {
                        Text(details.originDisplay)
                            .font(.headline)
                        Spacer()
                        Text(gateString(terminal: details.originTerminal, gate: details.originGate))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    if let depTime = formatTime(details.actualOut ?? details.estimatedOut ?? details.scheduledOut) {
                        Text("Out: \(depTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Divider()

                // Destination Arrival Info
                VStack(alignment: .leading, spacing: 6) {
                    Text("ARRIVAL")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(details.destinationDisplay)
                            .font(.headline)
                        Spacer()
                        Text(gateString(terminal: details.destinationTerminal, gate: details.destinationGate))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    if let arrTime = formatTime(details.estimatedIn ?? details.scheduledIn) {
                        Text("Estimated In: \(arrTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let baggage = details.baggageClaim {
                        Text("Baggage Claim: \(baggage)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.teal)
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No FlightAware gate information available for this flight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private var telemetryCategory: some View {
        CategoryCard(title: "Live Telemetry", systemImage: "speedometer", color: .blue) {
            DetailRow(label: "Barometric Altitude", value: aircraft.formattedAltitude, isHighlighted: true)
            Divider()
            DetailRow(label: "Ground Speed", value: aircraft.formattedSpeed)
            Divider()
            DetailRow(label: "True Heading", value: aircraft.formattedHeading)
            Divider()
            DetailRow(label: "Vertical Speed", value: aircraft.formattedVerticalRate)
            Divider()
            DetailRow(label: "Coordinates", value: String(format: "%.4f, %.4f", aircraft.latitude, aircraft.longitude))
            if let seen = aircraft.seen {
                Divider()
                DetailRow(label: "Signal Freshness", value: "\(String(format: "%.1f", seen))s ago")
            }
        }
    }

    // MARK: - Category: Aircraft Model Specifications (API-Ninjas & Aviation Database)
    private var modelSpecsCategory: some View {
        CategoryCard(title: "Aircraft Model Specifications", systemImage: "airplane", color: .cyan) {
            if isLoadingSpecs {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Querying aircraft technical data...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let specs = aircraftSpecs {
                // Header Row with Model & ICAO Type
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(specs.modelName)
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(specs.manufacturer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let icao = specs.icaoType, !icao.isEmpty {
                        Text(icao)
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(.vertical, 2)

                Divider()

                DetailRow(label: "Engines", value: specs.engines, isHighlighted: true)
                Divider()
                DetailRow(label: "Wingspan", value: specs.wingspan)
                Divider()
                DetailRow(label: "Max Takeoff Weight (MTOW)", value: specs.mtow, isHighlighted: true)
                Divider()
                DetailRow(label: "Max Seating Capacity", value: specs.maxSeating)
                Divider()
                DetailRow(label: "Operational Range", value: specs.range)
                Divider()
                DetailRow(label: "Maximum Speed", value: specs.maxSpeed)

                if let cruise = specs.cruiseSpeed {
                    Divider()
                    DetailRow(label: "Cruise Speed", value: cruise)
                }

                if let ceiling = specs.ceiling {
                    Divider()
                    DetailRow(label: "Service Ceiling", value: ceiling)
                }

                if let dim = specs.dimensions {
                    Divider()
                    DetailRow(label: "Airframe Dimensions", value: dim)
                }

                Divider()
                DetailRow(label: "Production Timeline", value: specs.productionYears)

                // Other Variants in the family
                if !specs.variants.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Other Family Variants")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(specs.variants, id: \.self) { variant in
                                    Text(variant)
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color(.systemFill))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Data Source Badge
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.cyan)
                        .font(.caption2)
                    Text("Source: \(specs.dataSource)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 2)
            } else {
                Text("Aircraft model specifications unavailable for this airframe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private var airframeCategory: some View {
        CategoryCard(title: "Airframe & Aircraft Specs", systemImage: "antenna.radiowaves.left.and.right", color: .orange) {
            DetailRow(label: "ICAO 24-bit Address", value: aircraft.hex.uppercased(), isHighlighted: true)

            // Exact Model from FlightAware or ADS-B
            if let fullModel = flightAwareSpecs?.fullModelDescription {
                Divider()
                DetailRow(label: "Exact Model", value: fullModel, isHighlighted: true)
            }

            // Aircraft Age & Year Built
            if let age = flightAwareSpecs?.ageFormatted {
                Divider()
                DetailRow(label: "Aircraft Age", value: age, isHighlighted: true)
            }

            // Engines info
            if let engines = flightAwareSpecs?.enginesDescription {
                Divider()
                DetailRow(label: "Engines", value: engines)
            }

            if let reg = flightAwareSpecs?.registration ?? aircraft.registration {
                Divider()
                DetailRow(label: "Tail / Registration", value: reg)
            }

            if let manufacturer = flightAwareSpecs?.manufacturer ?? aircraft.manufacturer {
                Divider()
                DetailRow(label: "Manufacturer", value: manufacturer)
            }

            if let owner = flightAwareSpecs?.registeredOwner ?? aircraft.registeredOwner {
                Divider()
                DetailRow(label: "Registered Owner", value: owner)
            }

            if let sqk = aircraft.squawk {
                Divider()
                DetailRow(label: "Transponder Squawk", value: sqk)
            }

            if let cat = aircraft.category {
                Divider()
                DetailRow(label: "Emitter Category", value: cat)
            }
        }
    }

    /// Category 5: Historical Flights
    private var historicalFlightsCategory: some View {
        CategoryCard(title: "Recent Flight History", systemImage: "clock.arrow.circlepath", color: .purple) {
            ForEach(flightAwareHistory.prefix(5)) { leg in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leg.ident)
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Text("\(leg.origin ?? "???") → \(leg.destination ?? "???")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if let date = leg.date {
                            Text(date)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        if let status = leg.status {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)

                if leg.id != flightAwareHistory.prefix(5).last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: - Helpers

    private func gateString(terminal: String?, gate: String?) -> String {
        switch (terminal, gate) {
        case let (t?, g?):
            return "Term \(t) • Gate \(g)"
        case let (nil, g?):
            return "Gate \(g)"
        case let (t?, nil):
            return "Terminal \(t)"
        default:
            return "TBD"
        }
    }

    private func formatTime(_ isoString: String?) -> String? {
        guard let iso = isoString else { return nil }
        // Take HH:mm from ISO string
        if iso.count >= 16 {
            let startIndex = iso.index(iso.startIndex, offsetBy: 11)
            let endIndex = iso.index(iso.startIndex, offsetBy: 16)
            return "\(iso[startIndex..<endIndex]) UTC"
        }
        return iso
    }

    // MARK: - Actions

    private func loadPhotoAndEnrichment() async {
        guard let service = flightService else { return }

        // 1. Kick off JetPhotos immediately if registration is already known
        let initialReg = aircraft.registration
        if let reg = initialReg, !reg.isEmpty {
            isLoadingPhoto = true
            Task {
                let photo = await service.fetchPhoto(for: reg)
                if self.jetPhoto == nil {
                    self.jetPhoto = photo
                }
                self.isLoadingPhoto = false
            }
        }

        // 2. Kick off initial Specs lookup immediately from built-in aviation database
        isLoadingSpecs = true
        Task {
            let specs = await AircraftSpecsService.shared.fetchSpecs(
                icaoType: aircraft.aircraftType,
                modelQuery: nil,
                manufacturerQuery: aircraft.manufacturer,
                apiKey: settings.apiNinjasKey
            )
            if self.aircraftSpecs == nil {
                self.aircraftSpecs = specs
            }
            self.isLoadingSpecs = false
        }

        // 3. Query FlightAware AeroAPI concurrently if configured
        if settings.isFlightAwareConfigured {
            isLoadingFlightAware = true
            let queryIdent = aircraft.callsign ?? aircraft.registration ?? aircraft.hex

            async let detailsTask: (FlightAwareFlightDetails?, [FlightAwareHistoricalFlight]) = {
                if settings.gateScheduleProvider == .flightAware && settings.flightAwareEnableGatesAndSchedule {
                    return await FlightAwareService.shared.fetchFlightDetails(ident: queryIdent, apiKey: settings.flightAwareAPIKey)
                }
                return (nil, [])
            }()

            async let specsTask: FlightAwareAircraftSpecs? = {
                if settings.aircraftSpecsProvider == .flightAware && settings.flightAwareEnableAircraftSpecs {
                    let specsIdent = aircraft.registration ?? queryIdent
                    return await FlightAwareService.shared.fetchAircraftSpecs(ident: specsIdent, apiKey: settings.flightAwareAPIKey)
                }
                return nil
            }()

            let (active, history) = await detailsTask
            let faSpecs = await specsTask

            self.flightAwareDetails = active
            if settings.flightAwareEnableHistoricalFlights {
                self.flightAwareHistory = history
            }
            self.flightAwareSpecs = faSpecs
            self.isLoadingFlightAware = false
        }

        // 4. Open-data backup enrichment via adsbdb (cached)
        let enriched = await service.enrichAircraft(aircraft)
        self.aircraft = enriched

        // 5. If photo was not yet resolved, query with enriched registration
        if self.jetPhoto == nil, let reg = flightAwareSpecs?.registration ?? enriched.registration, !reg.isEmpty {
            isLoadingPhoto = true
            self.jetPhoto = await service.fetchPhoto(for: reg)
            isLoadingPhoto = false
        }

        // 6. Refine specs with enriched model description
        let finalIcao = flightAwareSpecs?.typeIcao ?? enriched.aircraftType
        let finalModel = flightAwareSpecs?.fullModelDescription ?? jetPhoto?.aircraftModel
        if finalModel != nil || self.aircraftSpecs == nil {
            let refined = await AircraftSpecsService.shared.fetchSpecs(
                icaoType: finalIcao,
                modelQuery: finalModel,
                manufacturerQuery: flightAwareSpecs?.manufacturer ?? enriched.manufacturer,
                apiKey: settings.apiNinjasKey
            )
            if let refined = refined {
                self.aircraftSpecs = refined
            }
        }
    }
}

#Preview {
    AircraftDetailSheet(
        aircraft: LiveAircraft(
            hex: "a01234",
            callsign: "DAL1824",
            registration: "N123DN",
            aircraftType: "B738",
            latitude: 42.1,
            longitude: -80.2,
            altitudeBaro: 33000,
            groundSpeed: 465,
            track: 92
        ),
        route: nil,
        flightService: FlightTrackingService()
    )
}
