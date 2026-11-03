//
//  OnboardingDoneView.swift
//  Relay
//
//  Final onboarding step. Marks onboarding complete and transitions to MainTabView.
//

import SwiftUI

struct OnboardingDoneView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                Text("You're All Set!")
                    .font(.largeTitle.bold())

                Text("Relay checks Intervals.icu for new workouts when you open it, and from time to time in the background, and saves them to Apple Health.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            Spacer()

            Button {
                appState.onboardingCompleted = true
            } label: {
                Text("Start Using Relay")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationBarBackButtonHidden()
    }
}
