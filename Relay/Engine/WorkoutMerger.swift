//
//  WorkoutMerger.swift
//  Relay
//
//  Merges a cluster of matched NormalizedWorkouts from different sources into a single
//  canonical workout. Fields from higher-priority sources win; nil fields fall back
//  to lower-priority sources.
//

import Foundation

struct WorkoutMerger {

    /// Merge a cluster of workouts into one canonical NormalizedWorkout.
    /// `orderedSources` should be sorted highest→lowest priority for the sport.
    static func merge(_ cluster: [NormalizedWorkout], orderedSources: [ConnectionType]) -> NormalizedWorkout {
        // Sort cluster by source priority; unknown sources go to the end
        let sorted = cluster.sorted { a, b in
            let ai = orderedSources.firstIndex(of: a.source) ?? Int.max
            let bi = orderedSources.firstIndex(of: b.source) ?? Int.max
            return ai < bi
        }

        guard let primary = sorted.first else {
            preconditionFailure("merge called with empty cluster")
        }

        // Build merged metrics by falling back to lower-priority sources for nil fields
        var distance        = primary.distance
        var calories        = primary.calories
        var avgHeartRate    = primary.avgHeartRate
        var maxHeartRate    = primary.maxHeartRate
        var avgPower        = primary.avgPower
        var maxPower        = primary.maxPower
        var normalizedPower = primary.normalizedPower
        var avgCadence      = primary.avgCadence
        var avgSpeed        = primary.avgSpeed
        var maxSpeed        = primary.maxSpeed
        var elevationGain   = primary.elevationGain

        for fallback in sorted.dropFirst() {
            if distance        == nil { distance        = fallback.distance }
            if calories        == nil { calories        = fallback.calories }
            if avgHeartRate    == nil { avgHeartRate    = fallback.avgHeartRate }
            if maxHeartRate    == nil { maxHeartRate    = fallback.maxHeartRate }
            if avgPower        == nil { avgPower        = fallback.avgPower }
            if maxPower        == nil { maxPower        = fallback.maxPower }
            if normalizedPower == nil { normalizedPower = fallback.normalizedPower }
            if avgCadence      == nil { avgCadence      = fallback.avgCadence }
            if avgSpeed        == nil { avgSpeed        = fallback.avgSpeed }
            if maxSpeed        == nil { maxSpeed        = fallback.maxSpeed }
            if elevationGain   == nil { elevationGain   = fallback.elevationGain }
        }

        return NormalizedWorkout(
            id: primary.id,
            externalID: primary.externalID,
            source: primary.source,
            startDate: primary.startDate,
            duration: primary.duration,
            sportType: primary.sportType,
            name: primary.name,
            isTrainer: primary.isTrainer,
            distance: distance,
            calories: calories,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            avgPower: avgPower,
            maxPower: maxPower,
            normalizedPower: normalizedPower,
            avgCadence: avgCadence,
            avgSpeed: avgSpeed,
            maxSpeed: maxSpeed,
            elevationGain: elevationGain
        )
    }
}
