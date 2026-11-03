//
//  HealthInspector.swift
//  Relay
//
//  Debug builds only. Reads back everything Apple Health holds for a workout, whichever
//  app wrote it, so Relay's copy of an activity can be compared point by point with
//  another app's (RunGap, the Intervals.icu app, Apple Watch).
//

#if DEBUG
import Foundation
@preconcurrency import HealthKit

/// A quantity type the inspector reads, with the unit it reports in.
struct InspectedType: Identifiable {
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let label: String
    let unitLabel: String

    var id: String { identifier.rawValue }
    var type: HKQuantityType { HKQuantityType(identifier) }

    /// Every type a workout app is likely to write, including ones Relay doesn't write yet,
    /// so gaps show up in the comparison.
    static let all: [InspectedType] = [
        .init(identifier: .heartRate, unit: .count().unitDivided(by: .minute()), label: "Heart rate", unitLabel: "bpm"),
        .init(identifier: .activeEnergyBurned, unit: .kilocalorie(), label: "Active energy", unitLabel: "kcal"),
        .init(identifier: .basalEnergyBurned, unit: .kilocalorie(), label: "Resting energy", unitLabel: "kcal"),
        .init(identifier: .distanceCycling, unit: .meter(), label: "Distance (cycling)", unitLabel: "m"),
        .init(identifier: .distanceWalkingRunning, unit: .meter(), label: "Distance (walk/run)", unitLabel: "m"),
        .init(identifier: .distanceSwimming, unit: .meter(), label: "Distance (swim)", unitLabel: "m"),
        .init(identifier: .cyclingPower, unit: .watt(), label: "Cycling power", unitLabel: "W"),
        .init(identifier: .cyclingCadence, unit: .count().unitDivided(by: .minute()), label: "Cycling cadence", unitLabel: "rpm"),
        .init(identifier: .cyclingSpeed, unit: .meter().unitDivided(by: .second()), label: "Cycling speed", unitLabel: "m/s"),
        .init(identifier: .runningPower, unit: .watt(), label: "Running power", unitLabel: "W"),
        .init(identifier: .runningSpeed, unit: .meter().unitDivided(by: .second()), label: "Running speed", unitLabel: "m/s"),
        .init(identifier: .runningStrideLength, unit: .meter(), label: "Stride length", unitLabel: "m"),
        .init(identifier: .runningVerticalOscillation, unit: .meterUnit(with: .centi), label: "Vertical oscillation", unitLabel: "cm"),
        .init(identifier: .runningGroundContactTime, unit: .secondUnit(with: .milli), label: "Ground contact", unitLabel: "ms"),
        .init(identifier: .stepCount, unit: .count(), label: "Steps", unitLabel: "steps"),
        .init(identifier: .swimmingStrokeCount, unit: .count(), label: "Swim strokes", unitLabel: "strokes"),
        .init(identifier: .flightsClimbed, unit: .count(), label: "Flights climbed", unitLabel: "floors"),
    ]
}

/// What Health holds for one quantity type within a workout.
struct SeriesStats: Codable, Equatable {
    /// HealthKit samples. One sample can hold many points (series samples), so compare `points`.
    var samples: Int
    var points: Int
    var first: Date?
    var last: Date?
    var min: Double?
    var max: Double?
    var mean: Double?
    var sum: Double?
    /// Median seconds between consecutive sample starts: 1 means per-second data.
    var medianSpacing: Double?
}

struct WorkoutReport: Codable, Identifiable {
    var id: UUID
    var sourceName: String
    var bundleID: String
    var device: String?
    var activityType: UInt
    var start: Date
    var end: Date
    var duration: Double
    var laps: Int
    var segments: Int
    var otherEvents: Int
    var activities: Int
    var routes: Int
    var routePoints: Int
    var metadata: [String: String]
    /// The workout's own statistics: sum for cumulative types, average for the rest.
    var statistics: [String: Double]
    /// Samples associated with the workout (`HKWorkoutBuilder.add`).
    var linked: [String: SeriesStats]
    /// Samples from the same app inside the workout's time range, associated or not.
    /// Some apps save samples without associating them with the workout.
    var sameSourceInWindow: [String: SeriesStats]
}

final class HealthInspector {

    private let store = HKHealthStore()

    /// Read access for every inspected type. Debug builds only, so it can ask for more than Relay ships with.
    func requestAccess() async throws {
        var read: Set<HKObjectType> = Set(InspectedType.all.map { $0.type as HKObjectType })
        read.insert(HKObjectType.workoutType())
        read.insert(HKSeriesType.workoutRoute())
        try await store.requestAuthorization(toShare: [], read: read)
    }

    func workouts(on day: Date) async throws -> [HKWorkout] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(predicates: [.workout(predicate)],
                                                 sortDescriptors: [SortDescriptor(\.startDate)])
        return try await descriptor.result(for: store)
    }

    func report(for workout: HKWorkout) async throws -> WorkoutReport {
        let linkedPredicate = HKQuery.predicateForObjects(from: workout)
        let windowPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: [workout.sourceRevision.source]),
            HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate),
        ])

        var linked: [String: SeriesStats] = [:]
        var window: [String: SeriesStats] = [:]
        var statistics: [String: Double] = [:]
        for inspected in InspectedType.all {
            linked[inspected.label] = try await stats(inspected, predicate: linkedPredicate)
            window[inspected.label] = try await stats(inspected, predicate: windowPredicate)
            if let stat = workout.statistics(for: inspected.type) {
                let quantity = inspected.type.aggregationStyle == .cumulative ? stat.sumQuantity() : stat.averageQuantity()
                statistics[inspected.label] = quantity?.doubleValue(for: inspected.unit)
            }
        }

        let routes = try await HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: linkedPredicate)],
            sortDescriptors: []
        ).result(for: store).compactMap { $0 as? HKWorkoutRoute }

        let events = workout.workoutEvents ?? []
        return WorkoutReport(
            id: workout.uuid,
            sourceName: workout.sourceRevision.source.name,
            bundleID: workout.sourceRevision.source.bundleIdentifier,
            device: workout.device?.name,
            activityType: workout.workoutActivityType.rawValue,
            start: workout.startDate,
            end: workout.endDate,
            duration: workout.duration,
            laps: events.filter { $0.type == .lap }.count,
            segments: events.filter { $0.type == .segment }.count,
            otherEvents: events.filter { $0.type != .lap && $0.type != .segment }.count,
            activities: workout.workoutActivities.count,
            routes: routes.count,
            routePoints: routes.reduce(0) { $0 + $1.count },
            metadata: (workout.metadata ?? [:]).mapValues { "\($0)" },
            statistics: statistics,
            linked: linked,
            sameSourceInWindow: window
        )
    }

    private func stats(_ inspected: InspectedType, predicate: NSPredicate) async throws -> SeriesStats? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: inspected.type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        guard !samples.isEmpty else { return nil }

        let values = samples.map { $0.quantity.doubleValue(for: inspected.unit) }
        let spacings = zip(samples.dropFirst(), samples).map { $0.startDate.timeIntervalSince($1.startDate) }.sorted()
        let cumulative = inspected.type.aggregationStyle == .cumulative
        return SeriesStats(
            samples: samples.count,
            points: samples.reduce(0) { $0 + $1.count },
            first: samples.first?.startDate,
            last: samples.last?.endDate,
            min: values.min(),
            max: values.max(),
            mean: cumulative ? nil : values.reduce(0, +) / Double(values.count),
            sum: cumulative ? values.reduce(0, +) : nil,
            medianSpacing: spacings.isEmpty ? nil : spacings[spacings.count / 2]
        )
    }
}
#endif
