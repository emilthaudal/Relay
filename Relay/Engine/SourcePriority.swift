//
//  SourcePriority.swift
//  Relay
//
//  Resolves which connection should be considered the primary source for a given sport type,
//  taking into account user-configured priority and which connections are enabled.
//

import Foundation

struct SourcePriorityResolver {

    /// Returns the ordered list of connections for a sport type, filtered to enabled connections.
    static func orderedSources(for sport: SportType, appState: AppState) -> [ConnectionType] {
        let priorityList = appState.sourcePriority(for: sport)
        let enabled = appState.enabledConnections
        // Return only enabled connections, in priority order
        return priorityList.filter { enabled.contains($0) }
    }

    /// Returns the highest-priority connection for a sport type, or nil if none enabled.
    static func primarySource(for sport: SportType, appState: AppState) -> ConnectionType? {
        orderedSources(for: sport, appState: appState).first
    }

    /// Returns true if `candidate` is higher priority than `other` for the given sport.
    static func isHigherPriority(_ candidate: ConnectionType,
                                 than other: ConnectionType,
                                 for sport: SportType,
                                 appState: AppState) -> Bool {
        let ordered = orderedSources(for: sport, appState: appState)
        guard
            let ci = ordered.firstIndex(of: candidate),
            let oi = ordered.firstIndex(of: other)
        else { return false }
        return ci < oi
    }
}
