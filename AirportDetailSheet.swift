import SwiftUI
import CoreLocation

/// Sheet displaying airport data organized into clean, easy-to-read categories.
struct AirportDetailSheet: View {
    let airport: Airport
    var service: AirportDataService
    var onFocus: ((Airport) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card
                    headerCard

                    // Quick Actions
                    actionButtons

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
            Button {
                service.togglePin(for: airport)
            } label: {
                Label(
                    service.isPinned(airport) ? "Remove Pin" : "Pin to Map",
                    systemImage: service.isPinned(airport) ? "mappin.slash" : "mappin.and.ellipse"
                )
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(service.isPinned(airport) ? .red : .blue)

            if let onFocus = onFocus {
                Button {
                    onFocus(airport)
                    dismiss()
                } label: {
                    Label("Focus Map", systemImage: "location.fill")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var identifiersCategory: some View {
        CategoryCard(title: "Identification & Codes", systemImage: "number.square.fill", color: .blue) {
            DetailRow(label: "IATA Code", value: airport.iataCode ?? "N/A", isHighlighted: airport.iataCode != nil)
            Divider()
            DetailRow(label: "ICAO Code", value: airport.icaoCode ?? "N/A")
            Divider()
            DetailRow(label: "Local / FAA Code", value: airport.localCode ?? "N/A")
            Divider()
            DetailRow(label: "Airport Ident", value: airport.ident)
            Divider()
            DetailRow(label: "Database ID", value: "\(airport.id)")
        }
    }

    private var classificationCategory: some View {
        CategoryCard(title: "Facility Classification", systemImage: "tag.fill", color: airport.type.tintColor) {
            DetailRow(label: "Facility Type", value: airport.type.displayName)
            Divider()
            DetailRow(
                label: "Scheduled Service",
                value: airport.scheduledService ? "Yes (Commercial)" : "No (General / Private)"
            )
        }
    }

    private var locationCategory: some View {
        CategoryCard(title: "Geographic Location", systemImage: "map.fill", color: .green) {
            DetailRow(label: "City / Municipality", value: airport.municipality.isEmpty ? "Unincorporated" : airport.municipality)
            Divider()
            DetailRow(label: "Region / State", value: airport.formattedRegion)
            Divider()
            DetailRow(label: "Coordinates", value: airport.formattedCoordinates)
            Divider()
            DetailRow(label: "Latitude", value: String(format: "%.6f", airport.latitude))
            Divider()
            DetailRow(label: "Longitude", value: String(format: "%.6f", airport.longitude))
            Divider()
            DetailRow(label: "Field Elevation", value: airport.formattedElevation)
        }
    }

    private var resourcesCategory: some View {
        CategoryCard(title: "Web Resources", systemImage: "safari.fill", color: .purple) {
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
