//
//  SyncEngine.swift
//  Relay
//
//  Central orchestrator: fetches workouts from all enabled adapters, clusters/merges them,
//  persists WorkoutRecords + SyncRecords to SwiftData, then uploads to HealthKit.
//  Streams (per-second time-series) are fetched from Intervals.icu and written to
//  HealthKit when available; falls back to aggregate stats if streams are unavailable.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class SyncEngine {

    /// One engine for the whole app, so the list, Settings and the background task
    /// can't run two syncs at once and write the same workout twice.
    static let shared = SyncEngine()

    /// How far before the last sync each sync looks again. Intervals.icu filters by start
    /// date, so a ride that started before the last sync but was uploaded after it would
    /// otherwise be missed.
    static let lookback: TimeInterval = 2 * 24 * 3600

    private(set) var isSyncing = false
    private(set) var lastError: Error?
    /// Intervals.icu activities skipped in the last sync because they were imported from
    /// Strava, whose data the Intervals.icu API doesn't serve.
    private(set) var skippedFromStrava = 0
    /// Workouts saved to Health so far in the running sync, out of how many need saving.
    /// Nil while fetching, and when no sync is running.
    private(set) var progress: SyncProgress?

    struct SyncProgress: Equatable {
        var saved: Int
        var total: Int
    }

    // MARK: - Adapters

    private let healthKit  = HealthKitAdapter()
    private let intervals  = IntervalsAdapter()

    // MARK: - Public API

    func sync(appState: AppState, context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let since = (appState.lastSyncDate ?? Date().addingTimeInterval(-30 * 24 * 3600))
            .addingTimeInterval(-Self.lookback)
        await run(since: since, appState: appState, context: context)
    }

    /// Exports a single workout to the given destination, re-queueing it if previously synced.
    func exportWorkout(record: WorkoutRecord, to destination: ConnectionType, context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        if let existing = record.syncRecords.first(where: { $0.connection == destination }) {
            existing.state = .pending
            existing.errorMessage = nil
        } else {
            let syncRecord = SyncRecord(connection: destination, externalID: "", state: .pending, isPrimarySource: false)
            syncRecord.workout = record
            context.insert(syncRecord)
        }
        try? context.save()

        switch destination {
        case .healthKit:
            await uploadToHealthKit(record: record)
            try? context.save()
        default:
            record.syncRecords.first(where: { $0.connection == destination })?.markFailed(
                error: AdapterError.networkError("Export to \(destination.displayName) is not yet supported")
            )
            try? context.save()
        }
    }

    /// Syncs historical workouts going back `days` days, regardless of last sync date.
    /// `onProgress` gets each change of `progress`, for the system's progress UI.
    func syncHistorical(appState: AppState, context: ModelContext, days: Int,
                        onProgress: ((SyncProgress) -> Void)? = nil) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        await run(since: Date().addingTimeInterval(-Double(days) * 24 * 3600), appState: appState, context: context,
                  onProgress: onProgress)
    }

    // MARK: - Core logic

    private func run(since: Date, appState: AppState, context: ModelContext,
                     onProgress: ((SyncProgress) -> Void)? = nil) async {
        defer { progress = nil }
        do {
            try await performSync(since: since, appState: appState, context: context) { [weak self] update in
                self?.progress = update
                onProgress?(update)
            }
            appState.lastSyncDate = Date()
            try? context.save()
        } catch {
            // A cancelled sync is the background task running out of time, not a failure;
            // the next sync picks up where this one stopped.
            if !Task.isCancelled { lastError = error }
        }
    }

    private func performSync(since: Date, appState: AppState, context: ModelContext,
                             report: (SyncProgress) -> Void) async throws {
        // 1. Fetch from all enabled adapters
        var allWorkouts: [NormalizedWorkout] = []
        var fetchErrors: [String] = []
        for connection in appState.enabledConnections {
            let adapter: (any ConnectionAdapter)? = switch connection {
            case .healthKit:  healthKit
            case .intervals:  intervals
            case .hammerhead: nil
            }
            guard let adapter else { continue }
            do {
                let fetched = try await adapter.fetchWorkouts(since: since)
                allWorkouts.append(contentsOf: fetched)
                if connection == .intervals {
                    skippedFromStrava = await intervals.lastSkippedFromStrava
                }
            } catch {
                print("[SyncEngine] fetch failed for \(connection.displayName): \(error)")
                fetchErrors.append("\(connection.displayName): \(error.localizedDescription)")
                // Without Health's workouts, matching can't see what's already there, and
                // uploading could write duplicates. Stop before persisting anything.
                if connection == .healthKit {
                    throw AdapterError.fetchFailed(fetchErrors.joined(separator: "\n"))
                }
            }
        }

        // 2. Cluster into matched groups and persist
        let clusters = WorkoutMatcher.cluster(allWorkouts)
        for cluster in clusters {
            upsert(cluster: cluster, appState: appState, into: context)
        }
        try context.save()

        // 3. Upload to HealthKit for any workout that's still pending there
        guard appState.enabledConnections.contains(.healthKit),
              appState.autoSyncToHealthKit else { return }

        let allRecords = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        let pendingForHK = allRecords.filter { record in
            record.syncRecords.contains { $0.connection == .healthKit && $0.state == .pending }
        }

        report(SyncProgress(saved: 0, total: pendingForHK.count))
        for (index, record) in pendingForHK.enumerated() {
            try Task.checkCancellation()
            await uploadToHealthKit(record: record)
            try? context.save()
            report(SyncProgress(saved: index + 1, total: pendingForHK.count))
        }

        if !fetchErrors.isEmpty {
            throw AdapterError.fetchFailed(fetchErrors.joined(separator: "\n"))
        }
    }

    // MARK: - HealthKit upload

    private func uploadToHealthKit(record: WorkoutRecord) async {
        let workout = record.toNormalized()
        guard let hkSync = record.syncRecords.first(where: { $0.connection == .healthKit }) else { return }

        hkSync.state = .uploading

        do {
            let hkID: String

            // Prefer time-series streams from the primary source
            if let sourceSync = record.syncRecords.first(where: { $0.isPrimarySource && $0.connection != .healthKit }),
               let streams = await fetchStreams(connection: sourceSync.connection,
                                               activityID: sourceSync.externalID,
                                               startDate: workout.startDate) {
                print("[SyncEngine] Uploading \"\(record.name)\" to HealthKit with \(streams.time.count) stream samples")
                hkID = try await healthKit.uploadWithStreams(workout, streams: streams)
            } else {
                print("[SyncEngine] Uploading \"\(record.name)\" to HealthKit with aggregate stats (streams unavailable)")
                hkID = try await healthKit.upload(workout)
            }

            hkSync.externalID = hkID
            hkSync.markSynced()
        } catch {
            hkSync.markFailed(error: error)
            print("[SyncEngine] HealthKit upload failed for \"\(record.name)\": \(error)")
        }
    }

    private func fetchStreams(connection: ConnectionType,
                              activityID: String,
                              startDate: Date) async -> ActivityStreams? {
        switch connection {
        case .intervals:
            do {
                let s = try await intervals.fetchStreams(activityID: activityID, startDate: startDate)
                print("[SyncEngine] Intervals.icu streams OK: \(s.time.count) samples")
                return s
            } catch {
                print("[SyncEngine] Intervals.icu streams failed: \(error)")
                return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Persistence

    func upsert(cluster: [NormalizedWorkout],
                appState: AppState,
                into context: ModelContext) {
        let orderedSources = SourcePriorityResolver.orderedSources(
            for: cluster.first!.sportType,
            appState: appState
        )
        let merged = WorkoutMerger.merge(cluster, orderedSources: orderedSources)

        // Look up by matching any external ID in the cluster (stable across fetches)
        let existing = (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        let record = existing.first(where: { existingRecord in
            existingRecord.syncRecords.contains { sr in
                cluster.contains { w in w.source == sr.connection && w.externalID == sr.externalID }
            }
        }) ?? {
            let r = WorkoutRecord(
                id: merged.id,
                startDate: merged.startDate,
                duration: merged.duration,
                sportType: merged.sportType,
                name: merged.name,
                isTrainer: merged.isTrainer
            )
            context.insert(r)
            return r
        }()

        // Update all metrics (higher-priority source may have richer data now)
        record.timeZoneID      = merged.timeZone?.identifier
        record.deviceName      = merged.deviceName
        record.distance        = merged.distance
        record.calories        = merged.calories
        record.avgHeartRate    = merged.avgHeartRate
        record.maxHeartRate    = merged.maxHeartRate
        record.avgPower        = merged.avgPower
        record.maxPower        = merged.maxPower
        record.normalizedPower = merged.normalizedPower
        record.avgCadence      = merged.avgCadence
        record.avgSpeed        = merged.avgSpeed
        record.maxSpeed        = merged.maxSpeed
        record.elevationGain   = merged.elevationGain

        // Upsert SyncRecords for each source in the cluster
        for workout in cluster {
            if !record.syncRecords.contains(where: { $0.connection == workout.source }) {
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

        // Create a pending SyncRecord for HealthKit if not present
        if appState.enabledConnections.contains(.healthKit),
           !record.syncRecords.contains(where: { $0.connection == .healthKit }) {
            let syncRecord = SyncRecord(
                connection: .healthKit,
                externalID: "",
                state: .pending,
                isPrimarySource: false
            )
            syncRecord.workout = record
            context.insert(syncRecord)
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
            timeZone: timeZoneID.flatMap(TimeZone.init(identifier:)),
            deviceName: deviceName,
            distance: distance,
            calories: calories,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            avgPower: avgPower,
            maxPower: maxPower,
            normalizedPower: normalizedPower,
            avgCadence: avgCadence,
            avgSpeed: avgSpeed,
            maxSpeed: maxSpeed,
            elevationGain: elevationGain
        )
    }
}
