//
//  SyncEngine.swift
//  Relay
//
//  Central orchestrator: fetches workouts from all enabled adapters, clusters/merges them,
//  persists WorkoutRecords + SyncRecords to SwiftData, then uploads to any connections
//  that are missing the workout.
//

import Foundation
import SwiftData

@MainActor
final class SyncEngine: ObservableObject {

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: Error?

    // MARK: - Adapters

    private let healthKit  = HealthKitAdapter()
    private let strava     = StravaAdapter()
    private let intervals  = IntervalsAdapter()

    private func adapter(for type: ConnectionType) -> (any ConnectionAdapter)? {
        switch type {
        case .healthKit:  return healthKit
        case .strava:     return strava
        case .intervals:  return intervals
        case .hammerhead: return nil
        }
    }

    // MARK: - Public API

    func sync(appState: AppState) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            try await performSync(appState: appState)
            lastSyncDate = Date()
        } catch {
            lastError = error
        }
    }

    // MARK: - Core logic

    private func performSync(appState: AppState) async throws {
        let since = lastSyncDate ?? Date().addingTimeInterval(-30 * 24 * 3600) // default: 30 days back

        // 1. Fetch from all enabled adapters
        var allWorkouts: [NormalizedWorkout] = []
        for connection in appState.enabledConnections {
            guard let adapter = adapter(for: connection) else { continue }
            do {
                let fetched = try await adapter.fetchWorkouts(since: since)
                allWorkouts.append(contentsOf: fetched)
            } catch {
                // Log but continue — partial fetch is better than full failure
                print("[SyncEngine] fetch failed for \(connection.displayName): \(error)")
            }
        }

        // 2. Cluster into matched groups
        let clusters = WorkoutMatcher.cluster(allWorkouts)

        // 3. For each cluster, determine primary source + merge
        // (Caller passes a ModelContext via environment — we'll receive it via the view layer.
        //  SyncEngine itself is model-context-agnostic for testability.)
    }

    // MARK: - Persistence helpers (called from views that have modelContext)

    func upsert(cluster: [NormalizedWorkout],
                appState: AppState,
                into context: ModelContext) {
        let orderedSources = SourcePriorityResolver.orderedSources(
            for: cluster.first!.sportType,
            appState: appState
        )
        let merged = WorkoutMerger.merge(cluster, orderedSources: orderedSources)

        // Check for existing record
        let descriptor = FetchDescriptor<WorkoutRecord>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let record = existing.first(where: { $0.id == merged.id }) ?? {
            let r = WorkoutRecord(
                id: merged.id,
                startDate: merged.startDate,
                duration: merged.duration,
                sportType: merged.sportType,
                name: merged.name,
                isTrainer: merged.isTrainer
            )
            r.distance = merged.distance
            r.calories = merged.calories
            r.avgHeartRate = merged.avgHeartRate
            r.maxHeartRate = merged.maxHeartRate
            r.avgPower = merged.avgPower
            r.avgCadence = merged.avgCadence
            r.avgSpeed = merged.avgSpeed
            r.elevationGain = merged.elevationGain
            context.insert(r)
            return r
        }()

        // Upsert SyncRecords for each source in the cluster
        for workout in cluster {
            let existingSync = record.syncRecords.first { $0.connection == workout.source }
            if existingSync == nil {
                let isPrimary = workout.source == orderedSources.first
                let syncRecord = SyncRecord(
                    connection: workout.source,
                    externalID: workout.externalID,
                    state: .source,
                    isPrimarySource: isPrimary
                )
                syncRecord.workout = record
                context.insert(syncRecord)
            }
        }

        // Create pending SyncRecords for connections that don't have the workout yet
        for connection in appState.enabledConnections {
            let alreadyHas = record.syncRecords.contains { $0.connection == connection }
            if !alreadyHas {
                let syncRecord = SyncRecord(
                    connection: connection,
                    externalID: "",
                    state: .pending,
                    isPrimarySource: false
                )
                syncRecord.workout = record
                context.insert(syncRecord)
            }
        }
    }
}

// MARK: - WorkoutRecord convenience

extension WorkoutRecord {
    func toNormalized() -> NormalizedWorkout {
        NormalizedWorkout(
            id: id,
            externalID: syncRecords.first(where: { $0.isPrimarySource })?.externalID ?? id.uuidString,
            source: syncRecords.first(where: { $0.isPrimarySource })?.connection ?? .healthKit,
            startDate: startDate,
            duration: duration,
            sportType: sportType,
            name: name,
            isTrainer: isTrainer,
            distance: distance,
            calories: calories,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            avgPower: avgPower,
            avgCadence: avgCadence,
            avgSpeed: avgSpeed,
            elevationGain: elevationGain
        )
    }
}
