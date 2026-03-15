//
//  WorkoutListView.swift
//  Relay
//
//  Main list of persisted workouts, grouped by date. Shows sport icon, name,
//  duration and overall sync status badge per row.
//

import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]

    @State private var engine = SyncEngine()
    @State private var showingWorkout: WorkoutRecord?

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await engine.sync(appState: appState) }
                    } label: {
                        if engine.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(engine.isSyncing)
                }
            }
            .sheet(item: $showingWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
        }
    }

    // MARK: - Subviews

    private var list: some View {
        List {
            ForEach(workouts) { workout in
                Button { showingWorkout = workout } label: {
                    WorkoutRow(workout: workout)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Workouts",
            systemImage: "figure.run",
            description: Text("Tap the sync button to fetch workouts from your connected services.")
        )
    }
}

// MARK: - Row

private struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.sportType.symbolName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(workout.startDate, style: .date)
                    Text("·")
                    Text(formattedDuration(workout.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            SyncStatusBadge(state: workout.syncState)
        }
        .padding(.vertical, 4)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
