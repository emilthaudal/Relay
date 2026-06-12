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

                // Source Priority
                Section("Sync") {
                    NavigationLink {
                        SourcePrioritySettingsView()
                            .environment(appState)
                    } label: {
                        Label("Source Priority", systemImage: "arrow.up.arrow.down")
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
        }
    }
}
