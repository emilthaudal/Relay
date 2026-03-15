//
//  ConnectionType.swift
//  Relay
//
//  Represents a fitness platform / data source that Relay can connect to.
//

import Foundation

enum ConnectionType: String, Codable, CaseIterable, Identifiable {
    case healthKit  = "healthkit"
    case strava     = "strava"
    case intervals  = "intervals"
    case hammerhead = "hammerhead"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .healthKit:  return "Apple Health"
        case .strava:     return "Strava"
        case .intervals:  return "Intervals.icu"
        case .hammerhead: return "Hammerhead"
        }
    }

    var symbolName: String {
        switch self {
        case .healthKit:  return "heart.fill"
        case .strava:     return "flame.fill"
        case .intervals:  return "chart.xyaxis.line"
        case .hammerhead: return "bicycle"
        }
    }

    /// Whether this connection is currently available for use.
    /// Hammerhead is Phase 4 — no public API yet.
    var isAvailable: Bool {
        switch self {
        case .healthKit, .strava, .intervals: return true
        case .hammerhead:                     return false
        }
    }
}
