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

    private var isEnabled: Bool {
        appState.enabledConnections.contains(connection)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.symbolName)
                .font(.title3)
                .foregroundStyle(isEnabled ? .tint : .secondary)
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
    }

    private func connect() {
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
                case .intervals:
                    let adapter = IntervalsAdapter()
                    try await adapter.authenticate()
                case .hammerhead:
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
