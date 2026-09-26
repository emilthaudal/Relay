//
//  OnboardingAddConnectionsView.swift
//  Relay
//
//  Step 3: Add the Intervals.icu connection.
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

// MARK: - Connection Row

private struct ConnectionRow: View {
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
                .font(.title2)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
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
        .sheet(isPresented: $showIntervalsSheet) {
            IntervalsCredentialsView(onConnected: {
                appState.enabledConnections.insert(.intervals)
            })
        }
    }

    private func connect() {
        guard connection == .intervals else { return }
        isConnecting = true
        errorMessage = nil
        Task {
            let adapter = IntervalsAdapter()
            if await adapter.isConnected, (try? await adapter.authenticate()) != nil {
                appState.enabledConnections.insert(.intervals)
            } else {
                showIntervalsSheet = true
            }
            isConnecting = false
        }
    }

    private func disconnect() {
        Task {
            switch connection {
            case .intervals: await IntervalsAdapter().disconnect()
            default: break
            }
            await MainActor.run {
                _ = appState.enabledConnections.remove(connection)
            }
        }
    }
}
