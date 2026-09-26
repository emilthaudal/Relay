//
//  HealthKitSeries.swift
//  Relay
//
//  Converts per-second activity streams into the HealthKit samples, lap events and
//  route locations that make up a full-fidelity workout.
//

import CoreLocation
import Foundation
@preconcurrency import HealthKit

nonisolated struct HealthKitSeries {
    let streams: ActivityStreams
    let workout: NormalizedWorkout
    let workoutEnd: Date

    /// Cumulative quantities (distance, energy) are written in buckets of this many stream points.
    static let bucketSize = 10

    private var count: Int { streams.time.count }

    func samples() -> [HKSample] {
        discreteSamples() + distanceSamples() + energySamples()
    }

    // MARK: - Discrete quantities (one sample per stream point)

    private func discreteSamples() -> [HKSample] {
        let isCycling = workout.sportType.isCycling
        let isRunning = [.run, .trailRun, .virtualRun].contains(workout.sportType)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let metersPerSecond = HKUnit.meter().unitDivided(by: .second())

        var series: [([Double?], HKQuantityTypeIdentifier, HKUnit, ClosedRange<Double>)] = []
        if let hr = streams.heartRate {
            series.append((hr, .heartRate, bpm, 1...300))
        }
        if let watts = streams.watts, isCycling || isRunning {
            series.append((watts, isCycling ? .cyclingPower : .runningPower, .watt(), 0...3000))
        }
        if let cadence = streams.cadence, isCycling {
            series.append((cadence, .cyclingCadence, bpm, 0...300))
        }
        if let velocity = streams.velocity, isCycling || isRunning {
            series.append((velocity, isCycling ? .cyclingSpeed : .runningSpeed, metersPerSecond, 0...50))
        }

        var samples: [HKSample] = []
        for (values, identifier, unit, validRange) in series {
            let type = HKQuantityType(identifier)
            for i in 0..<min(values.count, count) {
                guard let value = values[i], validRange.contains(value), let interval = pointInterval(i) else { continue }
                samples.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: interval.start, end: interval.end
                ))
            }
        }
        return samples
    }

    private func pointInterval(_ i: Int) -> DateInterval? {
        let start = date(at: i)
        let end = min(start.addingTimeInterval(1), workoutEnd)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    // MARK: - Cumulative quantities (bucketed)

    private func distanceSamples() -> [HKSample] {
        guard let distance = streams.distance else { return [] }
        let cumulative = forwardFilled(distance)
        let type = HKQuantityType(workout.sportType.hkDistanceType)

        return buckets().compactMap { bucket in
            let meters = cumulative[bucket.upperBound] - cumulative[bucket.lowerBound]
            guard meters > 0, let interval = bucketInterval(bucket) else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                                    start: interval.start, end: interval.end)
        }
    }

    /// Spreads the workout's total calories across the ride, weighted by power when available.
    private func energySamples() -> [HKSample] {
        guard let total = workout.calories, total > 0, count > 1 else { return [] }
        let buckets = buckets()
        let powerWeights = streams.watts.map { watts in
            buckets.map { b in b.dropLast().reduce(0.0) { $0 + max((watts[safe: $1] ?? nil) ?? 0, 0) } }
        }
        let durations = buckets.map { Double(streams.time[$0.upperBound] - streams.time[$0.lowerBound]) }
        let weights = powerWeights.flatMap { $0.reduce(0, +) > 0 ? $0 : nil } ?? durations
        let weightSum = weights.reduce(0, +)
        guard weightSum > 0 else { return [] }

        let type = HKQuantityType(.activeEnergyBurned)
        return zip(buckets, weights).compactMap { bucket, weight in
            let kcal = Double(total) * weight / weightSum
            guard kcal > 0, let interval = bucketInterval(bucket) else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                    start: interval.start, end: interval.end)
        }
    }

    /// Index ranges `[a, b]` covering the stream, where each bucket's end is the next one's start.
    private func buckets() -> [ClosedRange<Int>] {
        guard count > 1 else { return [] }
        return stride(from: 0, to: count - 1, by: Self.bucketSize).map { a in
            a...min(a + Self.bucketSize, count - 1)
        }
    }

    private func bucketInterval(_ bucket: ClosedRange<Int>) -> DateInterval? {
        let start = date(at: bucket.lowerBound)
        let end = min(date(at: bucket.upperBound), workoutEnd)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func forwardFilled(_ values: [Double?]) -> [Double] {
        var last = 0.0
        return (0..<count).map { i in
            if let v = values[safe: i] ?? nil { last = v }
            return last
        }
    }

    // MARK: - Laps

    func lapEvents() -> [HKWorkoutEvent] {
        streams.laps.compactMap { lap in
            let start = streams.startDate.addingTimeInterval(TimeInterval(lap.start))
            let end = min(streams.startDate.addingTimeInterval(TimeInterval(lap.end)), workoutEnd)
            guard end > start else { return nil }
            return HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start, end: end), metadata: nil)
        }
    }

    // MARK: - Route

    /// Indoor workouts get no route: virtual worlds report fictional coordinates.
    func locations() -> [CLLocation] {
        guard !workout.isTrainer, let lats = streams.latitude, let lngs = streams.longitude else { return [] }
        return (0..<min(lats.count, lngs.count, count)).compactMap { i in
            guard let lat = lats[i], let lng = lngs[i],
                  (-90...90).contains(lat), (-180...180).contains(lng), lat != 0 || lng != 0
            else { return nil }
            let altitude = streams.altitude?[safe: i] ?? nil
            let speed = streams.velocity?[safe: i] ?? nil
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                altitude: altitude ?? 0,
                horizontalAccuracy: 5,
                verticalAccuracy: altitude == nil ? -1 : 5,
                course: -1,
                speed: speed ?? -1,
                timestamp: date(at: i)
            )
        }
    }

    private func date(at i: Int) -> Date {
        streams.startDate.addingTimeInterval(TimeInterval(streams.time[i]))
    }
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
