//
//  RelayApp.swift
//  Relay
//
//  App entry point. Sets up SwiftData container and routes to onboarding or main UI.
//

import SwiftUI
import SwiftData

@main
struct RelayApp: App {

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: WorkoutRecord.self, SyncRecord.self, AppState.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        #if os(iOS)
        BackgroundSyncTask.shared.registerHandlers()
        BackgroundSyncTask.shared.scheduleNextRefresh()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container)
        }
    }
}

// MARK: - Root routing view

private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var appStates: [AppState]

    private var appState: AppState? { appStates.first }

    var body: some View {
        if let appState {
            if appState.onboardingCompleted {
                MainTabView()
                    .environment(appState)
            } else {
                OnboardingWelcomeView()
                    .environment(appState)
            }
        } else {
            ProgressView("Loading…")
                .onAppear { ensureAppState() }
        }
    }

    /// Insert an AppState row on first launch so RootView can route correctly.
    private func ensureAppState() {
        let descriptor = FetchDescriptor<AppState>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        if count == 0 {
            modelContext.insert(AppState())
        }
    }
}
