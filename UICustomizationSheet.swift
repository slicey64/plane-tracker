import SwiftUI

/// Sheet for configuring map appearance, plane icon sizing, color schemes, airport pin colors, and annotation overlays
struct UICustomizationSheet: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private let presetPlaneColors: [Color] = [
        Color(hex: "#007AFF"), // Electric Blue
        Color(hex: "#FF9500"), // Radar Amber
        Color(hex: "#34C759"), // Radar Green
        Color(hex: "#FF2D55"), // Neon Coral / Pink
        Color(hex: "#AF52DE"), // Royal Purple
        Color(hex: "#00C7BE"), // Cyan
        Color(hex: "#FF3B30"), // High-Vis Red
        Color(hex: "#E5E5EA")  // Clean Silver
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Basemap Layer
                Section("Map Layer Style") {
                    Picker("Basemap", selection: $settings.mapStyle) {
                        ForEach(AppSettings.AppMapStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Aircraft Colors & Styling
                Section {
                    Picker("Color Theme", selection: $settings.planeColorTheme) {
                        ForEach(AppSettings.PlaneColorTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    if settings.planeColorTheme == .customSingle {
                        ColorPicker("Custom Plane Color", selection: $settings.customPlaneColor, supportsOpacity: false)

                        // Quick color palette presets
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Palette Presets")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                ForEach(presetPlaneColors, id: \.self) { color in
                                    Circle()
                                        .fill(color)
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary.opacity(0.3), lineWidth: settings.customPlaneColor == color ? 2.5 : 0.5)
                                        )
                                        .onTapGesture {
                                            settings.customPlaneColor = color
                                        }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Visual preview of aircraft
                    HStack(spacing: 12) {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(0..<4) { i in
                                Image("plane")
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                    .foregroundStyle(sampleColor(for: i))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Aircraft Styling & Colors")
                } footer: {
                    Text(settings.planeColorTheme == .customSingle
                         ? "Choose any custom color or quick swatch to apply across all aircraft."
                         : "Altitude Gradient dynamically tints aircraft from orange (low/takeoff) to blue (cruising flight levels).")
                }

                // Airport Facility Pin Colors
                Section {
                    ColorPicker("Major Hub Airports", selection: $settings.largeAirportColor, supportsOpacity: false)
                    ColorPicker("Medium / Regional Airports", selection: $settings.mediumAirportColor, supportsOpacity: false)
                    ColorPicker("Small / GA Airfields", selection: $settings.smallAirportColor, supportsOpacity: false)
                    ColorPicker("Heliports", selection: $settings.heliportColor, supportsOpacity: false)
                    ColorPicker("Seaplane Bases", selection: $settings.seaplaneBaseColor, supportsOpacity: false)

                    // Quick airport themes
                    HStack(spacing: 12) {
                        Button("Aviation Sky") {
                            settings.largeAirportColor = Color(hex: "#007AFF")
                            settings.mediumAirportColor = Color(hex: "#5856D6")
                            settings.smallAirportColor = Color(hex: "#30B0C7")
                            settings.heliportColor = Color(hex: "#FF9500")
                            settings.seaplaneBaseColor = Color(hex: "#00C7BE")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("High-Contrast") {
                            settings.largeAirportColor = Color(hex: "#34C759")
                            settings.mediumAirportColor = Color(hex: "#FFCC00")
                            settings.smallAirportColor = Color(hex: "#32ADE6")
                            settings.heliportColor = Color(hex: "#FF9500")
                            settings.seaplaneBaseColor = Color(hex: "#AF52DE")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Button("Neon Glow") {
                            settings.largeAirportColor = Color(hex: "#FF2D55")
                            settings.mediumAirportColor = Color(hex: "#AF52DE")
                            settings.smallAirportColor = Color(hex: "#5856D6")
                            settings.heliportColor = Color(hex: "#FF9500")
                            settings.seaplaneBaseColor = Color(hex: "#30B0C7")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Airport Pin Colors")
                } footer: {
                    Text("Customize marker pin colors for each airport facility classification tier.")
                }

                // Route Line & Selection Accent Colors
                Section("Route & Selection Colors") {
                    ColorPicker("Flight Route Line Color", selection: $settings.routeLineColor, supportsOpacity: false)
                    ColorPicker("Selection Accent Color", selection: $settings.selectionAccentColor, supportsOpacity: false)
                }

                // Plane Marker Sizing
                Section("Plane Icon Size") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Scale Multiplier")
                            Spacer()
                            Text(String(format: "%.1fx", settings.planeIconScaleMultiplier))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.planeIconScaleMultiplier, in: 0.8...1.6, step: 0.1)
                    }
                }

                // Map Annotations & Overlays
                Section("Overlays & Effects") {
                    Toggle("Liquid Glass Icons", isOn: $settings.enableLiquidGlass)
                    Toggle("Always Show Flight Callout Labels", isOn: $settings.showPlaneLabelsAlways)
                    Toggle("Show Flight Route Lines", isOn: $settings.showRouteLines)
                    Toggle("Show Airport Code Badges", isOn: $settings.showAirportCodesOnMap)
                }

                // Reset Defaults
                Section {
                    Button(role: .destructive) {
                        withAnimation {
                            settings.mapStyle = .standard
                            settings.planeColorTheme = .altitudeBased
                            settings.planeIconScaleMultiplier = 1.0
                            settings.showPlaneLabelsAlways = false
                            settings.showRouteLines = true
                            settings.showAirportCodesOnMap = true
                            settings.enableLiquidGlass = true
                            settings.resetColorsToDefaults()
                        }
                    } label: {
                        Text("Reset UI to Defaults")
                    }
                }
            }
            .navigationTitle("UI Customization")
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

    private func sampleColor(for index: Int) -> Color {
        switch settings.planeColorTheme {
        case .altitudeBased:
            switch index {
            case 0: return .orange
            case 1: return .green
            case 2: return .cyan
            default: return .blue
            }
        case .monochromaticBlue:
            return .blue
        case .vibrantYellow:
            return .yellow
        case .highContrastGreen:
            return .green
        case .customSingle:
            return settings.customPlaneColor
        }
    }
}
