import SwiftUI

/// Settings sheet with ADS-B source selection, FlightAware AeroAPI configuration, and Source Delegation
struct SettingsSheet: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingAPIKey: Bool = false
    @State private var isTestingKey: Bool = false
    @State private var testResult: (isValid: Bool, message: String)? = nil

    @State private var isShowingApiNinjasKey: Bool = false
    @State private var isTestingApiNinjasKey: Bool = false
    @State private var apiNinjasTestResult: (isValid: Bool, message: String)? = nil

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Live Map Telemetry Source
                mapSourceSection

                // Section 2: FlightAware AeroAPI Key & Configuration
                flightAwareSection

                // Section 3: Granular FlightAware GET Waypoints / Selectors
                if settings.isFlightAwareConfigured {
                    flightAwareWaypointsSection
                }

                // Section: API-Ninjas Aircraft API Key & Configuration
                apiNinjasSection

                // Section 4: Data Source Delegation (Manage Different Parts of the App)
                sourceDelegationSection

                // Section 5: Visual Effects & Liquid Glass
                visualEffectsSection

                // Section 6: Polling & Refresh
                updateRateSection

                // Section 7: About
                aboutSection
            }
            .navigationTitle("Settings")
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

    // MARK: - Sections

    /// Section 1: Map Telemetry Source (adsb.lol, airplanes.live, adsb.fi, dump1090)
    private var mapSourceSection: some View {
        Section {
            ForEach(AppSettings.ADSBDataSource.allCases) { source in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(source.rawValue)
                            .fontWeight(.medium)

                        Spacer()

                        if source == settings.selectedSource {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }

                    Text(source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    settings.selectedSource = source
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Map Telemetry Source")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(settings.selectedSource.description)
                if settings.selectedSource == .customDump1090 {
                    TextField("http://ip:port/data/aircraft.json", text: $settings.customDump1090URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.subheadline, design: .monospaced))
                        .padding(.top, 4)
                }
            }
        }
    }

    /// Section 2: FlightAware AeroAPI Key
    private var flightAwareSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if isShowingAPIKey {
                        TextField("Enter FlightAware API Key", text: $settings.flightAwareAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))
                    } else {
                        SecureField("Enter FlightAware API Key", text: $settings.flightAwareAPIKey)
                            .font(.system(.subheadline, design: .monospaced))
                    }

                    Button {
                        isShowingAPIKey.toggle()
                    } label: {
                        Image(systemName: isShowingAPIKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if !settings.flightAwareAPIKey.isEmpty {
                        Button {
                            settings.flightAwareAPIKey = ""
                            testResult = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Test Connection Button & Indicator
                HStack(spacing: 8) {
                    Button {
                        Task {
                            isTestingKey = true
                            testResult = await FlightAwareService.shared.testAPIKey(settings.flightAwareAPIKey)
                            isTestingKey = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingKey {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(isTestingKey ? "Verifying..." : "Test Connection")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .disabled(settings.flightAwareAPIKey.isEmpty || isTestingKey)

                    if let result = testResult {
                        HStack(spacing: 4) {
                            Image(systemName: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.isValid ? .green : .orange)
                            Text(result.isValid ? "Verified" : "Check Key")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(result.isValid ? .green : .orange)
                        }
                    }
                }
                .padding(.top, 2)

                if let result = testResult {
                    Text(result.message)
                        .font(.caption2)
                        .foregroundStyle(result.isValid ? Color.secondary : Color.red)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("FlightAware AeroAPI")
        } footer: {
            Text("Your API key is stored securely in app settings and is never hardcoded. Used for live gates, baggage claim, historical flight legs, and aircraft age.")
        }
    }

    /// Section 3: Granular GET Waypoints / Feature Selectors for FlightAware
    private var flightAwareWaypointsSection: some View {
        Section {
            Toggle(isOn: $settings.flightAwareEnableGatesAndSchedule) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gates, Terminals & Baggage")
                        .font(.subheadline)
                    Text("GET /flights/{ident} — departure/arrival gates, terminals, delays, baggage carousel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.flightAwareEnableAircraftSpecs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Airframe Specs & Aircraft Age")
                        .font(.subheadline)
                    Text("GET /aircraft/{ident} — exact model, manufacturer, year built, engines, age")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.flightAwareEnableHistoricalFlights) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Historical Flights & Recent Legs")
                        .font(.subheadline)
                    Text("GET /flights/{ident} — past completed flights, route history, and schedule")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.flightAwareEnableRoutes) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ATC Filed IFR Routes")
                        .font(.subheadline)
                    Text("GET /flights/{ident} — filed airway route, filed altitude, filed speed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.flightAwareEnableAirportBoards) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Airport Flight Boards")
                        .font(.subheadline)
                    Text("GET /airports/{id}/flights — live airport scheduled departures and arrivals")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("FlightAware API Waypoints")
        } footer: {
            Text("Toggle individual API endpoints on or off to customize which pieces of data are fetched.")
        }
    }

    /// Section: API-Ninjas Aircraft API Key & Configuration
    private var apiNinjasSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if isShowingApiNinjasKey {
                        TextField("Enter API-Ninjas API Key", text: $settings.apiNinjasKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))
                    } else {
                        SecureField("Enter API-Ninjas API Key", text: $settings.apiNinjasKey)
                            .font(.system(.subheadline, design: .monospaced))
                    }

                    Button {
                        isShowingApiNinjasKey.toggle()
                    } label: {
                        Image(systemName: isShowingApiNinjasKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    if !settings.apiNinjasKey.isEmpty {
                        Button {
                            settings.apiNinjasKey = ""
                            apiNinjasTestResult = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Test Connection Button & Indicator
                HStack(spacing: 8) {
                    Button {
                        Task {
                            isTestingApiNinjasKey = true
                            apiNinjasTestResult = await AircraftSpecsService.shared.testAPIKey(settings.apiNinjasKey)
                            isTestingApiNinjasKey = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isTestingApiNinjasKey {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "airplane.circle")
                            }
                            Text(isTestingApiNinjasKey ? "Verifying..." : "Test Aircraft API")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .disabled(settings.apiNinjasKey.isEmpty || isTestingApiNinjasKey)

                    if let result = apiNinjasTestResult {
                        HStack(spacing: 4) {
                            Image(systemName: result.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.isValid ? .green : .orange)
                            Text(result.isValid ? "Verified" : "Check Key")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(result.isValid ? .green : .orange)
                        }
                    }
                }
                .padding(.top, 2)

                if let result = apiNinjasTestResult {
                    Text(result.message)
                        .font(.caption2)
                        .foregroundStyle(result.isValid ? Color.secondary : Color.red)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("API-Ninjas Aircraft API")
        } footer: {
            Text("Used to query https://api.api-ninjas.com/v1/aircraft for technical data like engines, wingspan, MTOW, range, max speed, and airframe dimensions.")
        }
    }

    /// Section 4: Data Source Delegation Matrix
    private var sourceDelegationSection: some View {
        Section {
            // Map live telemetry
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map & Telemetry")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("GPS position, altitude, speed, track")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(settings.selectedSource.rawValue)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            // Gates & Schedule
            Picker("Gates & Delays", selection: $settings.gateScheduleProvider) {
                ForEach(AppSettings.GateScheduleProvider.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }

            // Aircraft Specs & Age
            Picker("Aircraft Specs & Age", selection: $settings.aircraftSpecsProvider) {
                ForEach(AppSettings.AircraftSpecsProvider.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }

            // Airport Flight Boards
            Picker("Airport Flight Boards", selection: $settings.airportBoardProvider) {
                ForEach(AppSettings.AirportBoardProvider.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }

            // Photos
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aircraft Photos")
                        .font(.subheadline)
                    Text("Real photos & photographer attribution")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("JetPhotos (jetapi.dev)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Data Source Delegation")
        } footer: {
            Text("Allows different sources to power different parts of the app (e.g., adsb.lol for map positions, FlightAware for gates and aircraft age, and JetPhotos for airframe photography).")
        }
    }

    /// Section 5: Visual Effects
    private var visualEffectsSection: some View {
        Section {
            Toggle("Liquid Glass Icons", isOn: $settings.enableLiquidGlass)
        } header: {
            Text("Visual Effects")
        } footer: {
            Text("Applies translucent frosted liquid glass effects with specular highlights, bevels, and depth to aircraft, airport markers, and controls.")
        }
    }

    /// Section 6: Update Rate
    private var updateRateSection: some View {
        Section("Update Rate") {
            Picker("Auto-Refresh Interval", selection: $settings.autoRefreshInterval) {
                Text("Real-time (3s)").tag(3.0)
                Text("Standard (5s)").tag(5.0)
                Text("Relaxed (10s)").tag(10.0)
                Text("Manual Only").tag(0.0)
            }
        }
    }

    /// Section 7: About
    private var aboutSection: some View {
        Section("About Flight Tracker") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.4.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Map Feed")
                Spacer()
                Text(settings.selectedSource.rawValue)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("AeroAPI Connected")
                Spacer()
                Text(settings.isFlightAwareConfigured ? "Yes" : "No Key")
                    .foregroundStyle(settings.isFlightAwareConfigured ? .green : .secondary)
            }
        }
    }
}
