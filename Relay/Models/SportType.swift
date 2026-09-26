//
//  SportType.swift
//  Relay
//
//  Canonical sport/activity type used throughout the app.
//  Maps from HKWorkoutActivityType and Strava type strings.
//

import Foundation

enum SportType: String, Codable, CaseIterable, Identifiable {
    // Cycling
    case ride
    case virtualRide
    case mountainBike

    // Running
    case run
    case trailRun
    case virtualRun

    // Swimming
    case swim
    case openWaterSwim

    // Walking / Hiking
    case walk
    case hike

    // Triathlon
    case triathlon

    // Strength / Cross-training
    case workout
    case yoga
    case hiit
    case elliptical
    case rowing

    // Other
    case other

    nonisolated var id: String { rawValue }

    /// Human-readable display name.
    nonisolated var displayName: String {
        switch self {
        case .ride:          return "Ride"
        case .virtualRide:   return "Virtual Ride"
        case .mountainBike:  return "Mountain Bike"
        case .run:           return "Run"
        case .trailRun:      return "Trail Run"
        case .virtualRun:    return "Virtual Run"
        case .swim:          return "Swim"
        case .openWaterSwim: return "Open Water Swim"
        case .walk:          return "Walk"
        case .hike:          return "Hike"
        case .triathlon:     return "Triathlon"
        case .workout:       return "Workout"
        case .yoga:          return "Yoga"
        case .hiit:          return "HIIT"
        case .elliptical:    return "Elliptical"
        case .rowing:        return "Rowing"
        case .other:         return "Activity"
        }
    }

    /// SF Symbol name for sport icon.
    nonisolated var symbolName: String {
        switch self {
        case .ride, .virtualRide, .mountainBike: return "bicycle"
        case .run, .trailRun, .virtualRun:       return "figure.run"
        case .swim, .openWaterSwim:              return "figure.pool.swim"
        case .walk:                              return "figure.walk"
        case .hike:                              return "figure.hiking"
        case .triathlon:                         return "figure.triathlon"
        case .workout, .hiit:                    return "dumbbell"
        case .yoga:                              return "figure.mind.and.body"
        case .elliptical:                        return "figure.elliptical"
        case .rowing:                            return "figure.rowing"
        case .other:                             return "figure.mixed.cardio"
        }
    }

    /// Activity type string as returned by the Intervals.icu API.
    nonisolated var intervalsType: String {
        switch self {
        case .ride:          return "Ride"
        case .virtualRide:   return "VirtualRide"
        case .mountainBike:  return "MountainBikeRide"
        case .run:           return "Run"
        case .trailRun:      return "TrailRun"
        case .virtualRun:    return "VirtualRun"
        case .swim:          return "Swim"
        case .openWaterSwim: return "OpenWaterSwim"
        case .walk:          return "Walk"
        case .hike:          return "Hike"
        case .triathlon:     return "Triathlon"
        case .workout:       return "Workout"
        case .yoga:          return "Yoga"
        case .hiit:          return "Hiit"
        case .elliptical:    return "Elliptical"
        case .rowing:        return "Rowing"
        case .other:         return "Other"
        }
    }

    nonisolated init(intervalsType: String) {
        switch intervalsType {
        case "GravelRide", "EBikeRide":
            self = .ride
        case "EMountainBikeRide":
            self = .mountainBike
        case "VirtualRide", "IndoorCycling":
            self = .virtualRide
        default:
            self = SportType.allCases.first { $0.intervalsType == intervalsType } ?? .other
        }
    }
}
