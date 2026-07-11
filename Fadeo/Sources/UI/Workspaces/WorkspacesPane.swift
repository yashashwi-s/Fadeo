import SwiftUI
import FadeoCore

/// Workspace list + editor. Edits are saved immediately (no separate "apply" step) —
/// ConfigStore's atomic write + hot-reload dedup make this safe, and it keeps the mental
/// model simple: this screen IS the config, not a draft of it.
struct WorkspacesPane: View {
    @EnvironmentObject var controller: AppController
    @State private var selection: String?
    @State private var installedApps: [InstalledApp] = []

    private var config: Config { controller.configStore.config }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
            detail.frame(minWidth: 460, maxWidth: .infinity)
        }
        .onAppear {
            installedApps = InstalledApps.scan()
            if selection == nil { selection = config.workspaces.first?.id }
        }
        .onDisappear { controller.stopPreview() }
        .onChange(of: selection) { _, _ in controller.stopPreview() }
        .navigationTitle("Workspaces")
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            List(config.workspaces, selection: $selection) { ws in
                HStack(spacing: 8) {
                    Circle().fill(Brand.swatch(ws.color)).frame(width: 8, height: 8)
                    Text(ws.name)
                    Spacer()
                    if ws.match.isEmpty {
                        Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    if ws.isOverride {
                        Image(systemName: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    }
                    if !ws.enabled {
                        Text("off").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .tag(ws.id)
                .opacity(ws.enabled ? 1 : 0.5)
            }
            Divider()
            HStack {
                Button { addWorkspace() } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                Button { removeSelected() } label: { Image(systemName: "minus") }
                    .buttonStyle(.plain)
                    .disabled(selection == nil)
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let binding = workspaceBinding(id) {
            WorkspaceEditor(workspace: binding, installedApps: installedApps,
                            allPlaylists: config.localPlaylists,
                            savedSounds: config.savedSounds,
                            onSaveSound: { name, source in saveSound(name: name, source: source) },
                            onTogglePreview: { sound in controller.togglePreview(sound) },
                            previewingSource: controller.previewingSource)
                .id(id)   // fresh form state per workspace
        } else {
            ContentUnavailableView("No workspace selected", systemImage: "square.stack.3d.up")
        }
    }

    private func saveSound(name: String, source: String) {
        guard !source.isEmpty else { return }
        var cfg = config
        // Same source already saved: just rename instead of duplicating.
        if let idx = cfg.savedSounds.firstIndex(where: { $0.source == source }) {
            cfg.savedSounds[idx].name = name
        } else {
            cfg.savedSounds.append(SavedSound(name: name, source: source))
        }
        controller.configStore.save(cfg)
    }

    // MARK: Mutation

    private func workspaceBinding(_ id: String) -> Binding<Workspace>? {
        guard config.workspaces.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { controller.configStore.config.workspaces.first(where: { $0.id == id }) ?? .placeholder(id) },
            set: { newValue in
                var cfg = controller.configStore.config
                if let idx = cfg.workspaces.firstIndex(where: { $0.id == id }) {
                    cfg.workspaces[idx] = newValue
                    controller.configStore.save(cfg)
                }
            }
        )
    }

    private func addWorkspace() {
        var cfg = config
        var id = "workspace"
        var n = 1
        while cfg.workspaces.contains(where: { $0.id == id }) { n += 1; id = "workspace-\(n)" }
        let ws = Workspace(id: id, name: "New Workspace", color: "#67E4D2",
                           priority: 10, match: Match(), sound: Sound(source: "internal:preset:brown-noise"))
        cfg.workspaces.append(ws)
        controller.configStore.save(cfg)
        selection = id
    }

    private func removeSelected() {
        guard let id = selection else { return }
        var cfg = config
        cfg.workspaces.removeAll { $0.id == id }
        controller.configStore.save(cfg)
        selection = cfg.workspaces.first?.id
    }
}

private extension Workspace {
    static func placeholder(_ id: String) -> Workspace {
        Workspace(id: id, name: id, match: Match(), sound: Sound())
    }
}
