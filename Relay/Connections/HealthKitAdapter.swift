//
//  HealthKitAdapter.swift
//  Relay
//
//  Adapter for Apple HealthKit. Fetches workouts and writes them back with full
//  metric coverage. Supports both aggregate (avg/max stats) and time-series upload.
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

        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .heartRate,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .cyclingPower,
            .cyclingCadence,
            .cyclingSpeed,
            .runningPower,
            .runningSpeed,
        ]
        let readTypes: Set<HKObjectType> = Set(quantityTypes.map { HKQuantityType($0) as HKObjectType })
            .union([HKObjectType.workoutType()])
        let writeTypes: Set<HKSampleType> = Set(quantityTypes.map { HKQuantityType($0) as HKSampleType })
            .union([HKObjectType.workoutType()])

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
                continuation.resume(returning: workouts.map { $0.toNormalized() })
            }
            store.execute(query)
        }
    }

    // MARK: - Upload (aggregate stats — single sample per metric spanning full workout)

    func upload(_ workout: NormalizedWorkout) async throws -> String {
        let config = HKWorkoutConfiguration()
        config.activityType = workout.sportType.hkActivityType

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let start = workout.startDate
        let end = start.addingTimeInterval(workout.duration)

        try await builder.beginCollection(at: start)

        let samples = aggregateSamples(for: workout, start: start, end: end)
        if !samples.isEmpty {
            try await addSamples(samples, to: builder)
        }
        try await addMetadata(workoutMetadata(for: workout), to: builder)
        try await builder.endCollection(at: end)
        guard let finished = try await builder.finishWorkout() else {
            throw AdapterError.uploadFailed("finishWorkout returned nil")
        }
        return finished.uuid.uuidString
    }

    // MARK: - Upload with time-series streams

    func uploadWithStreams(_ workout: NormalizedWorkout, streams: ActivityStreams) async throws -> String {
        let config = HKWorkoutConfiguration()
        config.activityType = workout.sportType.hkActivityType

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let start = workout.startDate
        let end = start.addingTimeInterval(workout.duration)

        try await builder.beginCollection(at: start)

        let samples = timeSeriesSamples(from: streams, workout: workout, workoutEnd: end)
        if !samples.isEmpty {
            try await addSamples(samples, to: builder)
        }
        try await addMetadata(workoutMetadata(for: workout), to: builder)
        try await builder.endCollection(at: end)
        guard let finished = try await builder.finishWorkout() else {
            throw AdapterError.uploadFailed("finishWorkout returned nil")
        }
        return finished.uuid.uuidString
    }

    // MARK: - Sample builders

    private func aggregateSamples(for workout: NormalizedWorkout, start: Date, end: Date) -> [HKSample] {
        var samples: [HKSample] = []
        let isCycling = workout.sportType.hkActivityType == .cycling

        if let hr = workout.avgHeartRate {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: hr),
                start: start, end: end
            ))
        }

        if let watts = workout.avgPower {
            let id: HKQuantityTypeIdentifier = isCycling ? .cyclingPower : .runningPower
            samples.append(HKQuantitySample(
                type: HKQuantityType(id),
                quantity: HKQuantity(unit: .watt(), doubleValue: watts),
                start: start, end: end
            ))
        }

        if let rpm = workout.avgCadence, isCycling {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.cyclingCadence),
                quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: rpm),
                start: start, end: end
            ))
        }

        if let speed = workout.avgSpeed {
            let id: HKQuantityTypeIdentifier = isCycling ? .cyclingSpeed : .runningSpeed
            samples.append(HKQuantitySample(
                type: HKQuantityType(id),
                quantity: HKQuantity(unit: .meter().unitDivided(by: .second()), doubleValue: speed),
                start: start, end: end
            ))
        }

        if let meters = workout.distance {
            let distID: HKQuantityTypeIdentifier
            switch workout.sportType.hkActivityType {
            case .cycling:  distID = .distanceCycling
            case .swimming: distID = .distanceSwimming
            default:        distID = .distanceWalkingRunning
            }
            samples.append(HKQuantitySample(
                type: HKQuantityType(distID),
                quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                start: start, end: end
            ))
        }

        if let kcal = workout.calories {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(kcal)),
                start: start, end: end
            ))
        }

        return samples
    }

    private func timeSeriesSamples(from streams: ActivityStreams,
                                   workout: NormalizedWorkout,
                                   workoutEnd: Date) -> [HKSample] {
        var samples: [HKSample] = []
        let base = streams.startDate
        let times = streams.time
        let isCycling = workout.sportType.hkActivityType == .cycling

        // Returns (sampleStart, sampleEnd) for index i
        func window(_ i: Int) -> (Date, Date) {
            let s = base.addingTimeInterval(TimeInterval(times[i]))
            let e = i + 1 < times.count
                ? base.addingTimeInterval(TimeInterval(times[i + 1]))
                : workoutEnd
            return (s, e)
        }

        if let hrs = streams.heartRate {
            let unit = HKUnit.count().unitDivided(by: .minute())
            for i in 0..<min(hrs.count, times.count) {
                let (s, e) = window(i)
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.heartRate),
                    quantity: HKQuantity(unit: unit, doubleValue: Double(hrs[i])),
                    start: s, end: e
                ))
            }
        }

        if let watts = streams.watts {
            let powerID: HKQuantityTypeIdentifier = isCycling ? .cyclingPower : .runningPower
            for i in 0..<min(watts.count, times.count) {
                guard watts[i] > 0 else { continue }  // skip zero-power coasting points
                let (s, e) = window(i)
                samples.append(HKQuantitySample(
                    type: HKQuantityType(powerID),
                    quantity: HKQuantity(unit: .watt(), doubleValue: Double(watts[i])),
                    start: s, end: e
                ))
            }
        }

        if let cadences = streams.cadence, isCycling {
            for i in 0..<min(cadences.count, times.count) {
                let (s, e) = window(i)
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.cyclingCadence),
                    quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: Double(cadences[i])),
                    start: s, end: e
                ))
            }
        }

        if let velocities = streams.velocity {
            let speedID: HKQuantityTypeIdentifier = isCycling ? .cyclingSpeed : .runningSpeed
            for i in 0..<min(velocities.count, times.count) {
                let (s, e) = window(i)
                samples.append(HKQuantitySample(
                    type: HKQuantityType(speedID),
                    quantity: HKQuantity(unit: .meter().unitDivided(by: .second()), doubleValue: velocities[i]),
                    start: s, end: e
                ))
            }
        }

        return samples
    }

    private func workoutMetadata(for workout: NormalizedWorkout) -> [String: Any] {
        var meta: [String: Any] = [HKMetadataKeyIndoorWorkout: workout.isTrainer]
        if let np = workout.normalizedPower {
            meta["NormalizedPower"] = np
        }
        return meta
    }

    // MARK: - HKWorkoutBuilder async wrappers

    private func addSamples(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            builder.add(samples) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            builder.addMetadata(metadata) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
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
            case .cycling:  return HKQuantityType(.distanceCycling)
            case .swimming: return HKQuantityType(.distanceSwimming)
            default:        return HKQuantityType(.distanceWalkingRunning)
            }
        }()
        let distance = distanceType.flatMap { statistics(for: $0)?.sumQuantity() }
            .map { $0.doubleValue(for: .meter()) }

        let isCycling = workoutActivityType == .cycling
        let isRunning = workoutActivityType == .running

        let avgPower: Double?
        let maxPower: Double?
        let avgCadence: Double?
        let avgSpeed: Double?
        let maxSpeed: Double?

        if isCycling {
            avgPower   = statistics(for: HKQuantityType(.cyclingPower))?.averageQuantity()?.doubleValue(for: .watt())
            maxPower   = statistics(for: HKQuantityType(.cyclingPower))?.maximumQuantity()?.doubleValue(for: .watt())
            avgCadence = statistics(for: HKQuantityType(.cyclingCadence))?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min"))
            avgSpeed   = statistics(for: HKQuantityType(.cyclingSpeed))?.averageQuantity()?.doubleValue(for: .meter().unitDivided(by: .second()))
            maxSpeed   = statistics(for: HKQuantityType(.cyclingSpeed))?.maximumQuantity()?.doubleValue(for: .meter().unitDivided(by: .second()))
        } else if isRunning {
            avgPower   = statistics(for: HKQuantityType(.runningPower))?.averageQuantity()?.doubleValue(for: .watt())
            maxPower   = statistics(for: HKQuantityType(.runningPower))?.maximumQuantity()?.doubleValue(for: .watt())
            avgCadence = nil
            avgSpeed   = statistics(for: HKQuantityType(.runningSpeed))?.averageQuantity()?.doubleValue(for: .meter().unitDivided(by: .second()))
            maxSpeed   = statistics(for: HKQuantityType(.runningSpeed))?.maximumQuantity()?.doubleValue(for: .meter().unitDivided(by: .second()))
        } else {
            avgPower = nil; maxPower = nil; avgCadence = nil; avgSpeed = nil; maxSpeed = nil
        }

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
            maxHeartRate: maxHR ?? nil,
            avgPower: avgPower,
            maxPower: maxPower,
            avgCadence: avgCadence,
            avgSpeed: avgSpeed,
            maxSpeed: maxSpeed
        )
    }
}

// MARK: - SportType → HKWorkoutActivityType

private extension SportType {
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .ride, .mountainBike, .virtualRide:    return .cycling
        case .run, .trailRun, .virtualRun:          return .running
        case .swim, .openWaterSwim:                 return .swimming
        case .walk:                                 return .walking
        case .hike:                                 return .hiking
        case .yoga:                                 return .yoga
        case .rowing:                               return .rowing
        case .elliptical:                           return .elliptical
        case .workout:                              return .traditionalStrengthTraining
        case .hiit:                                 return .highIntensityIntervalTraining
        case .triathlon:                            return .swimBikeRun
        case .other:                                return .other
        }
    }
}
