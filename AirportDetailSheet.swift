import SwiftUI
import CoreLocation

struct AirportDetailSheet: View {
    let airport: Airport
    var service: AirportDataService
    var onFocus: ((Airport) -> Void)?
    @Environment(\.dismiss) private var dismiss

    // FlightAware Airport Boards State
    @State private var airportBoards: FlightAwareAirportBoards?
    @State private var selectedBoardTab: AirportBoardTab = .departures
    @State private var isLoadingBoards: Bool = false

    enum AirportBoardTab: String, CaseIterable, Identifiable {
        case departures = "Departures"
        case arrivals = "Arrivals"
        var id: String { rawValue }
    }

    private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card
                    headerCard

                    // Quick Actions
                    actionButtons

                    // Category: FlightAware Live Flight Boards (Gates & Schedules)
                    if settings.isFlightAwareConfigured &&
                       settings.airportBoardProvider == .flightAware &&
                       settings.flightAwareEnableAirportBoards {
                        flightBoardsCategory
                    }

                    // Category 1: Codes & Identifiers
                    identifiersCategory

                    // Category 2: Facility Classification
                    classificationCategory

                    // Category 3: Geographic & Navigation Info
                    locationCategory

                    // Category 4: Web Resources
                    if airport.wikipediaLink != nil || airport.homeLink != nil {
                        resourcesCategory
                    }
                }
                .padding()
            }
            .navigationTitle(airport.displayCode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFlightBoards()
            }
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(spacing: 8) {
            Image(systemName: airport.type.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(airport.type.tintColor)
                .padding(12)
                .background(airport.type.tintColor.opacity(0.15))
                .clipShape(Circle())

            Text(airport.name)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            if !airport.municipality.isEmpty {
                Text("\(airport.municipality), \(airport.formattedRegion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let onFocus = onFocus {
                Button {
                    onFocus(airport)
                    dismiss()
                } label: {
                    Label("Show On Map", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if let url = airport.mapsURL {
                Link(destination: url) {
                    Label("Apple Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    /// FlightAware Live Airport Flight Boards Category (Gates, Flights, Delays)
    private var flightBoardsCategory: some View {
        CategoryCard(title: "Live Airport Flight Boards", systemImage: "airplane.departure", color: .teal) {
            VStack(spacing: 10) {
                Picker("Board", selection: $selectedBoardTab) {
                    ForEach(AirportBoardTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if isLoadingBoards {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("Querying FlightAware flight boards...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                } else if let boards = airportBoards {
                    let flights = selectedBoardTab == .departures ? boards.departures : boards.arrivals
                    if flights.isEmpty {
                        Text("No scheduled \(selectedBoardTab.rawValue.lowercased()) found right now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(flights.prefix(8)) { fl in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(fl.ident)
                                            .font(.subheadline)
                                            .fontWeight(.bold)

                                        if let type = fl.aircraftType {
                                            Text(type)
                                                .font(.caption2)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color(.systemFill))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }

                                    Text(fl.airportCode ?? fl.airportName ?? "Unknown")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    if let gate = fl.gate {
                                        Text("Gate \(gate)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.primary)
                                    }

                                    if let time = formatBoardTime(fl.scheduledTime) {
                                        Text(time)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let status = fl.status {
                                        Text(status)
                                            .font(.caption2)
                                            .foregroundStyle(.teal)
                                    }
                                }
                            }
                            .padding(.vertical, 2)

                            if fl.id != flights.prefix(8).last?.id {
                                Divider()
                            }
                        }
                    }
                } else {
                    Text("Flight boards not loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var identifiersCategory: some View {
        CategoryCard(title: "Codes & Identifiers", systemImage: "barcode", color: .blue) {
            DetailRow(label: "ICAO / Ident Code", value: airport.ident, isHighlighted: true)
            if let iata = airport.iataCode, !iata.isEmpty {
                Divider()
                DetailRow(label: "IATA Code", value: iata, isHighlighted: true)
            }
            if let gps = airport.gpsCode, !gps.isEmpty {
                Divider()
                DetailRow(label: "GPS Code", value: gps)
            }
            if let local = airport.localCode, !local.isEmpty {
                Divider()
                DetailRow(label: "Local Code", value: local)
            }
        }
    }

    private var classificationCategory: some View {
        CategoryCard(title: "Facility Classification", systemImage: "building.2", color: .purple) {
            DetailRow(label: "Airport Category", value: airport.type.rawValue, isHighlighted: true)
            Divider()
            DetailRow(label: "Scheduled Commercial Service", value: airport.scheduledService ? "Yes" : "No")
        }
    }

    private var locationCategory: some View {
        CategoryCard(title: "Geographic & Navigation", systemImage: "location", color: .green) {
            DetailRow(label: "Latitude", value: String(format: "%.6f°", airport.latitude))
            Divider()
            DetailRow(label: "Longitude", value: String(format: "%.6f°", airport.longitude))
            Divider()
            DetailRow(label: "Elevation", value: airport.formattedElevation)
            if !airport.continent.isEmpty {
                Divider()
                DetailRow(label: "Continent", value: airport.continent)
            }
            Divider()
            DetailRow(label: "Country", value: airport.isoCountry)
            Divider()
            DetailRow(label: "Region / State", value: airport.formattedRegion)
        }
    }

    private var resourcesCategory: some View {
        CategoryCard(title: "Web Resources", systemImage: "link", color: .orange) {
            if let wiki = airport.wikipediaLink, let url = URL(string: wiki) {
                Link(destination: url) {
                    HStack {
                        Label("Wikipedia Article", systemImage: "arrow.up.right.square")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if airport.wikipediaLink != nil && airport.homeLink != nil {
                Divider()
            }

            if let home = airport.homeLink, let url = URL(string: home) {
                Link(destination: url) {
                    HStack {
                        Label("Official Website", systemImage: "globe")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatBoardTime(_ iso: String?) -> String? {
        guard let s = iso, s.count >= 16 else { return iso }
        let startIndex = s.index(s.startIndex, offsetBy: 11)
        let endIndex = s.index(s.startIndex, offsetBy: 16)
        return "\(s[startIndex..<endIndex]) UTC"
    }

    private func loadFlightBoards() async {
        guard settings.isFlightAwareConfigured &&
              settings.airportBoardProvider == .flightAware &&
              settings.flightAwareEnableAirportBoards else {
            return
        }

        let code = airport.ident.isEmpty ? (airport.iataCode ?? "") : airport.ident
        guard !code.isEmpty else { return }

        isLoadingBoards = true
        airportBoards = await FlightAwareService.shared.fetchAirportBoards(airportCode: code, apiKey: settings.flightAwareAPIKey)
        isLoadingBoards = false
    }
}

/// Reusable card container for organized data categories
struct CategoryCard<Content: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .font(.headline)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 4)

            VStack(spacing: 8) {
                content
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Reusable label/value row for categorized details
struct DetailRow: View {
    let label: String
    let value: String
    var isHighlighted: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(isHighlighted ? .bold : .medium)
                .foregroundStyle(isHighlighted ? .primary : .secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
