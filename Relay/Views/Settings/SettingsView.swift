//
//  SettingsView.swift
//  Relay
//
//  Root settings screen. Sections: Connections, Source Priority, Sync, About.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    private let engine = SyncEngine.shared
    @State private var showingHistoricalSync = false

    private var isSyncing: Bool { engine.isSyncing }

    var body: some View {
        NavigationStack {
            Form {
                // Connections
                Section("Connections") {
                    NavigationLink {
                        ConnectionsSettingsView()
                            .environment(appState)
                    } label: {
                        Label("Manage Connections", systemImage: "link")
                    }
                }

                // Sync
                Section("Sync") {
                    NavigationLink {
                        SourcePrioritySettingsView()
                            .environment(appState)
                    } label: {
                        Label("Source Priority", systemImage: "arrow.up.arrow.down")
                    }

                    @Bindable var bindable = appState
                    Toggle(isOn: $bindable.autoSyncToHealthKit) {
                        Label("Auto-sync to Apple Health", systemImage: "heart.fill")
                    }

                    Button {
                        Task { await engine.sync(appState: appState, context: modelContext) }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isSyncing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(isSyncing)

                    Button {
                        showingHistoricalSync = true
                    } label: {
                        Label("Sync Historical Workouts", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                    .disabled(isSyncing)

                    if let progress = engine.progress, progress.total > 0 {
                        ProgressView(value: Double(progress.saved), total: Double(progress.total)) {
                            Text("\(progress.saved) of \(progress.total) saved to Apple Health")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let last = appState.lastSyncDate {
                        LabeledContent("Last Sync") {
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                #if DEBUG
                Section("Developer") {
                    NavigationLink {
                        HealthInspectorView()
                    } label: {
                        Label("Health Inspector", systemImage: "stethoscope")
                    }
                }
                #endif

                // About
                Section("About") {
                    LabeledContent("Version") {
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Sync Historical Workouts", isPresented: $showingHistoricalSync, titleVisibility: .visible) {
                ForEach([(label: "Last 90 days", days: 90), ("Last 6 months", 180), ("Last year", 365)], id: \.days) { option in
                    Button(option.label) {
                        BackgroundSyncTask.shared.startHistoricalSync(days: option.days, label: option.label,
                                                                      appState: appState, context: modelContext)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saves your Intervals.icu workouts from this period to Apple Health. It keeps going if you leave Relay, with progress on the Lock Screen.")
            }
        }
    }
}
