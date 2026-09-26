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
    @State private var engine = SyncEngine()
    @State private var isSyncing = false
    @State private var showingHistoricalSync = false

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
                        Task {
                            isSyncing = true
                            await engine.sync(appState: appState, context: modelContext)
                            isSyncing = false
                        }
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

                    if let last = engine.lastSyncDate {
                        LabeledContent("Last Sync") {
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

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
                Button("Last 90 days") {
                    Task {
                        isSyncing = true
                        await engine.syncHistorical(appState: appState, context: modelContext, days: 90)
                        isSyncing = false
                    }
                }
                Button("Last 6 months") {
                    Task {
                        isSyncing = true
                        await engine.syncHistorical(appState: appState, context: modelContext, days: 180)
                        isSyncing = false
                    }
                }
                Button("Last year") {
                    Task {
                        isSyncing = true
                        await engine.syncHistorical(appState: appState, context: modelContext, days: 365)
                        isSyncing = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will fetch workouts from all connected services for the selected time range.")
            }
        }
    }
}
