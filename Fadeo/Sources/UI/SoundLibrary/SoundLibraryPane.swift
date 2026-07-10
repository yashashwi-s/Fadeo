import SwiftUI
import AppKit
import FadeoCore

/// Manage local playlists (the "curated subset of files" case — PLAN.md §4), see the
/// bundled ambient presets, and check which external players are available to conduct.
///
/// Deliberately no live audio preview here: wiring one safely would mean bypassing the
/// resolver's own state tracking (`AppController.applyAudio`), risking the Now pane and
/// the menu bar showing a workspace that isn't actually what's playing. Rather than ship
/// that half-finished, it's cut — a real preview needs a dedicated suppress-evaluation
/// mode in the controller, which is a clean follow-up, not a quick add-on.
struct SoundLibraryPane: View {
    @EnvironmentObject var controller: AppController
    @State private var selection: String?

    private var config: Config { controller.configStore.config }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                playlistsCard
                presetsCard
                externalPlayersCard
            }
            .padding(20)
        }
        .navigationTitle("Sound Library")
    }

    // MARK: Playlists

    private var playlistsCard: some View {
        Card(title: "Your playlists") {
            VStack(alignment: .leading, spacing: 10) {
                if config.localPlaylists.isEmpty {
                    Text("No playlists yet. Create one and add specific files to it — the \"pick a few tracks\" option in a workspace's sound source.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(config.localPlaylists) { playlist in
                    PlaylistRow(
                        playlist: binding(for: playlist.id),
                        onDelete: { deletePlaylist(playlist.id) }
                    )
                }
                Button("New Playlist") { addPlaylist() }
            }
        }
    }

    private func binding(for id: String) -> Binding<LocalPlaylist> {
        Binding(
            get: { config.localPlaylists.first { $0.id == id } ?? LocalPlaylist(id: id, name: id, paths: []) },
            set: { newValue in
                var cfg = controller.configStore.config
                if let idx = cfg.localPlaylists.firstIndex(where: { $0.id == id }) {
                    cfg.localPlaylists[idx] = newValue
                    controller.configStore.save(cfg)
                }
            }
        )
    }

    private func addPlaylist() {
        var cfg = config
        var id = "playlist"
        var n = 1
        while cfg.localPlaylists.contains(where: { $0.id == id }) { n += 1; id = "playlist-\(n)" }
        cfg.localPlaylists.append(LocalPlaylist(id: id, name: "New Playlist", paths: []))
        controller.configStore.save(cfg)
    }

    private func deletePlaylist(_ id: String) {
        var cfg = config
        cfg.localPlaylists.removeAll { $0.id == id }
        controller.configStore.save(cfg)
    }

    // MARK: Presets

    private var presetsCard: some View {
        Card(title: "Bundled ambient presets") {
            VStack(alignment: .leading, spacing: 8) {
                presetRow("Brown noise", "Deep, warm — the default for focus work.")
                presetRow("Pink noise", "Softer high end than white noise.")
                presetRow("White noise", "Flat across all frequencies — the most masking.")
                presetRow("Rain", "A pink-noise texture tuned to read as rainfall.")
                Text("Synthesized in real time — no audio files shipped, no looping seams.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func presetRow(_ name: String, _ desc: String) -> some View {
        HStack {
            Image(systemName: "waveform").foregroundStyle(.secondary).frame(width: 20)
            Text(name).font(.callout.weight(.medium))
            Text(desc).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: External players

    private var externalPlayersCard: some View {
        Card(title: "External players") {
            VStack(alignment: .leading, spacing: 8) {
                playerRow(name: "Apple Music", bundleID: "com.apple.Music")
                playerRow(name: "Spotify", bundleID: "com.spotify.client")
                Text("Fadeo asks permission to control these the first time a workspace needs to (System Settings ▸ Privacy & Security ▸ Automation).")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func playerRow(name: String, bundleID: String) -> some View {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        return HStack {
            Circle().fill(installed ? Color.green.opacity(0.7) : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(name).font(.callout)
            Spacer()
            Text(installed ? "Installed" : "Not installed").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PlaylistRow: View {
    @Binding var playlist: LocalPlaylist
    let onDelete: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary)
                    .onTapGesture { expanded.toggle() }
                TextField("Name", text: $playlist.name).textFieldStyle(.plain).font(.callout.weight(.medium))
                Spacer()
                Text("\(playlist.paths.count) track\(playlist.paths.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Button { onDelete() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(playlist.paths, id: \.self) { path in
                        HStack {
                            Text((path as NSString).lastPathComponent).font(.caption).lineLimit(1)
                            Spacer()
                            Button {
                                playlist.paths.removeAll { $0 == path }
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    Button("Add Files…") { addFiles() }.font(.caption)
                }
                .padding(.leading, 16)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK {
            for url in panel.urls where !playlist.paths.contains(url.path) {
                playlist.paths.append(url.path)
            }
        }
    }
}
