//
//  OnboardingHealthKitView.swift
//  Relay
//
//  Step 2: Request HealthKit permissions.
//

import SwiftUI
import HealthKit

struct OnboardingHealthKitView: View {
    @Environment(AppState.self) private var appState

    @State private var permissionGranted = false
    @State private var requestInProgress = false
    @State private var errorMessage: String?

    private let adapter = HealthKitAdapter()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                Text("Connect Apple Health")
                    .font(.title.bold())

                Text("Relay reads and writes workouts from Apple Health. This is the foundation for all syncing.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Spacer()

            VStack(spacing: 12) {
                NavigationLink {
                    OnboardingAddConnectionsView()
                        .environment(appState)
                } label: {
                    Text(permissionGranted ? "Continue" : "Skip for Now")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    requestPermissions()
                } label: {
                    Group {
                        if requestInProgress {
                            ProgressView()
                        } else {
                            Text(permissionGranted ? "Permissions Granted" : "Allow Access")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(permissionGranted ? Color.green : Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(requestInProgress || permissionGranted)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func requestPermissions() {
        requestInProgress = true
        errorMessage = nil
        Task {
            do {
                try await adapter.authenticate()
                await MainActor.run {
                    @Bindable var state = appState
                    appState.enabledConnections.insert(.healthKit)
                    permissionGranted = true
                    requestInProgress = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    requestInProgress = false
                }
            }
        }
    }
}
