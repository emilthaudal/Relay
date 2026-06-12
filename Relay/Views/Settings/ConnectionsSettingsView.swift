//
//  ConnectionsSettingsView.swift
//  Relay
//
//  Re-accessible from Settings. Shows auth status per connection, connect/disconnect buttons.
//

import SwiftUI

struct ConnectionsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section {
                ForEach(ConnectionType.allCases.filter { $0.isAvailable }) { connection in
                    SettingsConnectionRow(connection: connection)
                        .environment(appState)
                }
            } footer: {
                Text("Hammerhead integration is planned for a future release.")
                    .font(.caption)
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings Connection Row

private struct SettingsConnectionRow: View {
    let connection: ConnectionType
    @Environment(AppState.self) private var appState

    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showIntervalsSheet = false

    private var isEnabled: Bool {
        appState.enabledConnections.contains(connection)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.symbolName)
                .font(.title3)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName)
                    .font(.body)
                if let error = errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.red)
                } else {
                    Text(isEnabled ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundStyle(isEnabled ? .green : .secondary)
                }
            }

            Spacer()

            if isConnecting {
                ProgressView().controlSize(.small)
            } else if isEnabled {
                Button("Disconnect", role: .destructive) { disconnect() }
                    .font(.caption.weight(.medium))
            } else {
                Button("Connect") { connect() }
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showIntervalsSheet) {
            IntervalsCredentialsView(onConnected: {
                appState.enabledConnections.insert(.intervals)
            })
            .environment(appState)
        }
    }

    private func connect() {
        if connection == .intervals {
            showIntervalsSheet = true
            return
        }
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                switch connection {
                case .healthKit:
                    let adapter = HealthKitAdapter()
                    try await adapter.authenticate()
                case .strava:
                    let adapter = StravaAdapter()
                    try await adapter.authenticate()
                case .intervals, .hammerhead:
                    break
                }
                await MainActor.run {
                    appState.enabledConnections.insert(connection)
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }

    private func disconnect() {
        Task {
            switch connection {
            case .strava:    await StravaAdapter().disconnect()
            case .intervals: await IntervalsAdapter().disconnect()
            default: break
            }
            await MainActor.run {
                appState.enabledConnections.remove(connection)
            }
        }
    }
}

// MARK: - Intervals.icu Credentials Sheet

private struct IntervalsCredentialsView: View {
    @Environment(\.dismiss) private var dismiss

    let onConnected: () -> Void

    @State private var athleteID = ""
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private var canConnect: Bool {
        !athleteID.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Athlete ID", text: $athleteID)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("API Key", text: $apiKey)
                } header: {
                    Text("Intervals.icu")
                } footer: {
                    Text("Find your API key at intervals.icu → Profile → API Key.")
                        .font(.caption)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Connect Intervals.icu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Connect") { connect() }
                            .disabled(!canConnect)
                    }
                }
            }
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        let trimmedID  = athleteID.trimmingCharacters(in: .whitespaces)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let adapter = IntervalsAdapter()
                await adapter.setCredentials(athleteID: trimmedID, apiKey: trimmedKey)
                try await adapter.authenticate()
                await MainActor.run {
                    onConnected()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isConnecting = false
                }
            }
        }
    }
}
