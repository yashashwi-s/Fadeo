import SwiftUI
import AppKit
import FadeoCore

/// The sound library: saved sounds (links, files, folders — named once, reused from any
/// workspace), the bundled ambient presets, and external player availability.
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
                presetsCard
                externalPlayersCard
            }
            .padding(20)
        }
        .navigationTitle("Sound Library")
    }

    // MARK: Saved sounds — the library: links, files, and folders, all named and
    // reusable from any workspace's sound picker. This replaced a separate "playlists"
    // card that duplicated the concept and had no folder support.

    private var savedSoundsCard: some View {
        Card(title: "Your sounds") {
            VStack(alignment: .leading, spacing: 10) {
                if config.savedSounds.isEmpty {
                    Text("Save an Apple Music or Spotify link, a local file, or a whole folder once, name it, and pick it in any workspace. You can also save from the Sound section of a workspace.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(config.savedSounds) { saved in
                    SavedSoundRow(
                        saved: savedBinding(for: saved.id),
                        onDelete: { deleteSavedSound(saved.id) }
                    )
                }
                HStack(spacing: 8) {
                    Button("Add Link…") { showAddSaved = true }
                    Button("Add File…") { addLocal(folder: false) }
                    Button("Add Folder…") { addLocal(folder: true) }
                }
            }
        }
        .sheet(isPresented: $showAddSaved) {
            AddSavedSoundSheet { name, provider, link in
                var cfg = config
                // A pasted link names its own service in its host; trust that over the picker
                // so a Spotify link saved under "Apple Music" is not stored as a broken
                // cross-provider source. Matches SoundEditor's commitLinkDraft behavior.
                let resolved = detectedSavedProvider(for: link) ?? provider
                let source = "external:\(resolved):playlist:\(link)"
                cfg.savedSounds.append(SavedSound(name: name, source: source))
                controller.configStore.save(cfg)
            }
        }
    }

    private func addLocal(folder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = false
        if !folder { panel.allowedContentTypes = [.audio, .movie] }
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var cfg = config
        let name = folder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let source = (folder ? "internal:folder:" : "internal:file:") + url.path
        cfg.savedSounds.append(SavedSound(name: name, source: source))
        controller.configStore.save(cfg)
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

    // MARK: Presets

    private var presetsCard: some View {
        Card(title: "Bundled ambient presets") {
            VStack(alignment: .leading, spacing: 8) {
                presetRow("Brown noise", "Deep and warm, the default for focus work.")
                presetRow("Pink noise", "Softer high end than white noise.")
                presetRow("White noise", "Flat across all frequencies, the most masking.")
                presetRow("Rain", "Bright hiss with scattered droplets.")
                presetRow("Ocean waves", "A slow brown-noise swell that rolls in and out.")
                presetRow("Wind", "Band-passed gusting, like air over a ridge.")
                presetRow("Fan / hum", "Steady low air with a faint tonal hum.")
                Text("Synthesized in real time. No audio files shipped, no looping seams. Pick one in a workspace's Sound section and press Preview to hear it.")
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
        if saved.source.hasPrefix("external:browser") { return "Browser" }
        if saved.source.hasPrefix("internal:file:") { return "File" }
        if saved.source.hasPrefix("internal:folder:") { return "Folder" }
        return "Other"
    }

    private var iconName: String {
        if saved.source.hasPrefix("internal:file:") { return "music.note" }
        if saved.source.hasPrefix("internal:folder:") { return "folder" }
        return "link"
    }

    /// The payload, for display: a path shows its tail, a link its last grammar segment.
    private var linkText: String {
        if saved.source.hasPrefix("internal:file:") || saved.source.hasPrefix("internal:folder:") {
            let path = saved.source.split(separator: ":", maxSplits: 2).map(String.init).last ?? ""
            return (path as NSString).abbreviatingWithTildeInPath
        }
        let parts = saved.source.split(separator: ":", maxSplits: 3).map(String.init)
        return parts.count == 4 ? parts[3] : saved.source
    }

    var body: some View {
        HStack {
            Image(systemName: iconName).font(.caption).foregroundStyle(.secondary).frame(width: 20)
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
                Text("Browser").tag("browser")
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

// Host-sniffs a pasted share link so a saved link is tagged with the service it actually
// names, not whatever the picker happened to show. Mirrors SoundEditor.detectedProvider;
// nil means "not a recognizable service link", so the picker choice stands.
private func detectedSavedProvider(for text: String) -> String? {
    if text.hasPrefix("spotify:") { return "spotify" }
    guard let url = URL(string: text), let host = url.host?.lowercased(),
          text.hasPrefix("http://") || text.hasPrefix("https://")
    else { return nil }
    if host.contains("music.apple.com") { return "appleMusic" }
    if host.contains("open.spotify.com") { return "spotify" }
    if host.contains("youtube.com") || host == "youtu.be" { return "browser" }
    return nil
}

