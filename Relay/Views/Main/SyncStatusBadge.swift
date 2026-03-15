//
//  SyncStatusBadge.swift
//  Relay
//
//  Small badge showing the sync state of a workout with a color-coded icon.
//

import SwiftUI

struct SyncStatusBadge: View {
    let state: SyncState

    var body: some View {
        Label(state.displayName, systemImage: iconName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var iconName: String {
        switch state {
        case .synced:    return "checkmark.circle.fill"
        case .pending:   return "clock.fill"
        case .uploading: return "arrow.up.circle.fill"
        case .failed:    return "exclamationmark.circle.fill"
        case .source:    return "star.fill"
        }
    }

    private var color: Color {
        switch state {
        case .synced:    return .green
        case .pending:   return .orange
        case .uploading: return .blue
        case .failed:    return .red
        case .source:    return .purple
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach([SyncState.synced, .pending, .uploading, .failed, .source], id: \.self) {
            SyncStatusBadge(state: $0)
        }
    }
    .padding()
}
