import SwiftUI
import MapKit

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
    private static let erieCoordinate = CLLocationCoordinate2D(
        latitude: 42.083127,
        longitude: -80.173867
    )

    // Camera starts centered on Erie, PA with regional view
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: erieCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
        )
    )

    // Track the visible region from map camera changes
    @State private var visibleRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: erieCoordinate,
        span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
    )

    // Selection states
    @State private var selectedAirport: Airport?
    @State private var selectedAircraft: LiveAircraft?
    @State private var isShowingAirportDetailSheet: Bool = false
    @State private var isShowingAircraftDetailSheet: Bool = false
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

    /// Visible aircraft based on display mode
    private var displayedAircraft: [LiveAircraft] {
        guard displayMode != .airportsOnly else { return [] }
        return flightService.aircraft
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
        ZStack(alignment: .bottom) {
            // Fullscreen Map with selected MapStyle
            Map(position: $position) {
                // Airport Pins
                ForEach(displayedAirports) { airport in
                    Annotation(airport.name, coordinate: airport.coordinate) {
                        AirportMarkerView(
                            airport: airport,
                            isSelected: selectedAirport?.id == airport.id,
                            scope: currentScope,
                            showBadge: settings.showAirportCodesOnMap
                        )
                        .onTapGesture {
                            selectedAircraft = nil
                            flightService.clearActiveRoute()
                            selectedAirport = airport
                            isShowingAirportDetailSheet = true
                        }
                    }
                }

                // Plane Markers
                ForEach(displayedAircraft) { plane in
                    Annotation(plane.displayName, coordinate: plane.coordinate) {
                        PlaneMarkerView(
                            plane: plane,
                            isSelected: selectedAircraft?.hex == plane.hex,
                            isAnyPlaneSelected: selectedAircraft != nil,
                            scope: currentScope,
                            settings: settings
                        )
                        .onTapGesture {
                            selectedAirport = nil
                            selectedAircraft = plane
                            Task {
                                if let callsign = plane.callsign {
                                    _ = await flightService.fetchRoute(for: callsign)
                                }
                            }
                        }
                    }
                }

                // Highlighted Flight Route Path on the map (Origin -> Plane -> Destination)
                if settings.showRouteLines && activeFlightPathCoordinates.count >= 2 {
                    MapPolyline(coordinates: activeFlightPathCoordinates)
                        .stroke(.blue, lineWidth: 3.5)
                }
            }
            .mapStyle(currentMapStyle)
            .onMapCameraChange(frequency: .continuous) { context in
                visibleRegion = context.region
            }
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
            .ignoresSafeArea()
            .task(id: "\(visibleRegion.center.latitude)_\(settings.selectedSource.rawValue)") {
                // Auto-refresh aircraft when camera settles or source changes
                if displayMode != .airportsOnly {
                    await refreshAircraft()
                }
            }

            // Floating Controls Overlay
            VStack(spacing: 12) {
                // Top bar: Display Mode Picker & App Menu
                topFloatingBar

                Spacer()

                // Bottom preview cards
                if let selectedPlane = selectedAircraft, !isShowingAircraftDetailSheet {
                    selectedAircraftQuickCard(selectedPlane)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                } else if let selectedAir = selectedAirport, !isShowingAirportDetailSheet {
                    selectedAirportQuickCard(selectedAir)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
        }
        .sheet(isPresented: $isShowingAirportSearch) {
            AirportSearchView(service: airportService) { chosenAirport in
                selectedAirport = chosenAirport
                withAnimation {
                    position = .region(
                        MKCoordinateRegion(
                            center: chosenAirport.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
                        )
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingQuickSearch) {
            QuickSearchSheet(aircraft: flightService.aircraft, flightService: flightService) { chosenPlane in
                selectedAirport = nil
                selectedAircraft = chosenPlane
                withAnimation {
                    position = .region(
                        MKCoordinateRegion(
                            center: chosenPlane.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                        )
                    )
                }
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
        .sheet(isPresented: $isShowingAirportDetailSheet) {
            if let selected = selectedAirport {
                AirportDetailSheet(
                    airport: selected,
                    service: airportService,
                    onFocus: { airport in
                        selectedAirport = airport
                        withAnimation {
                            position = .region(
                                MKCoordinateRegion(
                                    center: airport.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
                                )
                            )
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingAircraftDetailSheet) {
            if let plane = selectedAircraft {
                AircraftDetailSheet(
                    aircraft: plane,
                    route: flightService.activeRoute,
                    flightService: flightService,
                    onFocus: { focusedPlane in
                        withAnimation {
                            position = .region(
                                MKCoordinateRegion(
                                    center: focusedPlane.coordinate,
                                    span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
                                )
                            )
                        }
                    }
                )
            }
        }
    }

    // MARK: - Subviews

    /// Floating top control bar with Show All Airports / Planes selector and Menu
    private var topFloatingBar: some View {
        HStack(alignment: .top) {
            // Mode Picker: "All", "Airports", "Planes"
            HStack(spacing: 4) {
                ForEach(MapDisplayMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            displayMode = mode
                            if mode == .airportsOnly {
                                selectedAircraft = nil
                                flightService.clearActiveRoute()
                            } else if mode == .planesOnly {
                                selectedAirport = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.caption2)
                            Text(mode.rawValue)
                                .font(.caption)
                                .fontWeight(displayMode == mode ? .bold : .medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(displayMode == mode ? Color.blue : Color.clear)
                        .foregroundStyle(displayMode == mode ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)

            Spacer()

            // Quick actions + Main Menu
            VStack(spacing: 8) {
                // Main Options Menu (Settings, UI Customization, Quick Search)
                Menu {
                    Button {
                        isShowingQuickSearch = true
                    } label: {
                        Label("Flight Quick Search", systemImage: "magnifyingglass")
                    }

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
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                }

                // Flight Quick Search shortcut
                Button {
                    isShowingQuickSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                }

                // Refresh planes button
                Button {
                    Task {
                        await refreshAircraft()
                    }
                } label: {
                    ZStack {
                        if flightService.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                }

                // Erie Re-center button
                Button {
                    withAnimation(.easeInOut) {
                        position = .region(
                            MKCoordinateRegion(
                                center: Self.erieCoordinate,
                                span: MKCoordinateSpan(latitudeDelta: 1.5, longitudeDelta: 1.5)
                            )
                        )
                    }
                } label: {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
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

    /// Convert AppMapStyle to MapKit MapStyle
    private var currentMapStyle: MapStyle {
        switch settings.mapStyle {
        case .standard:
            return .standard
        case .imagery:
            return .imagery
        case .hybrid:
            return .hybrid
        }
    }

    /// Floating bottom card for selected aircraft
    private func selectedAircraftQuickCard(_ plane: LiveAircraft) -> some View {
        HStack(spacing: 12) {
            Image("plane")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(plane.track ?? 0))
                .padding(8)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(plane.displayName)
                        .font(.subheadline)
                        .fontWeight(.bold)

                    if let type = plane.aircraftType {
                        Text(type)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                HStack(spacing: 6) {
                    Text(plane.formattedAltitude)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(plane.formattedSpeed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let route = flightService.activeRoute {
                    Text(route.summary)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.blue)
                }
            }

            Spacer()

            Button {
                isShowingAircraftDetailSheet = true
            } label: {
                Text("Details")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)

            Button {
                withAnimation {
                    selectedAircraft = nil
                    flightService.clearActiveRoute()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

    /// Floating bottom card for selected airport
    private func selectedAirportQuickCard(_ airport: Airport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: airport.type.systemImage)
                .font(.title2)
                .foregroundStyle(airport.type.tintColor)
                .padding(10)
                .background(airport.type.tintColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(airport.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
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

                Text("\(airport.municipality.isEmpty ? "" : airport.municipality + ", ")\(airport.formattedRegion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                isShowingAirportDetailSheet = true
            } label: {
                Text("Details")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)

            Button {
                withAnimation {
                    selectedAirport = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

/// Custom plane marker using plane.png, rotated by true heading and resized by map zoom and UI preferences
struct PlaneMarkerView: View {
    let plane: LiveAircraft
    let isSelected: Bool
    var isAnyPlaneSelected: Bool = false
    let scope: MapViewScope
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 2) {
            if settings.showPlaneLabelsAlways || scope == .cityOrLocal || isSelected {
                Text(plane.displayName)
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.ultraThinMaterial)
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            }

            // Custom plane icon loaded from plane.png
            Image("plane")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(planeColor)
                .frame(width: planeIconSize, height: planeIconSize)
                .rotationEffect(.degrees(plane.track ?? 0))
                .shadow(color: isSelected ? .blue.opacity(0.5) : .black.opacity(0.3), radius: isSelected ? 4 : 2, x: 0, y: 1)
        }
        .scaleEffect(isSelected ? 1.25 : (isAnyPlaneSelected ? 0.9 : 1.0))
        .opacity(isSelected ? 1.0 : (isAnyPlaneSelected ? 0.35 : 1.0))
        .animation(.easeInOut(duration: 0.25), value: isSelected)
        .animation(.easeInOut(duration: 0.25), value: isAnyPlaneSelected)
    }

    /// Plane icon size dynamically scaled based on map zoom and user setting
    private var planeIconSize: CGFloat {
        let baseSize: CGFloat
        if isSelected {
            baseSize = 36
        } else {
            switch scope {
            case .continentOrCountry:
                baseSize = 18
            case .stateOrRegion:
                baseSize = 24
            case .cityOrLocal:
                baseSize = 32
            }
        }
        return baseSize * CGFloat(settings.planeIconScaleMultiplier)
    }

    private var planeColor: Color {
        if isSelected {
            return .blue
        }

        switch settings.planeColorTheme {
        case .altitudeBased:
            guard let alt = plane.altitudeBaro else { return .gray }
            if alt > 30000 {
                return .blue
            } else if alt > 15000 {
                return .cyan
            } else if alt > 5000 {
                return .green
            } else {
                return .orange
            }
        case .monochromaticBlue:
            return .blue
        case .vibrantYellow:
            return .yellow
        case .highContrastGreen:
            return .green
        }
    }
}

/// Custom pin marker view for every airport
struct AirportMarkerView: View {
    let airport: Airport
    let isSelected: Bool
    let scope: MapViewScope
    var showBadge: Bool = true

    var body: some View {
        VStack(spacing: 2) {
            if showBadge && (scope != .continentOrCountry || airport.type == .largeAirport || isSelected) {
                Text(airport.displayCode)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(.ultraThinMaterial)
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }

            ZStack {
                Circle()
                    .fill(airport.type.tintColor)
                    .frame(width: markerSize, height: markerSize)
                    .shadow(color: airport.type.tintColor.opacity(0.4), radius: 3, x: 0, y: 1)

                Image(systemName: airport.type.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isSelected ? 1.25 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var markerSize: CGFloat {
        if isSelected { return 30 }
        switch scope {
        case .continentOrCountry:
            return 22
        case .stateOrRegion:
            return 24
        case .cityOrLocal:
            return 26
        }
    }

    private var iconSize: CGFloat {
        if isSelected { return 14 }
        switch scope {
        case .continentOrCountry:
            return 10
        case .stateOrRegion:
            return 11
        case .cityOrLocal:
            return 12
        }
    }
}

#Preview {
    ContentView()
}
