import SwiftUI
import CoreLocation

/// Sheet displaying detailed live aircraft information, JetPhotos image, and flight route
struct AircraftDetailSheet: View {
    @State var aircraft: LiveAircraft
    let route: FlightRoute?
    var flightService: FlightTrackingService?
    var onFocus: ((LiveAircraft) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var jetPhoto: JetPhoto?
    @State private var isLoadingPhoto: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Aircraft Photo or Header Graphic
                    photoHeaderCard

                    // Category 1: Flight Route & Schedule
                    routeCategory

                    // Category 2: Live Telemetry & Avionics
                    telemetryCategory

                    // Category 3: Airframe, Owner & Transponder
                    airframeCategory
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

    /// Header card displaying real JetPhotos image if available, with fallback to rotated plane icon
    private var photoHeaderCard: some View {
        VStack(spacing: 12) {
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

                    if let model = photo.aircraftModel {
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

            Text(aircraft.displayName)
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 6) {
                if let type = aircraft.aircraftType {
                    Text(type)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color(.systemFill))
                        .clipShape(Capsule())
                }

                if let reg = aircraft.registration, reg != aircraft.displayName {
                    Text(reg)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill))
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

                        Image(systemName: "airplane")
                            .font(.title3)
                            .foregroundStyle(.blue)

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

                if let num = route.flightNumber {
                    Divider()
                    DetailRow(label: "Flight Number", value: num)
                }

                if let airline = aircraft.airlineName ?? route.airlineCode {
                    Divider()
                    DetailRow(label: "Airline / Operator", value: airline)
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

    private var airframeCategory: some View {
        CategoryCard(title: "Airframe & Registration", systemImage: "antenna.radiowaves.left.and.right", color: .orange) {
            DetailRow(label: "ICAO 24-bit Address", value: aircraft.hex.uppercased(), isHighlighted: true)

            if let reg = aircraft.registration {
                Divider()
                DetailRow(label: "Tail / Registration", value: reg)
            }

            if let manufacturer = aircraft.manufacturer {
                Divider()
                DetailRow(label: "Manufacturer", value: manufacturer)
            }

            if let owner = aircraft.registeredOwner {
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

    // MARK: - Actions

    private func loadPhotoAndEnrichment() async {
        guard let service = flightService else { return }

        // Enrich missing metadata from adsbdb
        let enriched = await service.enrichAircraft(aircraft)
        self.aircraft = enriched

        // Query JetPhotos via jetapi.dev using registration
        if let reg = aircraft.registration, !reg.isEmpty {
            isLoadingPhoto = true
            jetPhoto = await service.fetchPhoto(for: reg)
            isLoadingPhoto = false
        }
    }
}
