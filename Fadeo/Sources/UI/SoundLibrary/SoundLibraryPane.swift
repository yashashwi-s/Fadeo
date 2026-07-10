import SwiftUI
import AppKit
import FadeoCore

/// Manage local playlists (the "curated subset of files" case, PLAN.md §4), see the
/// bundled ambient presets, and check which external players are available to conduct.
///
/// Deliberately no live audio preview here: wiring one safely would mean bypassing the
/// resolver's own state tracking (`AppController.applyAudio`), risking the Now pane and
/// the menu bar showing a workspace that isn't actually what's playing. Rather than ship
/// that half-finished, it's cut. A real preview needs a dedicated suppress-evaluation
/// mode in the controller, which is a clean follow-up, not a quick add-on.
struct SoundLibraryPane: View {
    @EnvironmentObject var controller: AppController
    @State private var selection: String?
    @State private var showAddSaved = false

    private var config: Config { controller.configStore.config }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                savedSoundsCard
                playlistsCard
                presetsCard
                externalPlayersCard
            }
            .padding(20)
        }
        .navigationTitle("Sound Library")
    }

    // MARK: Saved sounds (named external links, reusable across workspaces)

    private var savedSoundsCard: some View {
        Card(title: "Saved links") {
            VStack(alignment: .leading, spacing: 10) {
                if config.savedSounds.isEmpty {
                    Text("Paste an Apple Music or Spotify link once, name it, and reuse it in any workspace. Save from here, or with the Save button next to the link field in a workspace's Sound section.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(config.savedSounds) { saved in
                    SavedSoundRow(
                        saved: savedBinding(for: saved.id),
                        onDelete: { deleteSavedSound(saved.id) }
                    )
                }
                Button("Add Link…") { showAddSaved = true }
            }
        }
        .sheet(isPresented: $showAddSaved) {
            AddSavedSoundSheet { name, provider, link in
                var cfg = config
                let source = "external:\(provider):playlist:\(link)"
                cfg.savedSounds.append(SavedSound(name: name, source: source))
                controller.configStore.save(cfg)
            }
        }
    }

    private func savedBinding(for id: String) -> Binding<SavedSound> {
        Binding(
            get: { config.savedSounds.first { $0.id == id } ?? SavedSound(id: id, name: id, source: "") },
            set: { newValue in
                var cfg = controller.configStore.config
                if let idx = cfg.savedSounds.firstIndex(where: { $0.id == id }) {
                    cfg.savedSounds[idx] = newValue
                    controller.configStore.save(cfg)
                }
            }
        )
    }

    private func deleteSavedSound(_ id: String) {
        var cfg = config
        cfg.savedSounds.removeAll { $0.id == id }
        controller.configStore.save(cfg)
    }

    // MARK: Playlists

    private var playlistsCard: some View {
        Card(title: "Your playlists") {
            VStack(alignment: .leading, spacing: 10) {
                if config.localPlaylists.isEmpty {
                    Text("No playlists yet. Create one and add specific files to it: the \"pick a few tracks\" option in a workspace's sound source.")
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
                presetRow("Brown noise", "Deep and warm, the default for focus work.")
                presetRow("Pink noise", "Softer high end than white noise.")
                presetRow("White noise", "Flat across all frequencies, the most masking.")
                presetRow("Rain", "A pink-noise texture tuned to read as rainfall.")
                Text("Synthesized in real time. No audio files shipped, no looping seams.")
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

private struct SavedSoundRow: View {
    @Binding var saved: SavedSound
    let onDelete: () -> Void

    private var providerLabel: String {
        if saved.source.hasPrefix("external:spotify") { return "Spotify" }
        if saved.source.hasPrefix("external:appleMusic") { return "Apple Music" }
        return "Other"
    }

    /// The link/name payload, for display: the last grammar segment.
    private var linkText: String {
        let parts = saved.source.split(separator: ":", maxSplits: 3).map(String.init)
        return parts.count == 4 ? parts[3] : saved.source
    }

    var body: some View {
        HStack {
            Image(systemName: "link").font(.caption).foregroundStyle(.secondary).frame(width: 20)
            TextField("Name", text: $saved.name).textFieldStyle(.plain).font(.callout.weight(.medium))
                .frame(maxWidth: 180)
            Text(providerLabel)
                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Text(linkText)
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { onDelete() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AddSavedSoundSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String, String, String) -> Void

    @State private var name = ""
    @State private var provider = "appleMusic"
    @State private var link = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save a link").font(.headline)
            TextField("Name (e.g. Deep Focus Mix)", text: $name).textFieldStyle(.roundedBorder)
            Picker("App", selection: $provider) {
                Text("Apple Music").tag("appleMusic")
                Text("Spotify").tag("spotify")
            }
            .pickerStyle(.segmented).labelsHidden()
            TextField("Share link, playlist name, or spotify: URI", text: $link)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onAdd(name.isEmpty ? link : name, provider, link)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(link.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
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
