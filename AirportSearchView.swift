import SwiftUI

/// View allowing users to query airports from airports.csv and pin or view them on the map.
struct AirportSearchView: View {
    var service: AirportDataService
    var onSelectAirport: ((Airport) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedTypeFilter: AirportType? = nil
    @State private var selectedAirportForDetail: Airport?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category Filter Pills
                filterScrollView

                Divider()

                if service.isLoading {
                    loadingView
                } else {
                    airportListView
                }
            }
            .navigationTitle("Airports Directory")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search by code (ERI, JFK), city, or country")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedAirportForDetail) { airport in
                AirportDetailSheet(
                    airport: airport,
                    service: service,
                    onFocus: { focused in
                        onSelectAirport?(focused)
                        dismiss()
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    private var filterScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All Facilities", isSelected: selectedTypeFilter == nil) {
                    selectedTypeFilter = nil
                }

                FilterChip(
                    title: "Major Hubs",
                    systemImage: AirportType.largeAirport.systemImage,
                    isSelected: selectedTypeFilter == .largeAirport
                ) {
                    selectedTypeFilter = (selectedTypeFilter == .largeAirport) ? nil : .largeAirport
                }

                FilterChip(
                    title: "Medium / Regional",
                    systemImage: AirportType.mediumAirport.systemImage,
                    isSelected: selectedTypeFilter == .mediumAirport
                ) {
                    selectedTypeFilter = (selectedTypeFilter == .mediumAirport) ? nil : .mediumAirport
                }

                FilterChip(
                    title: "Small / General Aviation",
                    systemImage: AirportType.smallAirport.systemImage,
                    isSelected: selectedTypeFilter == .smallAirport
                ) {
                    selectedTypeFilter = (selectedTypeFilter == .smallAirport) ? nil : .smallAirport
                }

                FilterChip(
                    title: "Heliports",
                    systemImage: AirportType.heliport.systemImage,
                    isSelected: selectedTypeFilter == .heliport
                ) {
                    selectedTypeFilter = (selectedTypeFilter == .heliport) ? nil : .heliport
                }

                FilterChip(
                    title: "Seaplane Bases",
                    systemImage: AirportType.seaplaneBase.systemImage,
                    isSelected: selectedTypeFilter == .seaplaneBase
                ) {
                    selectedTypeFilter = (selectedTypeFilter == .seaplaneBase) ? nil : .seaplaneBase
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.3)
            Text("Indexing airports database...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Over 70,000 airports and facilities are being loaded")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var airportListView: some View {
        let results = filteredResults

        return List {
            Section {
                if results.isEmpty {
                    VStack(alignment: .center, spacing: 8) {
                        Text("No matching airports found")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Try searching by IATA code (e.g. ERI, LAX, LHR) or city name.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ForEach(results.prefix(100)) { airport in
                        AirportRow(
                            airport: airport,
                            isPinned: service.isPinned(airport),
                            onTogglePin: { service.togglePin(for: airport) },
                            onShowDetails: { selectedAirportForDetail = airport }
                        )
                    }

                    if results.count > 100 {
                        Text("Showing top 100 of \(results.count) matches. Refine your query to see more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } header: {
                if searchText.isEmpty {
                    Text("International Airports (\(results.count))")
                } else {
                    Text("Search Results (\(results.count))")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var filteredResults: [Airport] {
        service.queryAirports(text: searchText, typeFilter: selectedTypeFilter)
    }
}

/// Filter chip pill
struct FilterChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                }
                Text(title)
                    .font(.footnote)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Row component for airport listing
struct AirportRow: View {
    let airport: Airport
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: airport.type.systemImage)
                .font(.title3)
                .foregroundStyle(airport.type.tintColor)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(airport.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if let iata = airport.iataCode, !iata.isEmpty {
                        Text(iata)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 6) {
                    Text(airport.municipality.isEmpty ? airport.formattedRegion : "\(airport.municipality), \(airport.formattedRegion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(airport.type.displayName)
                        .font(.caption)
                        .foregroundStyle(airport.type.tintColor)
                }
            }

            Spacer()

            // Pin / Unpin button
            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isPinned ? .green : .blue)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onShowDetails()
        }
    }
}
