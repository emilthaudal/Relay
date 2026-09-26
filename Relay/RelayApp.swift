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
        let schema = Schema([WorkoutRecord.self, SyncRecord.self, AppState.self])
        let config = ModelConfiguration(schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Schema migration failed (e.g. new non-optional attribute on existing store).
            // Delete the store and recreate — all data can be re-synced from connected services.
            let storeURL = config.url
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove SQLite WAL/SHM sidecars (named "default.store-wal", etc.)
            let dir = storeURL.deletingLastPathComponent()
            let base = storeURL.lastPathComponent
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(base + suffix))
            }
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }

        #if DEBUG
        IntervalsAdapter.seedCredentialsFromBundleIfNeeded()
        #endif

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
