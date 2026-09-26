//
//  WorkoutMatcherTests.swift
//  RelayTests
//

import Testing
import Foundation
@testable import Relay

@Suite("WorkoutMatcher")
struct WorkoutMatcherTests {

    // MARK: - Helpers

    private func workout(
        start: Date = Date(),
        duration: TimeInterval = 3600,
        sport: SportType = .ride,
        source: ConnectionType = .hammerhead,
        id: String = UUID().uuidString
    ) -> NormalizedWorkout {
        NormalizedWorkout(
            externalID: id,
            source: source,
            startDate: start,
            duration: duration,
            sportType: sport,
            name: sport.displayName
        )
    }

    private let base = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - matches(_:_:)

    @Test("exact same time and duration matches")
    func exactMatch() {
        let a = workout(start: base, duration: 3600)
        let b = workout(start: base, duration: 3600, source: .intervals)
        #expect(WorkoutMatcher.matches(a, b))
    }

    @Test("start within 5 min tolerance matches")
    func timeWithinTolerance() {
        let a = workout(start: base, duration: 3600)
        let b = workout(start: base.addingTimeInterval(300), duration: 3600, source: .intervals)
        #expect(WorkoutMatcher.matches(a, b))
    }

    @Test("start beyond 5 min tolerance does not match")
    func timeExceedsTolerance() {
        let a = workout(start: base, duration: 3600)
        let b = workout(start: base.addingTimeInterval(301), duration: 3600, source: .intervals)
        #expect(!WorkoutMatcher.matches(a, b))
    }

    @Test("moving-time copy of an elapsed-time recording matches")
    func movingVersusElapsedTime() {
        let elapsed = workout(start: base, duration: 9707)
        let moving = workout(start: base, duration: 8932, source: .healthKit)
        #expect(WorkoutMatcher.matches(elapsed, moving))
    }

    @Test("short workout overlapping less than half of the shorter one does not match")
    func insufficientOverlap() {
        let a = workout(start: base, duration: 600)
        let b = workout(start: base.addingTimeInterval(299), duration: 3600, source: .intervals)
        #expect(!WorkoutMatcher.matches(a, b))
    }

    @Test("incompatible sport types do not match")
    func incompatibleSports() {
        let a = workout(start: base, duration: 3600, sport: .ride)
        let b = workout(start: base, duration: 3600, sport: .run, source: .intervals)
        #expect(!WorkoutMatcher.matches(a, b))
    }

    @Test("ride and virtualRide are compatible")
    func cyclingGroupCompatible() {
        let a = workout(start: base, duration: 3600, sport: .ride)
        let b = workout(start: base, duration: 3600, sport: .virtualRide, source: .intervals)
        #expect(WorkoutMatcher.matches(a, b))
    }

    @Test("ride and mountainBike are compatible")
    func mtbGroupCompatible() {
        let a = workout(start: base, duration: 3600, sport: .ride)
        let b = workout(start: base, duration: 3600, sport: .mountainBike, source: .intervals)
        #expect(WorkoutMatcher.matches(a, b))
    }

    @Test("run and trailRun are compatible")
    func runGroupCompatible() {
        let a = workout(start: base, duration: 3600, sport: .run)
        let b = workout(start: base, duration: 3600, sport: .trailRun, source: .intervals)
        #expect(WorkoutMatcher.matches(a, b))
    }

    @Test("swim and openWaterSwim are compatible")
    func swimGroupCompatible() {
        let a = workout(start: base, duration: 3600, sport: .swim)
        let b = workout(start: base, duration: 3600, sport: .openWaterSwim, source: .intervals)
        #expect(WorkoutMatcher.matches(a, b))
    }

    // MARK: - cluster(_:)

    @Test("single workout clusters to one group")
    func singleWorkout() {
        let w = workout(start: base)
        let clusters = WorkoutMatcher.cluster([w])
        #expect(clusters.count == 1)
        #expect(clusters[0].count == 1)
    }

    @Test("two matching workouts form one cluster")
    func twoMatchingWorkouts() {
        let a = workout(start: base, source: .hammerhead)
        let b = workout(start: base, source: .intervals)
        let clusters = WorkoutMatcher.cluster([a, b])
        #expect(clusters.count == 1)
        #expect(clusters[0].count == 2)
    }

    @Test("two non-overlapping workouts form two clusters")
    func twoSeparateWorkouts() {
        let a = workout(start: base, duration: 3600, sport: .ride)
        let b = workout(start: base.addingTimeInterval(7200), duration: 3600, sport: .run, source: .intervals)
        let clusters = WorkoutMatcher.cluster([a, b])
        #expect(clusters.count == 2)
    }

    @Test("three workouts — two matching, one separate — form two clusters")
    func mixedClusters() {
        let a = workout(start: base, duration: 3600, sport: .ride, source: .hammerhead, id: "a")
        let b = workout(start: base.addingTimeInterval(30), duration: 3600, sport: .ride, source: .intervals, id: "b")
        let c = workout(start: base.addingTimeInterval(7200), duration: 1800, sport: .run, source: .hammerhead, id: "c")
        let clusters = WorkoutMatcher.cluster([a, b, c])
        #expect(clusters.count == 2)
        let sizes = clusters.map(\.count).sorted()
        #expect(sizes == [1, 2])
    }

    @Test("empty input returns empty clusters")
    func emptyInput() {
        let clusters = WorkoutMatcher.cluster([])
        #expect(clusters.isEmpty)
    }
}
