//
//  WorkoutDetailView.swift
//  Relay
//
//  Detail sheet for a single WorkoutRecord. Shows metrics and per-connection sync status.
//

import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutRecord

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Overview
                Section {
                    overviewRow
                }

                // Metrics
                if hasMetrics {
                    Section("Metrics") {
                        metricsRows
                    }
                }

                // Sync status per connection
                Section("Connections") {
                    if workout.syncRecords.isEmpty {
                        Text("No sync records yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workout.syncRecords, id: \.connectionType) { record in
                            HStack {
                                Image(systemName: record.connection.symbolName)
                                    .foregroundStyle(.secondary)
                                Text(record.connection.displayName)
                                Spacer()
                                SyncStatusBadge(state: record.state)
                            }
                        }
                    }
                }
            }
            .navigationTitle(workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var overviewRow: some View {
        HStack(spacing: 16) {
            Image(systemName: workout.sportType.symbolName)
                .font(.largeTitle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.sportType.displayName)
                    .font(.caption).foregroundStyle(.secondary)
                Text(workout.startDate, style: .date)
                    .font(.body)
                Text(formattedDuration(workout.duration))
                    .font(.body.weight(.medium))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var metricsRows: some View {
        if let distance = workout.distance {
            LabeledContent("Distance", value: String(format: "%.2f km", distance / 1000))
        }
        if let calories = workout.calories {
            LabeledContent("Calories", value: "\(calories) kcal")
        }
        if let avgHR = workout.avgHeartRate {
            LabeledContent("Avg Heart Rate", value: String(format: "%.0f bpm", avgHR))
        }
        if let maxHR = workout.maxHeartRate {
            LabeledContent("Max Heart Rate", value: String(format: "%.0f bpm", maxHR))
        }
        if let power = workout.avgPower {
            LabeledContent("Avg Power", value: String(format: "%.0f W", power))
        }
        if let cadence = workout.avgCadence {
            LabeledContent("Avg Cadence", value: String(format: "%.0f rpm", cadence))
        }
        if let elevation = workout.elevationGain {
            LabeledContent("Elevation Gain", value: String(format: "%.0f m", elevation))
        }
    }

    private var hasMetrics: Bool {
        workout.distance != nil ||
        workout.calories != nil ||
        workout.avgHeartRate != nil ||
        workout.avgPower != nil
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
