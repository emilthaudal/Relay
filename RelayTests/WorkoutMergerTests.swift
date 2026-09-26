//
//  WorkoutMergerTests.swift
//  RelayTests
//

import Testing
import Foundation
@testable import Relay

@Suite("WorkoutMerger")
struct WorkoutMergerTests {

    // MARK: - Helpers

    private let base = Date(timeIntervalSinceReferenceDate: 0)

    private func workout(
        source: ConnectionType,
        duration: TimeInterval = 3600,
        sport: SportType = .ride,
        distance: Double? = nil,
        calories: Int? = nil,
        avgHR: Double? = nil,
        maxHR: Double? = nil,
        avgPower: Double? = nil,
        maxPower: Double? = nil,
        np: Double? = nil,
        cadence: Double? = nil,
        avgSpeed: Double? = nil,
        maxSpeed: Double? = nil,
        elevation: Double? = nil
    ) -> NormalizedWorkout {
        NormalizedWorkout(
            externalID: UUID().uuidString,
            source: source,
            startDate: base,
            duration: duration,
            sportType: sport,
            name: sport.displayName,
            distance: distance,
            calories: calories,
            avgHeartRate: avgHR,
            maxHeartRate: maxHR,
            avgPower: avgPower,
            maxPower: maxPower,
            normalizedPower: np,
            avgCadence: cadence,
            avgSpeed: avgSpeed,
            maxSpeed: maxSpeed,
            elevationGain: elevation
        )
    }

    // MARK: - Source priority

    @Test("primary source identity is preserved")
    func primarySourcePreserved() {
        let other = workout(source: .hammerhead, distance: 10000)
        let hk = workout(source: .healthKit, distance: 9900)
        let result = WorkoutMerger.merge([other, hk], orderedSources: [.hammerhead, .healthKit])
        #expect(result.source == .hammerhead)
    }

    @Test("higher-priority source wins for non-nil fields")
    func higherPriorityWins() {
        let other = workout(source: .hammerhead, avgHR: 150)
        let hk = workout(source: .healthKit, avgHR: 145)
        let result = WorkoutMerger.merge([other, hk], orderedSources: [.hammerhead, .healthKit])
        #expect(result.avgHeartRate == 150)
    }

    @Test("falls back to lower-priority source for nil fields")
    func nilFieldFallback() {
        let other = workout(source: .hammerhead, avgHR: nil)
        let hk = workout(source: .healthKit, avgHR: 145)
        let result = WorkoutMerger.merge([other, hk], orderedSources: [.hammerhead, .healthKit])
        #expect(result.avgHeartRate == 145)
    }

    @Test("nil remains nil when no source has the field")
    func nilRemainsNil() {
        let other = workout(source: .hammerhead, avgHR: nil)
        let hk = workout(source: .healthKit, avgHR: nil)
        let result = WorkoutMerger.merge([other, hk], orderedSources: [.hammerhead, .healthKit])
        #expect(result.avgHeartRate == nil)
    }

    // MARK: - Field-level fallback across all metrics

    @Test("distance falls back correctly")
    func distanceFallback() {
        let primary = workout(source: .hammerhead, distance: nil)
        let fallback = workout(source: .intervals, distance: 15000)
        let result = WorkoutMerger.merge([primary, fallback], orderedSources: [.hammerhead, .intervals])
        #expect(result.distance == 15000)
    }

    @Test("calories falls back correctly")
    func caloriesFallback() {
        let primary = workout(source: .hammerhead, calories: nil)
        let fallback = workout(source: .healthKit, calories: 500)
        let result = WorkoutMerger.merge([primary, fallback], orderedSources: [.hammerhead, .healthKit])
        #expect(result.calories == 500)
    }

    @Test("normalized power falls back correctly")
    func normalizedPowerFallback() {
        let primary = workout(source: .healthKit, np: nil)
        let fallback = workout(source: .intervals, np: 220)
        let result = WorkoutMerger.merge([primary, fallback], orderedSources: [.healthKit, .intervals])
        #expect(result.normalizedPower == 220)
    }

    @Test("elevation gain falls back correctly")
    func elevationFallback() {
        let primary = workout(source: .hammerhead, elevation: nil)
        let fallback = workout(source: .intervals, elevation: 450)
        let result = WorkoutMerger.merge([primary, fallback], orderedSources: [.hammerhead, .intervals])
        #expect(result.elevationGain == 450)
    }

    // MARK: - Single-element cluster

    @Test("single workout passes through unchanged")
    func singleWorkout() {
        let w = workout(source: .hammerhead, distance: 42195, avgHR: 155, avgPower: 230)
        let result = WorkoutMerger.merge([w], orderedSources: [.hammerhead])
        #expect(result.distance == 42195)
        #expect(result.avgHeartRate == 155)
        #expect(result.avgPower == 230)
        #expect(result.source == .hammerhead)
    }

    // MARK: - Unknown source ordering

    @Test("unknown sources go to end of priority order")
    func unknownSourceOrdering() {
        let other = workout(source: .hammerhead, avgHR: 160)
        let hk = workout(source: .healthKit, avgHR: 155)
        // healthKit not in ordered list — goes last, hammerhead still wins
        let result = WorkoutMerger.merge([other, hk], orderedSources: [.hammerhead, .intervals])
        #expect(result.avgHeartRate == 160)
    }

    // MARK: - Three-source merge

    @Test("three sources: first fills, middle fills nil, last fills remaining nil")
    func threeSourceFallback() {
        let a = workout(source: .hammerhead, avgHR: 150, avgPower: nil, elevation: nil)
        let b = workout(source: .intervals, avgHR: nil, avgPower: 220, elevation: nil)
        let c = workout(source: .healthKit, avgHR: nil, avgPower: nil, elevation: 300)
        let result = WorkoutMerger.merge([a, b, c], orderedSources: [.hammerhead, .intervals, .healthKit])
        #expect(result.avgHeartRate == 150)
        #expect(result.avgPower == 220)
        #expect(result.elevationGain == 300)
    }
}
