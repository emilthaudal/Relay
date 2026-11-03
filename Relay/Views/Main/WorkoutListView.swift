//
//  WorkoutListView.swift
//  Relay
//
//  Main list of persisted workouts, in a section per month. Shows sport icon, name,
//  duration and overall sync status badge per row.
//

import SwiftUI
import SwiftData

struct WorkoutListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutRecord.startDate, order: .reverse, sectionBy: \WorkoutRecord.monthKey)
    private var months: SectionedResults<WorkoutRecord, String>

    private let engine = SyncEngine.shared
    @State private var showingWorkout: WorkoutRecord?

    var body: some View {
        NavigationStack {
            Group {
                if months.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await engine.sync(appState: appState, context: modelContext) }
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
            SyncNoticesSection(engine: engine)
            ForEach(months) { month in
                Section(WorkoutRecord.monthTitle(for: month.title)) {
                    ForEach(month) { workout in
                        Button { showingWorkout = workout } label: {
                            WorkoutRow(workout: workout)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            SyncNoticesSection(engine: engine)
                .padding(.horizontal)
            ContentUnavailableView(
                "No Workouts",
                systemImage: "figure.run",
                description: Text("Tap the sync button to fetch workouts from your connected services.")
            )
        }
    }
}

// MARK: - Sync notices

/// The last sync's error, and activities Relay had to skip.
private struct SyncNoticesSection: View {
    let engine: SyncEngine

    var body: some View {
        if let error = engine.lastError {
            Label {
                Text(error.localizedDescription).font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        if engine.skippedFromStrava > 0 {
            Label {
                Text("\(engine.skippedFromStrava) Intervals.icu \(engine.skippedFromStrava == 1 ? "activity was" : "activities were") skipped because \(engine.skippedFromStrava == 1 ? "it was" : "they were") imported from Strava. Strava doesn't let Intervals.icu share that data. Connect your device or Zwift to Intervals.icu directly to sync these rides.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
        if engine.heldBackBeforeHealthAccess > 0, let from = engine.healthReadableFrom {
            Label {
                Text("\(engine.heldBackBeforeHealthAccess) \(engine.heldBackBeforeHealthAccess == 1 ? "workout" : "workouts") from before \(from.formatted(date: .abbreviated, time: .omitted)) weren't saved. Apple Health only lets Relay read workouts from that date, so it can't check whether they're already there. To include them, allow all data in Settings → Health → Data Access & Devices → Relay.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
        }
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
