//
//  WorkoutMatcher.swift
//  Relay
//
//  Groups NormalizedWorkouts from multiple sources into matched clusters.
//  Matching criteria: start time ±60s + duration ±120s + compatible sport type.
//

import Foundation

struct WorkoutMatcher {

    private static let timeToleranceSeconds: TimeInterval = 60
    private static let durationToleranceSeconds: TimeInterval = 120

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
        guard timeDiff <= timeToleranceSeconds else { return false }
        let durationDiff = abs(a.duration - b.duration)
        return durationDiff <= durationToleranceSeconds
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
