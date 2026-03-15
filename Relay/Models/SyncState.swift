//
//  SyncState.swift
//  Relay
//
//  Lifecycle state of a SyncRecord (a workout ↔ connection pair).
//

import Foundation

enum SyncState: String, Codable {
    /// Not yet attempted.
    case pending   = "pending"
    /// Upload in progress.
    case uploading = "uploading"
    /// Successfully synced.
    case synced    = "synced"
    /// Last attempt failed; will retry.
    case failed    = "failed"
    /// Workout originated from this source.
    case source    = "source"

    var displayName: String {
        switch self {
        case .pending:   return "Pending"
        case .uploading: return "Uploading"
        case .synced:    return "Synced"
        case .failed:    return "Failed"
        case .source:    return "Source"
        }
    }
}
