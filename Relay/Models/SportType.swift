//
//  SportType.swift
//  Relay
//
//  Canonical sport/activity type used throughout the app.
//  Maps from HKWorkoutActivityType and Strava type strings.
//

import Foundation
import HealthKit

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

    var id: String { rawValue }

    /// Human-readable display name.
    var displayName: String {
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
    var symbolName: String {
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

    /// Strava activity type string (as returned by Strava API).
    var stravaType: String {
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

    /// Initialize from a Strava activity type string.
    init(stravaType: String) {
        self = SportType.allCases.first { $0.stravaType == stravaType } ?? .other
    }
}

// MARK: - HKWorkoutActivityType → SportType

extension HKWorkoutActivityType {
    var relaySportType: SportType {
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

    var relayDisplayName: String {
        relaySportType.displayName
    }
}
