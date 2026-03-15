//
//  OnboardingSourcePriorityView.swift
//  Relay
//
//  Step 4 (skippable): Set source priority per sport type.
//  Pre-populated from AppState defaults.
//

import SwiftUI

struct OnboardingSourcePriorityView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            SourcePriorityContent()
                .environment(appState)

            Spacer()

            VStack(spacing: 12) {
                NavigationLink {
                    OnboardingDoneView()
                        .environment(appState)
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }

                NavigationLink {
                    OnboardingDoneView()
                        .environment(appState)
                } label: {
                    Text("Skip")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Source Priority")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared content (also used by SourcePrioritySettingsView)

struct SourcePriorityContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            ForEach(SportType.allCases) { sport in
                Section(sport.displayName) {
                    let sources = appState.sourcePriority(for: sport)
                    ForEach(sources.indices, id: \.self) { index in
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Image(systemName: sources[index].symbolName)
                                .foregroundStyle(.secondary)
                            Text(sources[index].displayName)
                        }
                    }
                    .onMove { from, to in
                        var updated = sources
                        updated.move(fromOffsets: from, toOffset: to)
                        appState.setSourcePriority(updated, for: sport)
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
    }
}
