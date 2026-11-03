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
    /// "yyyy-MM" of `startDate`, which sections the workout list by month.
    /// Optional so existing stores migrate; `SyncEngine` fills in older records.
    var monthKey: String?

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
        self.monthKey = Self.monthKey(for: startDate)
        self.syncRecords = []
    }

    // MARK: - Month sections

    static func monthKey(for date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// "October 2026" for "2026-10"; records not yet backfilled have an empty key.
    static func monthTitle(for key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1]))
        else { return "Earlier" }
        return date.formatted(.dateTime.month(.wide).year())
    }
}
