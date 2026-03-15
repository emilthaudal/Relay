//
//  SyncRecord.swift
//  Relay
//
//  SwiftData model representing a (workout, connection) sync pair.
//  Tracks whether a workout has been synced to/from a given connection.
//

import Foundation
import SwiftData

@Model
final class SyncRecord {

    // MARK: - Fields

    var workout: WorkoutRecord?
    var connectionType: String          // ConnectionType.rawValue
    var externalID: String              // Platform-specific workout ID
    var stateRaw: String                // SyncState.rawValue
    var isPrimarySource: Bool           // true if this connection is the origin
    var lastAttempt: Date?
    var errorMessage: String?

    // MARK: - Computed

    var connection: ConnectionType {
        get { ConnectionType(rawValue: connectionType) ?? .healthKit }
        set { connectionType = newValue.rawValue }
    }

    var state: SyncState {
        get { SyncState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        connection: ConnectionType,
        externalID: String,
        state: SyncState = .pending,
        isPrimarySource: Bool = false
    ) {
        self.connectionType = connection.rawValue
        self.externalID = externalID
        self.stateRaw = state.rawValue
        self.isPrimarySource = isPrimarySource
    }

    // MARK: - Helpers

    func markSynced() {
        state = .synced
        lastAttempt = Date()
        errorMessage = nil
    }

    func markFailed(error: Error) {
        state = .failed
        lastAttempt = Date()
        errorMessage = error.localizedDescription
    }
}
