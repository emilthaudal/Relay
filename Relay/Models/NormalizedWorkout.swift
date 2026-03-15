//
//  NormalizedWorkout.swift
//  Relay
//
//  A platform-agnostic workout representation used by the matching/merging engine.
//  Adapters convert their native types to NormalizedWorkout before handing off to SyncEngine.
//

import Foundation

struct NormalizedWorkout: Identifiable {
    let id: UUID
    let externalID: String          // Platform-specific ID
    let source: ConnectionType
    let startDate: Date
    let duration: TimeInterval      // seconds
    let sportType: SportType
    let name: String                // non-optional; adapters supply a fallback
    let isTrainer: Bool

    // Optional metrics
    var distance: Double?           // meters
    var calories: Int?
    var avgHeartRate: Double?       // bpm
    var maxHeartRate: Double?
    var avgPower: Double?           // watts
    var maxPower: Double?           // watts
    var normalizedPower: Double?    // watts (NP / weighted average power)
    var avgCadence: Double?         // rpm / spm
    var avgSpeed: Double?           // m/s
    var maxSpeed: Double?           // m/s
    var elevationGain: Double?      // meters

    init(
        id: UUID = UUID(),
        externalID: String,
        source: ConnectionType,
        startDate: Date,
        duration: TimeInterval,
        sportType: SportType,
        name: String,
        isTrainer: Bool = false,
        distance: Double? = nil,
        calories: Int? = nil,
        avgHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        avgPower: Double? = nil,
        maxPower: Double? = nil,
        normalizedPower: Double? = nil,
        avgCadence: Double? = nil,
        avgSpeed: Double? = nil,
        maxSpeed: Double? = nil,
        elevationGain: Double? = nil
    ) {
        self.id = id
        self.externalID = externalID
        self.source = source
        self.startDate = startDate
        self.duration = duration
        self.sportType = sportType
        self.name = name
        self.isTrainer = isTrainer
        self.distance = distance
        self.calories = calories
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.avgPower = avgPower
        self.maxPower = maxPower
        self.normalizedPower = normalizedPower
        self.avgCadence = avgCadence
        self.avgSpeed = avgSpeed
        self.maxSpeed = maxSpeed
        self.elevationGain = elevationGain
    }
}
