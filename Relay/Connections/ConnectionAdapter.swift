//
//  ConnectionAdapter.swift
//  Relay
//
//  Protocol that every fitness-platform adapter must conform to.
//  All operations are async and actor-isolated to allow safe concurrent access.
//

import Foundation

protocol ConnectionAdapter: Actor {
    /// The platform this adapter represents.
    var connectionType: ConnectionType { get }

    /// Whether the user is currently authenticated / connected.
    var isConnected: Bool { get async }

    /// Authenticate the user (OAuth flow, permission request, etc.).
    /// Throws if auth fails or is cancelled.
    func authenticate() async throws

    /// Disconnect / revoke credentials.
    func disconnect() async

    /// Fetch workouts recorded since the given date.
    /// Returns platform-normalised workouts ready for the engine.
    func fetchWorkouts(since date: Date) async throws -> [NormalizedWorkout]

    /// Upload a workout to this platform and return the platform-assigned ID.
    func upload(_ workout: NormalizedWorkout) async throws -> String
}
