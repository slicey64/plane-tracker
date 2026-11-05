import SwiftUI

/// Settings sheet with ADS-B source selection (adsb.lol, airplanes.live, adsb.fi, dump1090)
struct SettingsSheet: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Section: ADS-B Data Source Selector
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
                    Text("ADS-B Data Source")
                } footer: {
                    Text(settings.selectedSource.description)
                }

                // Custom dump1090 local / self-hosted host input
                if settings.selectedSource == .customDump1090 {
                    Section("dump1090 Host URL") {
                        TextField("http://ip:port/data/aircraft.json", text: $settings.customDump1090URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.subheadline, design: .monospaced))

                        Text("Connects to dump1090, readsb, or tar1090 json feeds running on a local Raspberry Pi, SDR, or network server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Section: Polling & Refresh
                Section("Update Rate") {
                    Picker("Auto-Refresh Interval", selection: $settings.autoRefreshInterval) {
                        Text("Real-time (3s)").tag(3.0)
                        Text("Standard (5s)").tag(5.0)
                        Text("Relaxed (10s)").tag(10.0)
                        Text("Manual Only").tag(0.0)
                    }
                }

                // Section: About
                Section("About Flight Tracker") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.3.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Active Source")
                        Spacer()
                        Text(settings.selectedSource.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }
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
}
