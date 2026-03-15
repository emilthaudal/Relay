//
//  OnboardingWelcomeView.swift
//  Relay
//
//  First screen of the onboarding wizard.
//

import SwiftUI
import SwiftData

struct OnboardingWelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Hero
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.tint)

                    Text("Welcome to Relay")
                        .font(.largeTitle.bold())

                    Text("Relay automatically syncs your workouts across all your fitness apps — so you record once and it appears everywhere.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Spacer()

                NavigationLink {
                    OnboardingHealthKitView()
                        .environment(appState)
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarHidden(true)
        }
        .onAppear { ensureAppState() }
    }

    /// Insert an AppState if none exists yet (first launch).
    private func ensureAppState() {
        let descriptor = FetchDescriptor<AppState>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        if count == 0 {
            modelContext.insert(AppState())
        }
    }
}
