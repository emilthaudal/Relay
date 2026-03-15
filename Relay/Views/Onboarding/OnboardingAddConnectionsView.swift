//
//  OnboardingAddConnectionsView.swift
//  Relay
//
//  Step 3: Add Strava and Intervals.icu connections.
//

import SwiftUI

struct OnboardingAddConnectionsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)

                Text("Add Connections")
                    .font(.title.bold())

                Text("Connect your other fitness accounts. You can add or remove connections any time in Settings.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            connectionsList

            Spacer()

            NavigationLink {
                OnboardingSourcePriorityView()
                    .environment(appState)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectionsList: some View {
        VStack(spacing: 0) {
            ForEach(ConnectionType.allCases.filter { $0.isAvailable && $0 != .healthKit }) { connection in
                ConnectionRow(connection: connection)
                    .environment(appState)
                Divider().padding(.leading, 56)
            }
        }
        .background(.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Connection Row

private struct ConnectionRow: View {
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
                .font(.title2)
                .foregroundStyle(isEnabled ? .tint : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.displayName)
                    .font(.body.weight(.medium))
                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else if isEnabled {
                    Text("Connected").font(.caption).foregroundStyle(.green)
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil
        Task {
            do {
                switch connection {
                case .strava:
                    let adapter = StravaAdapter()
                    try await adapter.authenticate()
                case .intervals:
                    let adapter = IntervalsAdapter()
                    try await adapter.authenticate()
                default:
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
