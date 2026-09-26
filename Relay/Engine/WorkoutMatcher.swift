//
//  WorkoutMatcher.swift
//  Relay
//
//  Groups NormalizedWorkouts from multiple sources into matched clusters.
//  Matching criteria: start time ±5min + ≥50% overlap of the shorter workout + compatible sport type.
//

import Foundation

struct WorkoutMatcher {

    private static let startToleranceSeconds: TimeInterval = 300
    private static let minimumOverlapFraction = 0.5

    /// Match workouts from multiple sources into clusters.
    /// Each cluster contains workouts that represent the same real-world activity.
    static func cluster(_ workouts: [NormalizedWorkout]) -> [[NormalizedWorkout]] {
        var remaining = workouts
        var clusters: [[NormalizedWorkout]] = []

        while !remaining.isEmpty {
            let seed = remaining.removeFirst()
            var cluster = [seed]

            remaining = remaining.filter { candidate in
                if matches(seed, candidate) {
                    cluster.append(candidate)
                    return false // remove from remaining
                }
                return true
            }

            clusters.append(cluster)
        }

        return clusters
    }

    // MARK: - Private

    static func matches(_ a: NormalizedWorkout, _ b: NormalizedWorkout) -> Bool {
        guard compatibleSportTypes(a.sportType, b.sportType) else { return false }
        let timeDiff = abs(a.startDate.timeIntervalSince(b.startDate))
        guard timeDiff <= startToleranceSeconds else { return false }
        let overlapStart = max(a.startDate, b.startDate)
        let overlapEnd = min(a.startDate.addingTimeInterval(a.duration), b.startDate.addingTimeInterval(b.duration))
        let overlap = overlapEnd.timeIntervalSince(overlapStart)
        let shorter = min(a.duration, b.duration)
        return shorter > 0 && overlap >= shorter * minimumOverlapFraction
    }

    private static func compatibleSportTypes(_ a: SportType, _ b: SportType) -> Bool {
        if a == b { return true }
        // Virtual variants are compatible with their physical counterparts
        let cyclingGroup: Set<SportType> = [.ride, .virtualRide, .mountainBike]
        let runGroup: Set<SportType>     = [.run, .trailRun, .virtualRun]
        let swimGroup: Set<SportType>    = [.swim, .openWaterSwim]
        for group in [cyclingGroup, runGroup, swimGroup] {
            if group.contains(a) && group.contains(b) { return true }
        }
        return false
    }
}
