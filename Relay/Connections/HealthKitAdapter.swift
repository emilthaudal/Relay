//
//  HealthKitAdapter.swift
//  Relay
//
//  Adapter for Apple HealthKit. Fetches workouts and writes them back with full
//  metric coverage. Supports both aggregate (avg/max stats) and time-series upload.
//

import CoreLocation
import Foundation
@preconcurrency import HealthKit

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
            .union([HKObjectType.workoutType(), HKSeriesType.workoutRoute()])
        let writeTypes: Set<HKSampleType> = Set(quantityTypes.map { HKQuantityType($0) as HKSampleType })
            .union([HKObjectType.workoutType(), HKSeriesType.workoutRoute()])

        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func disconnect() async {
        // HealthKit auth cannot be revoked programmatically; user must do it in Settings
    }

    // MARK: - Fetch

    func fetchWorkouts(since date: Date) async throws -> [NormalizedWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let hkWorkouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
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
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        var workouts = hkWorkouts.map { $0.toNormalized() }
        for i in workouts.indices {
            if let gain = await elevationGain(for: hkWorkouts[i]) {
                workouts[i].elevationGain = gain
            }
        }
        return workouts
    }

    // MARK: - Elevation via GPS route

    private func elevationGain(for workout: HKWorkout) async -> Double? {
        let routes: [HKWorkoutRoute]
        do {
            routes = try await withCheckedThrowingContinuation { continuation in
                let predicate = HKQuery.predicateForObjects(from: workout)
                let query = HKSampleQuery(
                    sampleType: HKSeriesType.workoutRoute(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? []) }
                }
                store.execute(query)
            }
        } catch {
            return nil
        }

        guard !routes.isEmpty else { return nil }

        var totalGain = 0.0
        for route in routes {
            guard let locations = try? await routeLocations(for: route), locations.count > 1 else { continue }
            var prev = locations[0].altitude
            for loc in locations.dropFirst() {
                let delta = loc.altitude - prev
                if delta > 0 { totalGain += delta }
                prev = loc.altitude
            }
        }

        return totalGain > 0 ? totalGain : nil
    }

    private func routeLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var collected: [CLLocation] = []
            var resumed = false
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    continuation.resume(throwing: error)
                    return
                }
                if let locs = locations { collected.append(contentsOf: locs) }
                if done {
                    resumed = true
                    continuation.resume(returning: collected)
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Upload (aggregate stats — single sample per metric spanning full workout)

    func upload(_ workout: NormalizedWorkout) async throws -> String {
        let end = workout.startDate.addingTimeInterval(workout.duration)
        let samples = aggregateSamples(for: workout, start: workout.startDate, end: end)
        return try await save(workout, samples: samples, events: [], locations: [])
    }

    // MARK: - Upload with time-series streams

    func uploadWithStreams(_ workout: NormalizedWorkout, streams: ActivityStreams) async throws -> String {
        let end = workout.startDate.addingTimeInterval(workout.duration)
        let series = HealthKitSeries(streams: streams, workout: workout, workoutEnd: end)
        return try await save(workout, samples: series.samples(), events: series.lapEvents(), locations: series.locations())
    }

    private func save(_ workout: NormalizedWorkout,
                      samples: [HKSample],
                      events: [HKWorkoutEvent],
                      locations: [CLLocation]) async throws -> String {
        let config = HKWorkoutConfiguration()
        config.activityType = workout.sportType.hkActivityType
        config.locationType = workout.isTrainer ? .indoor : .outdoor

        let device = HKDevice(name: workout.deviceName ?? "Intervals.icu", manufacturer: nil, model: nil,
                              hardwareVersion: nil, firmwareVersion: nil, softwareVersion: nil,
                              localIdentifier: nil, udiDeviceIdentifier: nil)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: device)
        let start = workout.startDate
        let end = start.addingTimeInterval(workout.duration)

        try await builder.beginCollection(at: start)
        var chunkStart = 0
        while chunkStart < samples.count {
            let chunkEnd = min(chunkStart + 5_000, samples.count)
            try await addSamples(Array(samples[chunkStart..<chunkEnd]), to: builder)
            chunkStart = chunkEnd
        }
        if !events.isEmpty {
            try await addEvents(events, to: builder)
        }
        try await addMetadata(workoutMetadata(for: workout), to: builder)
        try await builder.endCollection(at: end)
        guard let finished = try await builder.finishWorkout() else {
            throw AdapterError.uploadFailed("finishWorkout returned nil")
        }

        // A route failure must not fail the upload, or a retry would duplicate the saved workout.
        if !locations.isEmpty {
            do {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: device)
                try await routeBuilder.insertRouteData(locations)
                try await routeBuilder.finishRoute(with: finished, metadata: nil)
            } catch {
                print("[HealthKitAdapter] Route save failed for \(finished.uuid): \(error)")
            }
        }

        print("[HealthKitAdapter] Saved \(finished.uuid): \(samples.count) samples, \(events.count) laps, \(locations.count) route points")
        return finished.uuid.uuidString
    }

    // MARK: - Sample builders

    private func aggregateSamples(for workout: NormalizedWorkout, start: Date, end: Date) -> [HKSample] {
        var samples: [HKSample] = []
        let isCycling = workout.sportType.isCycling

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
            samples.append(HKQuantitySample(
                type: HKQuantityType(workout.sportType.hkDistanceType),
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

    private func workoutMetadata(for workout: NormalizedWorkout) -> [String: Any] {
        var meta: [String: Any] = [
            HKMetadataKeyIndoorWorkout: workout.isTrainer,
            HKMetadataKeyExternalUUID: "\(workout.source.rawValue):\(workout.externalID)",
            "RelayWorkoutName": workout.name,
        ]
        if let timeZone = workout.timeZone {
            meta[HKMetadataKeyTimeZone] = timeZone.identifier
        }
        if let np = workout.normalizedPower {
            meta["NormalizedPower"] = np
        }
        if let maxHR = workout.maxHeartRate {
            meta["MaxHeartRate"] = maxHR
        }
        let speedUnit = HKUnit.meter().unitDivided(by: .second())
        if let avgSpeed = workout.avgSpeed {
            meta[HKMetadataKeyAverageSpeed] = HKQuantity(unit: speedUnit, doubleValue: avgSpeed)
        }
        if let maxSpeed = workout.maxSpeed {
            meta[HKMetadataKeyMaximumSpeed] = HKQuantity(unit: speedUnit, doubleValue: maxSpeed)
        }
        if let elevation = workout.elevationGain {
            meta[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: elevation)
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

    private func addEvents(_ events: [HKWorkoutEvent], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            builder.addWorkoutEvents(events) { _, error in
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
    nonisolated func toNormalized() -> NormalizedWorkout {
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

// MARK: - HKWorkoutActivityType → SportType

extension HKWorkoutActivityType {
    nonisolated var relaySportType: SportType {
        switch self {
        case .cycling:                   return .ride
        case .running:                   return .run
        case .swimming:                  return .swim
        case .walking:                   return .walk
        case .hiking:                    return .hike
        case .yoga:                      return .yoga
        case .rowing:                    return .rowing
        case .elliptical:                return .elliptical
        case .crossTraining, .functionalStrengthTraining,
             .traditionalStrengthTraining:  return .workout
        case .highIntensityIntervalTraining: return .hiit
        default:                         return .other
        }
    }

    nonisolated var relayDisplayName: String {
        relaySportType.displayName
    }
}

// MARK: - SportType → HealthKit types

extension SportType {
    nonisolated var isCycling: Bool {
        [.ride, .mountainBike, .virtualRide].contains(self)
    }

    nonisolated var hkDistanceType: HKQuantityTypeIdentifier {
        switch self {
        case .ride, .virtualRide, .mountainBike: return .distanceCycling
        case .swim, .openWaterSwim:              return .distanceSwimming
        default:                                  return .distanceWalkingRunning
        }
    }

    nonisolated var hkActivityType: HKWorkoutActivityType {
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
