//
//  SourcePrioritySettingsView.swift
//  Relay
//
//  Re-accessible from Settings. Reuses SourcePriorityContent; persists immediately.
//

import SwiftUI

struct SourcePrioritySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        SourcePriorityContent()
            .environment(appState)
            .navigationTitle("Source Priority")
            .navigationBarTitleDisplayMode(.inline)
    }
}
