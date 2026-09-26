//
//  AppState.swift
//  Relay
//
//  SwiftData model for global app configuration.
//  Stores onboarding completion, enabled connections, and source priority settings.
//  There should be exactly one AppState instance in the store.
//

import Foundation
import SwiftData

@Model
final class AppState {

    // MARK: - Onboarding

    var onboardingCompleted: Bool

    // MARK: - Sync Options

    /// When true, imported workouts are automatically uploaded to HealthKit after each sync.
    var autoSyncToHealthKit: Bool

    // MARK: - Connections

    /// Raw values of enabled ConnectionTypes.
    var enabledConnectionsRaw: [String]

    var enabledConnections: Set<ConnectionType> {
        get { Set(enabledConnectionsRaw.compactMap { ConnectionType(rawValue: $0) }) }
        set { enabledConnectionsRaw = newValue.map { $0.rawValue } }
    }

    // MARK: - Source Priority

    /// Per-sport source priority. Key: SportType.rawValue, Value: [ConnectionType.rawValue] ordered highest→lowest.
    var sourcePriorityRaw: [String: [String]]

    func sourcePriority(for sport: SportType) -> [ConnectionType] {
        guard let raw = sourcePriorityRaw[sport.rawValue] else {
            return defaultPriority(for: sport)
        }
        return raw.compactMap { ConnectionType(rawValue: $0) }
    }

    func setSourcePriority(_ connections: [ConnectionType], for sport: SportType) {
        sourcePriorityRaw[sport.rawValue] = connections.map { $0.rawValue }
    }

    private func defaultPriority(for sport: SportType) -> [ConnectionType] {
        switch sport {
        case .ride, .mountainBike, .virtualRide:
            return [.intervals, .healthKit]
        default:
            return [.healthKit, .intervals]
        }
    }

    // MARK: - Init

    init() {
        self.onboardingCompleted = false
        self.autoSyncToHealthKit = true
        self.enabledConnectionsRaw = []
        self.sourcePriorityRaw = [:]
    }
}
