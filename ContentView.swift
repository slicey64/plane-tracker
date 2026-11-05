import SwiftUI
import MapKit
import os

/// Filter mode to toggle showing all airports, live planes, or both
enum MapDisplayMode: String, CaseIterable, Identifiable {
    case planesAndAirports = "All"
    case airportsOnly = "Airports"
    case planesOnly = "Planes"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .planesAndAirports:
            return "square.stack.3d.up.fill"
        case .airportsOnly:
            return "mappin.and.ellipse"
        case .planesOnly:
            return "airplane"
        }
    }
}

/// Zoom level categorization representing view scope
enum MapViewScope: String, CaseIterable, Sendable {
    case continentOrCountry = "National / Continental"
    case stateOrRegion = "State / Regional"
    case cityOrLocal = "City / Local"

    var badgeText: String {
        switch self {
        case .continentOrCountry:
            return "Major Hubs"
        case .stateOrRegion:
            return "Major & Regional"
        case .cityOrLocal:
            return "All Facilities"
        }
    }

    var iconName: String {
        switch self {
        case .continentOrCountry:
            return "globe.americas.fill"
        case .stateOrRegion:
            return "map.fill"
        case .cityOrLocal:
            return "building.2.crop.circle"
        }
    }
}

struct ContentView: View {
    @State private var airportService = AirportDataService()
    @State private var flightService = FlightTrackingService()
    @State private var settings = AppSettings.shared

    // Mode: show airports only, planes only, or both
    @State private var displayMode: MapDisplayMode = .planesAndAirports

    // Default coordinates: Erie, PA (Erie International Airport KERI)
    static let erieCoordinate = CLLocationCoordinate2D(
        latitude: 42.083127,
        longitude: -80.173867
    )

    // Programmatic camera target (recentering, search results, focusing)
    @State private var targetRegion: MKCoordinateRegion? = nil

    // Track the visible region from map camera changes
    @State private var visibleRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: erieCoordinate,
        span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
    )

    // Selection states
    @State private var selectedAirport: Airport?
    @State private var selectedAircraft: LiveAircraft?

    private static let mapLogger = Logger(subsystem: "FlightTracker", category: "MapPerformance")

    private func logAnnotationCounts(airports: Int, aircraft: Int) {
        let total = airports + aircraft
        Self.mapLogger.info("[MapPerformance] Passing \(total) annotations to Map (\(airports) airports, \(aircraft) aircraft)")
        print("[MapPerformance] Passing \(total) annotations to Map (\(airports) airports, \(aircraft) aircraft)")
    }
    @State private var isShowingAirportSearch: Bool = false
    @State private var isShowingQuickSearch: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var isShowingUICustomization: Bool = false

    /// Determine current zoom scale based on latitudeDelta
    private var currentScope: MapViewScope {
        let delta = visibleRegion.span.latitudeDelta
        if delta > 12.0 {
            return .continentOrCountry
        } else if delta > 3.0 {
            return .stateOrRegion
        } else {
            return .cityOrLocal
        }
    }

    /// Dynamically filter visible airports based on zoom threshold and display mode
    private var displayedAirports: [Airport] {
        guard displayMode != .planesOnly else { return [] }

        let delta = visibleRegion.span.latitudeDelta
        let baseAirports = airportService.pinnedAirports

        // If user tapped "Airports" mode, show full list of airports
        if displayMode == .airportsOnly {
            return baseAirports
        }

        // When zoomed way out, show major hubs
        if delta > 12.0 {
            return baseAirports.filter { airport in
                if airport.id == selectedAirport?.id { return true }
                return airport.type == .largeAirport
            }
        }

        // Regional / state view: show major hubs + regional/medium airports
        if delta > 3.0 {
            var selected: [Airport] = []
            let gridCellSize = 0.5
            var clusterCounts: [String: Int] = [:]
            let prioritized = baseAirports.sorted { $0.type.rank > $1.type.rank }

            for airport in prioritized {
                if airport.id == selectedAirport?.id {
                    selected.append(airport)
                    continue
                }

                if airport.type.rank < 2 {
                    continue
                }

                let cellKey = "\(Int(airport.latitude / gridCellSize))_\(Int(airport.longitude / gridCellSize))"
                let currentCount = clusterCounts[cellKey, default: 0]

                if currentCount < 2 || airport.type == .largeAirport {
                    selected.append(airport)
                    clusterCounts[cellKey] = currentCount + 1
                }
            }
            return selected
        }

        // Local / city view: show all facilities
        return baseAirports
    }

    /// Visible aircraft filtered to visible region plus padding
    private var displayedAircraft: [LiveAircraft] {
        guard displayMode != .airportsOnly else { return [] }

        let center = visibleRegion.center
        let span = visibleRegion.span

        // Add 25% padding around the viewport edges to prevent pop-in during pans
        let latPad = max(span.latitudeDelta * 0.25, 0.05)
        let lonPad = max(span.longitudeDelta * 0.25, 0.05)

        let minLat = center.latitude - (span.latitudeDelta / 2.0) - latPad
        let maxLat = center.latitude + (span.latitudeDelta / 2.0) + latPad
        let minLon = center.longitude - (span.longitudeDelta / 2.0) - lonPad
        let maxLon = center.longitude + (span.longitudeDelta / 2.0) + lonPad

        let allPlanes = flightService.aircraft

        var filtered = allPlanes.filter { plane in
            plane.latitude >= minLat && plane.latitude <= maxLat &&
            plane.longitude >= minLon && plane.longitude <= maxLon
        }

        if let selected = selectedAircraft, !filtered.contains(where: { $0.hex == selected.hex }) {
            filtered.append(selected)
        }

        return filtered
    }

    /// Coordinate path for the currently highlighted aircraft:
    /// Origin Airport -> Current Aircraft Location -> Destination Airport
    private var activeFlightPathCoordinates: [CLLocationCoordinate2D] {
        guard let plane = selectedAircraft else { return [] }

        if let route = flightService.activeRoute {
            let orig = route.originAirport?.coordinate
            let dest = route.destinationAirport?.coordinate

            if let o = orig, let d = dest {
                return [o, plane.coordinate, d]
            } else if let o = orig {
                return [o, plane.coordinate]
            } else if let d = dest {
                return [plane.coordinate, d]
            }
        }
        return []
    }

    var body: some View {
        ZStack {
            // Full-screen Map with minimal chrome
            FlightMapView(
                aircraft: displayedAircraft,
                airports: displayedAirports,
                routeCoordinates: activeFlightPathCoordinates,
                showRouteLines: settings.showRouteLines,
                settings: settings,
                visibleRegion: $visibleRegion,
                targetRegion: $targetRegion,
                selectedAircraftHex: selectedAircraft?.hex,
                selectedAirportId: selectedAirport?.id,
                onSelectAircraft: { plane in
                    selectedAirport = nil
                    selectedAircraft = plane
                    Task {
                        if let callsign = plane.callsign {
                            _ = await flightService.fetchRoute(for: callsign)
                        }
                    }
                },
                onSelectAirport: { airport in
                    selectedAircraft = nil
                    flightService.clearActiveRoute()
                    selectedAirport = airport
                },
                onDeselect: {
                    selectedAircraft = nil
                    selectedAirport = nil
                    flightService.clearActiveRoute()
                }
            )
            .ignoresSafeArea()
            .task(id: "\(visibleRegion.center.latitude)_\(settings.selectedSource.rawValue)") {
                // Auto-refresh aircraft when camera settles or source changes
                if displayMode != .airportsOnly {
                    await refreshAircraft()
                }
            }

            // Floating Controls Overlay: Small circular buttons floating in corners
            cornerControlsOverlay
        }
        .sheet(isPresented: $isShowingAirportSearch) {
            AirportSearchView(service: airportService) { chosenAirport in
                selectedAircraft = nil
                flightService.clearActiveRoute()
                selectedAirport = chosenAirport
                targetRegion = MKCoordinateRegion(
                    center: chosenAirport.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
                )
            }
        }
        .sheet(isPresented: $isShowingQuickSearch) {
            QuickSearchSheet(aircraft: flightService.aircraft, flightService: flightService) { chosenPlane in
                selectedAirport = nil
                selectedAircraft = chosenPlane
                targetRegion = MKCoordinateRegion(
                    center: chosenPlane.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                )
                Task {
                    if let callsign = chosenPlane.callsign {
                        _ = await flightService.fetchRoute(for: callsign)
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsSheet(settings: settings)
        }
        .sheet(isPresented: $isShowingUICustomization) {
            UICustomizationSheet(settings: settings)
        }
        .sheet(item: $selectedAirport) { airport in
            AirportDetailSheet(
                airport: airport,
                service: airportService,
                onFocus: { focusedAirport in
                    selectedAircraft = nil
                    flightService.clearActiveRoute()
                    selectedAirport = focusedAirport
                    targetRegion = MKCoordinateRegion(
                        center: focusedAirport.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
                    )
                }
            )
            .presentationDetents([.fraction(0.24), .medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(item: $selectedAircraft) { plane in
            AircraftDetailSheet(
                aircraft: plane,
                route: flightService.activeRoute,
                flightService: flightService,
                onFocus: { focusedPlane in
                    selectedAirport = nil
                    selectedAircraft = focusedPlane
                    targetRegion = MKCoordinateRegion(
                        center: focusedPlane.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                    )
                }
            )
            .presentationDetents([.fraction(0.24), .medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    // MARK: - Subviews

    /// Floating Controls Overlay: Small circular buttons floating in corners + center filter pills
    private var cornerControlsOverlay: some View {
        VStack {
            // Top Row: Search (Leading) | Filter Pills (Center) | Layers & Settings (Trailing)
            HStack(alignment: .top) {
                // Top-leading: Search
                circularControl(systemImage: "magnifyingglass") {
                    isShowingQuickSearch = true
                }

                Spacer()

                // Center: Filter pills ("All", "Airports", "Planes") with safe-area breathing room
                filterPillsBar
                    .padding(.top, 4)

                Spacer()

                // Top-trailing: Map Layers & Settings
                VStack(spacing: 8) {
                    // Map Layers Menu
                    Menu {
                        Section("Display Mode") {
                            Button {
                                displayMode = .planesAndAirports
                            } label: {
                                Label("Show All", systemImage: "square.grid.2x2")
                            }
                            Button {
                                displayMode = .planesOnly
                                selectedAirport = nil
                            } label: {
                                Label("Planes Only", systemImage: "airplane")
                            }
                            Button {
                                displayMode = .airportsOnly
                                selectedAircraft = nil
                                flightService.clearActiveRoute()
                            } label: {
                                Label("Airports Only", systemImage: "airplane.circle")
                            }
                        }

                        Section("Map Style") {
                            Button {
                                settings.mapStyle = .standard
                            } label: {
                                Label("Standard", systemImage: "map")
                            }
                            Button {
                                settings.mapStyle = .imagery
                            } label: {
                                Label("Satellite", systemImage: "globe.americas")
                            }
                            Button {
                                settings.mapStyle = .hybrid
                            } label: {
                                Label("Hybrid", systemImage: "square.3.layers.3d")
                            }
                        }
                    } label: {
                        Image(systemName: "square.2.layers.3d")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                    }

                    // Settings & More Menu
                    Menu {
                        Button {
                            isShowingAirportSearch = true
                        } label: {
                            Label("Airports Directory", systemImage: "airplane.circle")
                        }

                        Divider()

                        Button {
                            isShowingUICustomization = true
                        } label: {
                            Label("UI Customization", systemImage: "paintpalette")
                        }

                        Button {
                            isShowingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()

            // Bottom-trailing: Refresh & Locate
            HStack(alignment: .bottom) {
                Spacer()

                VStack(spacing: 8) {
                    // Refresh Button
                    circularControl(systemImage: "arrow.clockwise") {
                        Task {
                            await refreshAircraft()
                        }
                    }

                    // Locate / Recenter Button
                    circularControl(systemImage: "location.fill") {
                        targetRegion = MKCoordinateRegion(
                            center: Self.erieCoordinate,
                            span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
                        )
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
        }
        .safeAreaPadding(.top)
        .safeAreaPadding(.bottom)
    }

    /// Filter pills ("All", "Airports", "Planes") with safe-area breathing room
    private var filterPillsBar: some View {
        HStack(spacing: 2) {
            ForEach(MapDisplayMode.allCases) { mode in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        displayMode = mode
                    }
                    if mode == .airportsOnly {
                        selectedAircraft = nil
                        flightService.clearActiveRoute()
                    } else if mode == .planesOnly {
                        selectedAirport = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: displayMode == mode ? .semibold : .regular))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        displayMode == mode
                            ? settings.selectionAccentColor
                            : Color.clear
                    )
                    .foregroundStyle(
                        displayMode == mode
                            ? Color.white
                            : Color.primary
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
    }

    private func circularControl(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// Refresh aircraft using the user's selected ADS-B source and camera coordinates
    private func refreshAircraft() async {
        let nmi = Int(visibleRegion.span.latitudeDelta * 60.0)
        await flightService.updateAircraft(
            center: visibleRegion.center,
            radiusNmi: nmi,
            source: settings.selectedSource,
            customURL: settings.customDump1090URL
        )
    }
}

#Preview {
    ContentView()
}
