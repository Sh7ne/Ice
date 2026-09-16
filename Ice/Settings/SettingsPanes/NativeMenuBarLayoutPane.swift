//
//  NativeMenuBarLayoutPane.swift
//  Ice
//

import SwiftUI

struct NativeMenuBarLayoutPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var manager: NativeMenuBarManager
    @State private var isConfirmingExperimentalHiding = false

    var body: some View {
        IceForm(spacing: 16) {
            IceSection {
                Toggle("Experimental app hiding", isOn: Binding(
                    get: { manager.experimentalHidingEnabled },
                    set: { enabled in
                        if enabled {
                            isConfirmingExperimentalHiding = true
                        } else {
                            manager.experimentalHidingEnabled = false
                        }
                    }
                ))
                Text("While apps are hidden, some system icons and the clock's Notification Center shortcut are unavailable.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            IceSection {
                HStack {
                    Text("Menu Bar Apps").font(.headline)
                    Spacer()
                    Button {
                        Task { await manager.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                    .disabled(manager.isRefreshing)
                }
                if let error = manager.error {
                    Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                if manager.items.isEmpty {
                    Text(manager.isRefreshing ? "Loading..." : "No menu bar apps found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(manager.items) { item in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 24, height: 24)
                        }
                        Text(item.name).lineLimit(2)
                        Spacer()
                        Picker(item.name, selection: Binding(
                            get: { manager.sections[item.id] ?? 0 },
                            set: { manager.setSection($0, for: item.id) }
                        )) {
                            Text("Visible").tag(0)
                            Text("Hidden").tag(1)
                            if appState.settings.advanced.enableAlwaysHiddenSection || manager.sections[item.id] == 2 {
                                Text("Always-Hidden").tag(2)
                            }
                        }
                        .labelsHidden().frame(width: 150)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .confirmationDialog("Enable experimental hiding?", isPresented: $isConfirmingExperimentalHiding) {
            Button("Enable") { manager.experimentalHidingEnabled = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("macOS may hide additional system icons and disable the clock's Notification Center shortcut. Show all sections or disable this option to restore them.")
        }
        .task { await manager.refresh() }
    }
}
