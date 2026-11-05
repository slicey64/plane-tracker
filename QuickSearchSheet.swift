import SwiftUI

/// Scope for searching flights
enum FlightSearchScope: String, CaseIterable, Identifiable {
    case all = "All"
    case callsign = "Callsign"
    case aircraftType = "Type"
    case airportRoute = "Airport"

    var id: String { rawValue }

    var placeholder: String {
        switch self {
        case .all:
            return "Search callsign, type, or airport code..."
        case .callsign:
            return "e.g. UAL2496, AAL100, DAL123..."
        case .aircraftType:
            return "e.g. B738, A321, C172, B77W..."
        case .airportRoute:
            return "e.g. ERI, ORD, JFK, LAX..."
        }
    }
}

/// Sheet allowing users to search live aircraft by callsign, airplane type, or arrival/destination airport
struct QuickSearchSheet: View {
    let aircraft: [LiveAircraft]
    let flightService: FlightTrackingService
    var onSelectAircraft: ((LiveAircraft) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedScope: FlightSearchScope = .all
    @State private var selectedAircraftForDetail: LiveAircraft?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scope picker
                Picker("Search By", selection: $selectedScope) {
                    ForEach(FlightSearchScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                if filteredAircraft.isEmpty {
                    emptyResultsView
                } else {
                    List {
                        Section {
                            ForEach(filteredAircraft) { plane in
                                FlightSearchRow(
                                    aircraft: plane,
                                    route: flightService.routes[plane.callsign?.uppercased() ?? ""]
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelectAircraft?(plane)
                                    dismiss()
                                }
                            }
                        } header: {
                            Text("Matching Aircraft (\(filteredAircraft.count) of \(aircraft.count) active)")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Flight Quick Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: selectedScope.placeholder)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredAircraft: [LiveAircraft] {
        let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return aircraft }

        return aircraft.filter { plane in
            let callsignMatch = plane.callsign?.uppercased().contains(clean) ?? false
            let regMatch = plane.registration?.uppercased().contains(clean) ?? false
            let hexMatch = plane.hex.uppercased().contains(clean)
            let typeMatch = plane.aircraftType?.uppercased().contains(clean) ?? false

            // Route check (origin / destination matching airport code)
            var routeMatch = false
            if let cs = plane.callsign?.uppercased(), let route = flightService.routes[cs] {
                if let origIata = route.originAirport?.iata?.uppercased(), origIata.contains(clean) { routeMatch = true }
                if let origIcao = route.originAirport?.icao?.uppercased(), origIcao.contains(clean) { routeMatch = true }
                if let destIata = route.destinationAirport?.iata?.uppercased(), destIata.contains(clean) { routeMatch = true }
                if let destIcao = route.destinationAirport?.icao?.uppercased(), destIcao.contains(clean) { routeMatch = true }
                if let sum = route.airportCodesIata?.uppercased(), sum.contains(clean) { routeMatch = true }
            }

            switch selectedScope {
            case .all:
                return callsignMatch || regMatch || hexMatch || typeMatch || routeMatch
            case .callsign:
                return callsignMatch || regMatch || hexMatch
            case .aircraftType:
                return typeMatch
            case .airportRoute:
                return routeMatch
            }
        }
    }

    private var emptyResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "airplane.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Aircraft Found")
                .font(.headline)

            if selectedScope == .airportRoute {
                Text("Tip: Search by airport 3-letter IATA (e.g. ERI, ORD) or 4-letter ICAO (e.g. KERI, KORD).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Try refining your search query or selecting a different search scope.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Row view for flight search item
struct FlightSearchRow: View {
    let aircraft: LiveAircraft
    let route: FlightRoute?

    var body: some View {
        HStack(spacing: 12) {
            Image("plane")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(aircraft.track ?? 0))
                .padding(6)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(aircraft.displayName)
                        .font(.headline)

                    if let type = aircraft.aircraftType {
                        Text(type)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if let route = route {
                    Text(route.summary)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }

                HStack(spacing: 6) {
                    Text(aircraft.formattedAltitude)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(aircraft.formattedSpeed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
