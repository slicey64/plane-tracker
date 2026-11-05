import SwiftUI

/// Sheet for configuring map appearance, plane icon sizing, color schemes, and annotation overlays
struct UICustomizationSheet: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Map Style
                Section("Map Layer Style") {
                    Picker("Basemap", selection: $settings.mapStyle) {
                        ForEach(AppSettings.AppMapStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Plane Icon Styling & Colors
                Section("Aircraft Color Theme") {
                    Picker("Plane Colors", selection: $settings.planeColorTheme) {
                        ForEach(AppSettings.PlaneColorTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }

                    // Visual preview of current theme
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
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(sampleColor(for: i))
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
                Section("Overlays & Labels") {
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
        }
    }
}
