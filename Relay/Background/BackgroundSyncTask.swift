//
//  BackgroundSyncTask.swift
//  Relay
//
//  Registers and handles BGAppRefreshTask for background syncing.
//  Also sets up HKObserverQuery for near-realtime HealthKit pickup.
//  Wrapped in #if os(iOS) because BackgroundTasks framework is iOS-only.
//

#if os(iOS)
import Foundation
import BackgroundTasks
import HealthKit

final class BackgroundSyncTask {

    static let shared = BackgroundSyncTask()
    private init() {}

    private let identifier = "com.relay.backgroundSync"
    private let store = HKHealthStore()

    // MARK: - Registration

    func registerHandlers() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            self?.handle(task: task)
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - HealthKit Observer

    func startHealthKitObserver() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            // Trigger a sync on next background opportunity
            self?.scheduleNextRefresh()
            completionHandler()
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, _ in }
    }

    // MARK: - Task handler

    private func handle(task: BGAppRefreshTask) {
        scheduleNextRefresh() // Reschedule before doing work

        let syncTask = Task {
            // Background sync: fetch and persist new workouts
            // Full sync engine requires ModelContainer; post notification for foreground pickup
            NotificationCenter.default.post(name: .relayBackgroundSyncTriggered, object: nil)
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let relayBackgroundSyncTriggered = Notification.Name("relay.backgroundSyncTriggered")
}
#endif
