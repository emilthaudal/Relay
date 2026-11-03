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
    /// Permitted as `emtb.Relay.historical.*`; each historical sync submits its own ID under it.
    static let historicalPrefix = "emtb.Relay.historical"

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

    // MARK: - Historical sync

    /// Runs a historical sync as a BGContinuedProcessingTask, so it keeps going after the user
    /// leaves the app, with iOS showing its progress as a Live Activity. Falls back to an
    /// in-app sync when iOS won't start the task.
    func startHistoricalSync(days: Int, label: String, appState: AppState, context: ModelContext) {
        guard !SyncEngine.shared.isSyncing else { return }

        // Continued-processing tasks may register after launch. Each ID is registered once.
        let identifier = "\(Self.historicalPrefix).\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                BackgroundSyncTask.shared.runHistorical(task: task, days: days)
            }
        }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                       title: "Syncing workouts",
                                                       subtitle: label)
        // Start now or not at all: the user is waiting, and a queued request would surprise them later.
        request.strategy = .fail
        do {
            guard registered else { throw BGTaskScheduler.Error(.notPermitted) }
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundSyncTask] Continued processing unavailable (\(error)); syncing in the app")
            Task { await SyncEngine.shared.syncHistorical(appState: appState, context: context, days: days) }
        }
    }

    private func runHistorical(task: BGContinuedProcessingTask, days: Int) {
        guard let container,
              let appState = try? container.mainContext.fetch(FetchDescriptor<AppState>()).first
        else {
            task.setTaskCompleted(success: false)
            return
        }

        // Fetching comes first and counts as one unit, so the progress never looks stalled at zero.
        task.progress.totalUnitCount = 1
        task.progress.completedUnitCount = 0

        let work = Task { @MainActor in
            let engine = SyncEngine.shared
            await engine.syncHistorical(appState: appState, context: container.mainContext, days: days) { update in
                task.progress.totalUnitCount = Int64(update.total + 1)
                task.progress.completedUnitCount = Int64(update.saved + 1)
                let subtitle = update.total == 0
                    ? "Everything is already in Apple Health"
                    : "\(update.saved) of \(update.total) saved to Apple Health"
                task.updateTitle(task.title, subtitle: subtitle)
            }
            return engine.lastError == nil
        }

        task.expirationHandler = {
            work.cancel()
        }

        Task { @MainActor in
            let success = await work.value
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.setTaskCompleted(success: success && !work.isCancelled)
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
