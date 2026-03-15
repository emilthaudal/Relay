//
//  HealthKitAdapter.swift
//  Relay
//
//  Adapter for Apple HealthKit. Fetches workouts and writes them back.
//  Requests read+write auth for workouts, active energy, heart rate, and distance.
//

import Foundation
import HealthKit

actor HealthKitAdapter: ConnectionAdapter {

    let connectionType: ConnectionType = .healthKit

    private let store = HKHealthStore()

    // MARK: - Auth

    var isConnected: Bool {
        get async {
            guard HKHealthStore.isHealthDataAvailable() else { return false }
            let status = store.authorizationStatus(for: HKObjectType.workoutType())
            return status == .sharingAuthorized
        }
    }

    func authenticate() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw AdapterError.unavailable("HealthKit is not available on this device")
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming)
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling)
        ]

        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func disconnect() async {
        // HealthKit auth cannot be revoked programmatically; user must do it in Settings
    }

    // MARK: - Fetch

    func fetchWorkouts(since date: Date) async throws -> [NormalizedWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let normalized = workouts.map { $0.toNormalized() }
                continuation.resume(returning: normalized)
            }
            store.execute(query)
        }
    }

    // MARK: - Upload

    func upload(_ workout: NormalizedWorkout) async throws -> String {
        let activityType = workout.sportType.hkActivityType
        let startDate = workout.startDate
        let endDate = startDate.addingTimeInterval(workout.duration)

        var totalEnergy: HKQuantity?
        if let calories = workout.calories {
            totalEnergy = HKQuantity(unit: .kilocalorie(), doubleValue: Double(calories))
        }

        var totalDistance: HKQuantity?
        if let distance = workout.distance {
            totalDistance = HKQuantity(unit: .meter(), doubleValue: distance)
        }

        let builder = HKWorkoutBuilder(healthStore: store, configuration: HKWorkoutConfiguration(), device: .local())
        let config = HKWorkoutConfiguration()
        config.activityType = activityType

        let newBuilder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        try await newBuilder.beginCollection(at: startDate)
        try await newBuilder.endCollection(at: endDate)

        let hkWorkout = try await newBuilder.finishWorkout()

        // Suppress "unused" warning — builder captures are needed for the side effect
        _ = builder
        _ = totalEnergy
        _ = totalDistance

        return hkWorkout.uuid.uuidString
    }
}

// MARK: - HKWorkout → NormalizedWorkout

private extension HKWorkout {
    func toNormalized() -> NormalizedWorkout {
        let calories = statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()
            .map { Int($0.doubleValue(for: .kilocalorie())) }

        let avgHR = statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()
            .map { $0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }

        let maxHR = statistics(for: HKQuantityType(.heartRate))?
            .maximumQuantity()
            .map { $0.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }

        let distanceType: HKQuantityType? = {
            switch workoutActivityType {
            case .cycling: return HKQuantityType(.distanceCycling)
            case .swimming: return HKQuantityType(.distanceSwimming)
            default: return HKQuantityType(.distanceWalkingRunning)
            }
        }()

        let distance = distanceType.flatMap { statistics(for: $0)?.sumQuantity() }
            .map { $0.doubleValue(for: .meter()) }

        return NormalizedWorkout(
            externalID: uuid.uuidString,
            source: .healthKit,
            startDate: startDate,
            duration: duration,
            sportType: workoutActivityType.relaySportType,
            name: metadata?[HKMetadataKeyWorkoutBrandName] as? String ?? workoutActivityType.relaySportType.displayName,
            isTrainer: metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false,
            distance: distance,
            calories: calories ?? nil,
            avgHeartRate: avgHR ?? nil,
            maxHeartRate: maxHR ?? nil
        )
    }
}

// MARK: - SportType → HKWorkoutActivityType

private extension SportType {
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .ride, .mountainBike:   return .cycling
        case .virtualRide:           return .cycling
        case .run:                   return .running
        case .trailRun:              return .running
        case .virtualRun:            return .running
        case .swim:                  return .swimming
        case .openWaterSwim:         return .swimming
        case .walk:                  return .walking
        case .hike:                  return .hiking
        case .yoga:                  return .yoga
        case .rowing:                return .rowing
        case .elliptical:            return .elliptical
        case .workout:               return .traditionalStrengthTraining
        case .hiit:                  return .highIntensityIntervalTraining
        case .triathlon:             return .swimBikeRun
        case .other:                 return .other
        }
    }
}
