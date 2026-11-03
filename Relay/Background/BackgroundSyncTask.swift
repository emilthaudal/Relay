//
//  BackgroundSyncTask.swift
//  Relay
//
//  Registers and handles the BGAppRefreshTask that syncs while Relay isn't open.
//  The identifier must be listed under BGTaskSchedulerPermittedIdentifiers in
//  Config/Relay-Info.plist, and UIBackgroundModes must include "fetch".
//

#if os(iOS)
import BackgroundTasks
import Foundation
import SwiftData

final class BackgroundSyncTask {

    static let shared = BackgroundSyncTask()
    private init() {}

    static let identifier = "emtb.Relay.refresh"

    /// iOS decides when the task actually runs; this is only the earliest time.
    private let minimumInterval: TimeInterval = 30 * 60

    private var container: ModelContainer?

    // MARK: - Registration

    /// Must run before the app finishes launching.
    func registerHandlers(container: ModelContainer) {
        self.container = container
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                BackgroundSyncTask.shared.handle(task: task)
            }
        }
        if !registered {
            print("[BackgroundSyncTask] \(Self.identifier) isn't in BGTaskSchedulerPermittedIdentifiers")
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Fails in the simulator and when Background App Refresh is off.
            print("[BackgroundSyncTask] Couldn't schedule refresh: \(error)")
        }
    }

    // MARK: - Task handler

    private func handle(task: BGAppRefreshTask) {
        scheduleNextRefresh()

        guard let container else {
            task.setTaskCompleted(success: false)
            return
        }

        let syncTask = Task { @MainActor in
            let context = container.mainContext
            guard let appState = try? context.fetch(FetchDescriptor<AppState>()).first,
                  appState.onboardingCompleted
            else { return true }
            let engine = SyncEngine.shared
            await engine.sync(appState: appState, context: context)
            return engine.lastError == nil
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task { @MainActor in
            let success = await syncTask.value
            task.setTaskCompleted(success: success && !syncTask.isCancelled)
        }
    }
}
#endif
