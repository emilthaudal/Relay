//
//  HealthInspectorView.swift
//  Relay
//
//  Debug builds only. Pick a day, select the copies of one activity written by
//  different apps (e.g. Relay and RunGap), and compare what Health holds for each.
//

#if DEBUG
import HealthKit
import SwiftUI

struct HealthInspectorView: View {
    private let inspector = HealthInspector()

    @State private var day = Date()
    @State private var workouts: [HKWorkout] = []
    @State private var selected: Set<UUID> = []
    @State private var reports: [WorkoutReport] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                DatePicker("Day", selection: $day, displayedComponents: .date)
            } footer: {
                Text("Select the same activity as written by each app, then compare.")
            }

            Section("Workouts in Health") {
                if workouts.isEmpty && !isLoading {
                    Text("No workouts on this day").foregroundStyle(.secondary)
                }
                ForEach(workouts, id: \.uuid) { workout in
                    Button { toggle(workout.uuid) } label: {
                        HStack {
                            Image(systemName: selected.contains(workout.uuid) ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text(workout.sourceRevision.source.name).font(.body.weight(.medium))
                                Text("\(workout.startDate.formatted(date: .omitted, time: .shortened)) · \(Int(workout.duration / 60)) min · \(workout.device?.name ?? "no device")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
            }

            Section {
                Button("Compare \(selected.count) workout\(selected.count == 1 ? "" : "s")") {
                    Task { await compare() }
                }
                .disabled(selected.isEmpty || isLoading)
            }

            if !reports.isEmpty {
                WorkoutComparison(reports: reports)
                if let url = exportURL() {
                    Section {
                        ShareLink("Export JSON", item: url)
                    }
                }
            }
        }
        .navigationTitle("Health Inspector")
        .overlay { if isLoading { ProgressView() } }
        .task(id: day) { await load() }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await inspector.requestAccess()
            workouts = try await inspector.workouts(on: day)
            selected = selected.filter { id in workouts.contains { $0.uuid == id } }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func compare() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var result: [WorkoutReport] = []
            for workout in workouts where selected.contains(workout.uuid) {
                result.append(try await inspector.report(for: workout))
            }
            reports = result
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportURL() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(reports) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("health-inspector.json")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

// MARK: - Comparison

/// One row per measure, one column per workout; rows where the workouts differ are highlighted.
private struct WorkoutComparison: View {
    let reports: [WorkoutReport]

    private struct Row: Identifiable {
        let label: String
        let values: [String]
        var id: String { label }
        var differs: Bool { Set(values).count > 1 }
    }

    var body: some View {
        Section("Workout") { grid(workoutRows) }
        Section("Samples linked to the workout") { grid(seriesRows(\.linked)) }
        Section("Same app, inside the workout's time") { grid(seriesRows(\.sameSourceInWindow)) }
        Section("Workout statistics") { grid(statisticsRows) }
        Section("Metadata") { grid(metadataRows) }
    }

    private var workoutRows: [Row] {
        [
            Row(label: "Source", values: reports.map(\.sourceName)),
            Row(label: "Device", values: reports.map { $0.device ?? "—" }),
            Row(label: "Start", values: reports.map { $0.start.formatted(date: .omitted, time: .standard) }),
            Row(label: "Duration", values: reports.map { "\(Int($0.duration)) s" }),
            Row(label: "Laps", values: reports.map { "\($0.laps)" }),
            Row(label: "Segments", values: reports.map { "\($0.segments)" }),
            Row(label: "Other events", values: reports.map { "\($0.otherEvents)" }),
            Row(label: "Activities", values: reports.map { "\($0.activities)" }),
            Row(label: "Routes", values: reports.map { "\($0.routes)" }),
            Row(label: "Route points", values: reports.map { "\($0.routePoints)" }),
        ]
    }

    private func seriesRows(_ keyPath: KeyPath<WorkoutReport, [String: SeriesStats]>) -> [Row] {
        InspectedType.all.flatMap { inspected -> [Row] in
            let stats = reports.map { $0[keyPath: keyPath][inspected.label] }
            guard stats.contains(where: { $0 != nil }) else { return [] }
            let u = inspected.unitLabel
            return [
                Row(label: "\(inspected.label): points", values: stats.map { $0.map { "\($0.points)" } ?? "—" }),
                Row(label: "\(inspected.label): spacing", values: stats.map { $0?.medianSpacing.map { format($0) + " s" } ?? "—" }),
                Row(label: "\(inspected.label): \(stats.contains { $0?.sum != nil } ? "sum" : "mean")",
                    values: stats.map { s in (s?.sum ?? s?.mean).map { format($0) + " " + u } ?? "—" }),
                Row(label: "\(inspected.label): min–max",
                    values: stats.map { s in s.flatMap { s in s.min.flatMap { lo in s.max.map { "\(format(lo))–\(format($0))" } } } ?? "—" }),
            ]
        }
    }

    private var statisticsRows: [Row] {
        let labels = Set(reports.flatMap { $0.statistics.keys })
        return InspectedType.all.filter { labels.contains($0.label) }.map { inspected in
            Row(label: inspected.label,
                values: reports.map { $0.statistics[inspected.label].map { format($0) + " " + inspected.unitLabel } ?? "—" })
        }
    }

    private var metadataRows: [Row] {
        Set(reports.flatMap { $0.metadata.keys }).sorted().map { key in
            Row(label: key, values: reports.map { $0.metadata[key] ?? "—" })
        }
    }

    @ViewBuilder
    private func grid(_ rows: [Row]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label).font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                            Text(value).font(.caption.monospacedDigit())
                                .foregroundStyle(row.differs ? .orange : .primary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
#endif
