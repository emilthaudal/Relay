//
//  WorkoutRecord.swift
//  Relay
//
//  SwiftData model for a persisted workout.
//  A WorkoutRecord has one SyncRecord per connection it's been seen on or pushed to.
//

import Foundation
import SwiftData

@Model
final class WorkoutRecord {

    // MARK: - Identity

    var id: UUID
    var startDate: Date
    var duration: TimeInterval          // seconds
    var sportTypeRaw: String            // SportType.rawValue
    var name: String
    var isTrainer: Bool
    var timeZoneID: String?
    var deviceName: String?

    // MARK: - Metrics (all optional)

    var distance: Double?               // meters
    var calories: Int?
    var avgHeartRate: Double?           // bpm
    var maxHeartRate: Double?
    var avgPower: Double?               // watts
    var maxPower: Double?               // watts
    var normalizedPower: Double?        // watts (NP / weighted average power)
    var avgCadence: Double?             // rpm / spm
    var avgSpeed: Double?               // m/s
    var maxSpeed: Double?               // m/s
    var elevationGain: Double?          // meters

    // MARK: - Sync records

    @Relationship(deleteRule: .cascade, inverse: \SyncRecord.workout)
    var syncRecords: [SyncRecord]

    // MARK: - Computed

    var sportType: SportType {
        get { SportType(rawValue: sportTypeRaw) ?? .other }
        set { sportTypeRaw = newValue.rawValue }
    }

    var syncState: SyncState {
        // Worst state wins: failed > uploading > pending > source > synced
        if syncRecords.contains(where: { $0.state == .failed })    { return .failed }
        if syncRecords.contains(where: { $0.state == .uploading }) { return .uploading }
        if syncRecords.contains(where: { $0.state == .pending })   { return .pending }
        return .synced
    }

    var primarySource: ConnectionType? {
        syncRecords.first(where: { $0.isPrimarySource })?.connection
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        startDate: Date,
        duration: TimeInterval,
        sportType: SportType,
        name: String,
        isTrainer: Bool = false
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.sportTypeRaw = sportType.rawValue
        self.name = name
        self.isTrainer = isTrainer
        self.syncRecords = []
    }
}
