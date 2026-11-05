import SwiftUI
import MapKit

// MARK: - Plane Icon Cache

@MainActor
final class PlaneIconCache {
    static let shared = PlaneIconCache()
    private var cache: [String: UIImage] = [:]
    private let sourceImage: UIImage?

    private init() {
        self.sourceImage = UIImage(named: "plane")
    }

    /// Retrieve or pre-render a cached plane icon tinted with the given color and size
    func icon(color: UIColor, size: CGFloat = 28) -> UIImage {
        let roundedSize = max(16, round(size))
        let key = "\(color.description)_\(Int(roundedSize))"
        if let cached = cache[key] {
            return cached
        }

        let targetSize = CGSize(width: roundedSize, height: roundedSize)
        let format = UIGraphicsImageRendererFormat.preferred()
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let renderedImage = renderer.image { ctx in
            guard let src = sourceImage else { return }
            let rect = CGRect(origin: .zero, size: targetSize)
            src.draw(in: rect)
            ctx.cgContext.setBlendMode(.sourceIn)
            color.setFill()
            ctx.cgContext.fill(rect)
        }

        cache[key] = renderedImage
        return renderedImage
    }

    /// Determine icon color based on aircraft altitude or user theme
    static func planeUIColor(for aircraft: LiveAircraft, settings: AppSettings) -> UIColor {
        switch settings.planeColorTheme {
        case .altitudeBased:
            guard let alt = aircraft.altitudeBaro else { return .systemGray }
            if alt > 30000 {
                return .systemBlue
            } else if alt > 15000 {
                return .systemCyan
            } else if alt > 5000 {
                return .systemGreen
            } else {
                return .systemOrange
            }
        case .monochromaticBlue:
            return .systemBlue
        case .vibrantYellow:
            return .systemYellow
        case .highContrastGreen:
            return .systemGreen
        }
    }
}

// MARK: - Plane Annotation

final class PlaneAnnotation: NSObject, MKAnnotation {
    let hex: String
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var aircraft: LiveAircraft
    var heading: Double?

    init(aircraft: LiveAircraft) {
        self.hex = aircraft.hex
        self.coordinate = aircraft.coordinate
        self.aircraft = aircraft
        self.heading = aircraft.track
        super.init()
    }

    func update(with aircraft: LiveAircraft) {
        self.aircraft = aircraft
        if self.coordinate.latitude != aircraft.latitude || self.coordinate.longitude != aircraft.longitude {
            self.coordinate = aircraft.coordinate
        }
        self.heading = aircraft.track
    }

    var title: String? {
        aircraft.displayName
    }

    var subtitle: String? {
        "\(aircraft.formattedAltitude) • \(aircraft.formattedSpeed)"
    }
}

// MARK: - Plane Annotation View

final class PlaneAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "PlaneAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
        image = nil
    }

    func configure(with planeAnnotation: PlaneAnnotation, settings: AppSettings) {
        let color = PlaneIconCache.planeUIColor(for: planeAnnotation.aircraft, settings: settings)
        let baseSize: CGFloat = 26.0 * CGFloat(settings.planeIconScaleMultiplier)
        self.image = PlaneIconCache.shared.icon(color: color, size: baseSize)
        updateTransform(heading: planeAnnotation.heading, isSelected: isSelected)
    }

    private func updateTransform(heading: Double?, isSelected: Bool) {
        let headingRad = CGFloat((heading ?? 0.0) * .pi / 180.0)
        let scale: CGFloat = isSelected ? 1.3 : 1.0
        self.transform = CGAffineTransform(rotationAngle: headingRad).scaledBy(x: scale, y: scale)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        guard let planeAnnotation = annotation as? PlaneAnnotation else { return }

        let updates = {
            self.updateTransform(heading: planeAnnotation.heading, isSelected: selected)
        }

        if animated {
            UIView.animate(withDuration: 0.2, animations: updates)
        } else {
            updates()
        }
    }
}

// MARK: - Airport Annotation

final class AirportAnnotation: NSObject, MKAnnotation {
    let id: Int
    let airport: Airport
    let coordinate: CLLocationCoordinate2D

    init(airport: Airport) {
        self.id = airport.id
        self.airport = airport
        self.coordinate = airport.coordinate
        super.init()
    }

    var title: String? {
        airport.displayCode
    }

    var subtitle: String? {
        airport.name
    }
}

// MARK: - Airport Annotation View

final class AirportAnnotationView: MKMarkerAnnotationView {
    static let reuseIdentifier = "AirportAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        displayPriority = .defaultLow
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with airportAnnotation: AirportAnnotation) {
        let airport = airportAnnotation.airport
        glyphImage = UIImage(systemName: airport.type.systemImage)
        markerTintColor = UIColor(airport.type.tintColor)
        titleVisibility = .adaptive
        subtitleVisibility = .hidden
        displayPriority = airport.type == .largeAirport ? .required : .defaultLow
    }
}

// MARK: - FlightMapView (MKMapView Representable)

struct FlightMapView: UIViewRepresentable {
    let aircraft: [LiveAircraft]
    let airports: [Airport]
    let routeCoordinates: [CLLocationCoordinate2D]
    let showRouteLines: Bool
    let settings: AppSettings
    @Binding var visibleRegion: MKCoordinateRegion
    @Binding var targetRegion: MKCoordinateRegion?
    let selectedAircraftHex: String?
    let selectedAirportId: Int?

    let onSelectAircraft: (LiveAircraft) -> Void
    let onSelectAirport: (Airport) -> Void
    let onDeselect: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()

        let config = MKStandardMapConfiguration(elevationStyle: .flat)
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config
        mapView.pointOfInterestFilter = .excludingAll

        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.setRegion(visibleRegion, animated: false)

        mapView.register(PlaneAnnotationView.self, forAnnotationViewWithReuseIdentifier: PlaneAnnotationView.reuseIdentifier)
        mapView.register(AirportAnnotationView.self, forAnnotationViewWithReuseIdentifier: AirportAnnotationView.reuseIdentifier)

        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // 1. Programmatic region camera shift (recenter / search selection)
        if let target = targetRegion {
            coordinator.isProgrammaticRegionChange = true
            mapView.setRegion(target, animated: true)
            DispatchQueue.main.async {
                self.targetRegion = nil
            }
        }

        // 2. Map Style & POI Configuration (flat standard with POIs filtered)
        switch settings.mapStyle {
        case .standard:
            if !(mapView.preferredConfiguration is MKStandardMapConfiguration) {
                let config = MKStandardMapConfiguration(elevationStyle: .flat)
                config.pointOfInterestFilter = .excludingAll
                mapView.preferredConfiguration = config
            }
        case .imagery:
            if !(mapView.preferredConfiguration is MKImageryMapConfiguration) {
                let config = MKImageryMapConfiguration(elevationStyle: .flat)
                mapView.preferredConfiguration = config
            }
        case .hybrid:
            if !(mapView.preferredConfiguration is MKHybridMapConfiguration) {
                let config = MKHybridMapConfiguration(elevationStyle: .flat)
                config.pointOfInterestFilter = .excludingAll
                mapView.preferredConfiguration = config
            }
        }

        // 3. Diff Aircraft Annotations by ICAO hex
        var newHexSet = Set<String>()
        newHexSet.reserveCapacity(aircraft.count)
        var planesToAdd: [PlaneAnnotation] = []

        for plane in aircraft {
            newHexSet.insert(plane.hex)
            if let existing = coordinator.planeAnnotations[plane.hex] {
                existing.update(with: plane)
                if let view = mapView.view(for: existing) as? PlaneAnnotationView {
                    view.configure(with: existing, settings: settings)
                }
            } else {
                let annotation = PlaneAnnotation(aircraft: plane)
                coordinator.planeAnnotations[plane.hex] = annotation
                planesToAdd.append(annotation)
            }
        }

        var planesToRemove: [PlaneAnnotation] = []
        for (hex, annotation) in coordinator.planeAnnotations {
            if !newHexSet.contains(hex) {
                planesToRemove.append(annotation)
                coordinator.planeAnnotations.removeValue(forKey: hex)
            }
        }

        if !planesToRemove.isEmpty {
            mapView.removeAnnotations(planesToRemove)
        }
        if !planesToAdd.isEmpty {
            mapView.addAnnotations(planesToAdd)
        }

        // 4. Diff Airport Annotations by airport ID
        var newAirportIdSet = Set<Int>()
        newAirportIdSet.reserveCapacity(airports.count)
        var airportsToAdd: [AirportAnnotation] = []

        for airport in airports {
            newAirportIdSet.insert(airport.id)
            if coordinator.airportAnnotations[airport.id] == nil {
                let annotation = AirportAnnotation(airport: airport)
                coordinator.airportAnnotations[airport.id] = annotation
                airportsToAdd.append(annotation)
            }
        }

        var airportsToRemove: [AirportAnnotation] = []
        for (id, annotation) in coordinator.airportAnnotations {
            if !newAirportIdSet.contains(id) {
                airportsToRemove.append(annotation)
                coordinator.airportAnnotations.removeValue(forKey: id)
            }
        }

        if !airportsToRemove.isEmpty {
            mapView.removeAnnotations(airportsToRemove)
        }
        if !airportsToAdd.isEmpty {
            mapView.addAnnotations(airportsToAdd)
        }

        // 5. Update route line polyline overlay
        coordinator.updateRouteOverlay(mapView: mapView, coordinates: routeCoordinates, showLines: showRouteLines)

        // 6. Synchronize selection state if changed programmatically
        coordinator.syncSelection(
            mapView: mapView,
            selectedAircraftHex: selectedAircraftHex,
            selectedAirportId: selectedAirportId
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: FlightMapView
        var planeAnnotations: [String: PlaneAnnotation] = [:]
        var airportAnnotations: [Int: AirportAnnotation] = [:]
        var currentPolyline: MKPolyline?
        var currentPolylineCoordinates: [CLLocationCoordinate2D] = []
        var isProgrammaticRegionChange = false

        init(_ parent: FlightMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let planeAnnotation = annotation as? PlaneAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: PlaneAnnotationView.reuseIdentifier,
                    for: planeAnnotation
                ) as? PlaneAnnotationView ?? PlaneAnnotationView(annotation: planeAnnotation, reuseIdentifier: PlaneAnnotationView.reuseIdentifier)
                view.configure(with: planeAnnotation, settings: parent.settings)
                return view
            } else if let airportAnnotation = annotation as? AirportAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: AirportAnnotationView.reuseIdentifier,
                    for: airportAnnotation
                ) as? AirportAnnotationView ?? AirportAnnotationView(annotation: airportAnnotation, reuseIdentifier: AirportAnnotationView.reuseIdentifier)
                view.configure(with: airportAnnotation)
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let planeAnnotation = view.annotation as? PlaneAnnotation {
                parent.onSelectAircraft(planeAnnotation.aircraft)
            } else if let airportAnnotation = view.annotation as? AirportAnnotation {
                parent.onSelectAirport(airportAnnotation.airport)
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if mapView.selectedAnnotations.isEmpty {
                parent.onDeselect()
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticRegionChange {
                isProgrammaticRegionChange = false
            }
            parent.visibleRegion = mapView.region
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 3.5
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func updateRouteOverlay(mapView: MKMapView, coordinates: [CLLocationCoordinate2D], showLines: Bool) {
            guard showLines, coordinates.count >= 2 else {
                if let poly = currentPolyline {
                    mapView.removeOverlay(poly)
                    currentPolyline = nil
                    currentPolylineCoordinates = []
                }
                return
            }

            var isSame = (coordinates.count == currentPolylineCoordinates.count)
            if isSame {
                for i in 0..<coordinates.count {
                    if coordinates[i].latitude != currentPolylineCoordinates[i].latitude ||
                       coordinates[i].longitude != currentPolylineCoordinates[i].longitude {
                        isSame = false
                        break
                    }
                }
            }

            if isSame { return }

            if let poly = currentPolyline {
                mapView.removeOverlay(poly)
            }

            let newPolyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            currentPolyline = newPolyline
            currentPolylineCoordinates = coordinates
            mapView.addOverlay(newPolyline)
        }

        func syncSelection(mapView: MKMapView, selectedAircraftHex: String?, selectedAirportId: Int?) {
            if selectedAircraftHex == nil && selectedAirportId == nil {
                if !mapView.selectedAnnotations.isEmpty {
                    for annotation in mapView.selectedAnnotations {
                        mapView.deselectAnnotation(annotation, animated: true)
                    }
                }
                return
            }

            if let hex = selectedAircraftHex, let annotation = planeAnnotations[hex] {
                if !mapView.selectedAnnotations.contains(where: { ($0 as? PlaneAnnotation)?.hex == hex }) {
                    mapView.selectAnnotation(annotation, animated: true)
                }
            } else if let id = selectedAirportId, let annotation = airportAnnotations[id] {
                if !mapView.selectedAnnotations.contains(where: { ($0 as? AirportAnnotation)?.id == id }) {
                    mapView.selectAnnotation(annotation, animated: true)
                }
            }
        }
    }
}
