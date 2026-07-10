import SwiftUI
import AppKit
import FadeoCore

/// Builds/edits a `Sound.source` string by parsing it into a UI-friendly shape and
/// reconstructing it on every edit. The model stays a single opaque string (simple,
/// serializes cleanly, matches the source grammar in PLAN.md §4) while the UI gets normal
/// pickers and text fields via computed bindings.
struct SoundEditor: View {
    @Binding var sound: Sound
    let memberApps: [String]
    let installedApps: [InstalledApp]
    let allPlaylists: [LocalPlaylist]
    var savedSounds: [SavedSound] = []
    /// Persist a new saved sound (name, source) into the config. Provided by the pane
    /// that owns config access; the editor itself only sees the workspace binding.
    var onSaveSound: ((String, String) -> Void)?

    /// Local draft of the external link/playlist text. Committing on submit/blur (not
    /// every keystroke) matters: each save re-evaluates, and if this workspace is
    /// active, a half-typed URL would fire a real handoff to Music/Spotify mid-typing.
    @State private var linkDraft: String = ""
    @FocusState private var linkFieldFocused: Bool
    @State private var showSavePrompt = false
    @State private var savePromptName = ""

    private enum Kind: String, CaseIterable, Identifiable {
        case preset, file, folder, playlist, external, silence
        var id: String { rawValue }
        var label: String {
            switch self {
            case .preset: return "Ambient preset"
            case .file: return "A file"
            case .folder: return "A folder"
            case .playlist: return "A playlist (curated)"
            case .external: return "Spotify / Apple Music"
            case .silence: return "Nothing (pause/stop)"
            }
        }
    }

    private static let presets = ["brown-noise", "pink-noise", "white-noise", "rain"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Source", selection: kindBinding) {
                ForEach(Kind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()

            switch currentKind {
            case .preset: presetPicker
            case .file: pathPicker(isFolder: false)
            case .folder: pathPicker(isFolder: true)
            case .playlist: playlistPicker
            case .external: externalPicker
            case .silence: EmptyView()
            }

            if currentKind != .silence {
                volumeRow
                if currentKind == .folder || currentKind == .playlist {
                    orderRepeatRow
                }
            }

            actionRow

            if !memberApps.isEmpty {
                Divider()
                perAppOverrides
            }
        }
    }

    // MARK: Kind

    private var currentKind: Kind {
        guard let s = sound.source, !s.isEmpty else { return .silence }
        if s.hasPrefix("internal:preset:") { return .preset }
        if s.hasPrefix("internal:file:") { return .file }
        if s.hasPrefix("internal:folder:") { return .folder }
        if s.hasPrefix("internal:playlist:") { return .playlist }
        if s.hasPrefix("external:") { return .external }
        return .silence
    }

    private var kindBinding: Binding<Kind> {
        Binding(
            get: { currentKind },
            set: { newKind in
                switch newKind {
                case .preset: sound.source = "internal:preset:\(Self.presets[0])"
                case .file, .folder: sound.source = nil   // wait for a Choose… pick
                case .playlist: sound.source = allPlaylists.first.map { "internal:playlist:\($0.id)" }
                case .external: sound.source = "external:appleMusic:command"
                case .silence: sound.source = nil; sound.action = .pause
                }
                if newKind != .silence { sound.action = .play }
            }
        )
    }

    // MARK: Preset

    private var presetPicker: some View {
        Picker("Preset", selection: Binding(
            get: { sourceSuffix(after: "internal:preset:") ?? Self.presets[0] },
            set: { sound.source = "internal:preset:\($0)" }
        )) {
            ForEach(Self.presets, id: \.self) { Text(presetLabel($0)).tag($0) }
        }
        .labelsHidden()
    }

    private func presetLabel(_ p: String) -> String {
        switch p {
        case "brown-noise": return "Brown noise"
        case "pink-noise": return "Pink noise"
        case "white-noise": return "White noise"
        case "rain": return "Rain"
        default: return p
        }
    }

    // MARK: File / folder

    private func pathPicker(isFolder: Bool) -> some View {
        HStack {
            Text(sourceSuffix(after: isFolder ? "internal:folder:" : "internal:file:") ?? "No path chosen")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Choose…") { choosePath(isFolder: isFolder) }
        }
    }

    private func choosePath(isFolder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !isFolder
        panel.canChooseDirectories = isFolder
        panel.allowsMultipleSelection = false
        if !isFolder {
            panel.allowedContentTypes = [.audio]
        }
        if panel.runModal() == .OK, let url = panel.url {
            sound.source = (isFolder ? "internal:folder:" : "internal:file:") + url.path
        }
    }

    // MARK: Playlist

    private var playlistPicker: some View {
        Group {
            if allPlaylists.isEmpty {
                Text("No playlists yet. Create one in Sound Library.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("Playlist", selection: Binding(
                    get: { sourceSuffix(after: "internal:playlist:") ?? allPlaylists[0].id },
                    set: { sound.source = "internal:playlist:\($0)" }
                )) {
                    ForEach(allPlaylists) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
            }
        }
    }

    // MARK: External

    private var externalProvider: String {
        guard let s = sound.source, s.hasPrefix("external:") else { return "appleMusic" }
        let parts = s.split(separator: ":", maxSplits: 3).map(String.init)
        return parts.count > 1 ? parts[1] : "appleMusic"
    }

    private var externalPlaylistText: String {
        guard let s = sound.source else { return "" }
        let parts = s.split(separator: ":", maxSplits: 3).map(String.init)
        guard parts.count == 4, parts[2] == "playlist" else { return "" }
        return parts[3]
    }

    private var externalPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("App", selection: Binding(
                get: { externalProvider },
                set: { rebuildExternal(provider: $0, playlist: externalPlaylistText) }
            )) {
                Text("Apple Music").tag("appleMusic")
                Text("Spotify").tag("spotify")
            }
            .labelsHidden()

            if !externalSavedSounds.isEmpty {
                Picker("Saved", selection: Binding(
                    get: { savedSelectionID },
                    set: { id in
                        guard id != "custom", let saved = savedSounds.first(where: { $0.id == id }) else { return }
                        sound.source = saved.source
                        linkDraft = externalPlaylistText
                    }
                )) {
                    Text("Custom / pasted link").tag("custom")
                    ForEach(externalSavedSounds) { Text($0.name).tag($0.id) }
                }
            }

            HStack(spacing: 6) {
                TextField("Playlist name, a spotify: URI, or a share link. Leave empty to just play/pause",
                          text: $linkDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($linkFieldFocused)
                    .onSubmit { commitLinkDraft() }
                    .onChange(of: linkFieldFocused) { _, focused in
                        if !focused { commitLinkDraft() }
                    }
                if onSaveSound != nil {
                    Button("Save…") {
                        commitLinkDraft()
                        savePromptName = ""
                        showSavePrompt = true
                    }
                    .disabled(linkDraft.isEmpty)
                    .help("Name this link and keep it in your Sound Library for reuse in any workspace")
                }
            }
            if linkDraft != externalPlaylistText {
                Text("Press Return (or click away) to apply the link.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Text(shareLinkExplanation)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .onAppear { linkDraft = externalPlaylistText }
        .onChange(of: sound.source) { _, _ in
            // Source changed underneath us (saved-sound pick, hot reload): resync the
            // draft unless the user is mid-edit in the field.
            if !linkFieldFocused { linkDraft = externalPlaylistText }
        }
        .alert("Save to Sound Library", isPresented: $showSavePrompt) {
            TextField("Name (e.g. Deep Focus Mix)", text: $savePromptName)
            Button("Save") {
                let name = savePromptName.isEmpty ? linkDraft : savePromptName
                onSaveSound?(name, sound.source ?? "")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved sounds appear in the Saved picker here and in Sound Library, so you never paste the same link twice.")
        }
    }

    /// Saved sounds usable in this picker (external sources only, any provider — picking
    /// one switches the provider automatically since the full source string is copied).
    private var externalSavedSounds: [SavedSound] {
        savedSounds.filter { $0.source.hasPrefix("external:") }
    }

    private var savedSelectionID: String {
        externalSavedSounds.first(where: { $0.source == sound.source })?.id ?? "custom"
    }

    private func commitLinkDraft() {
        let trimmed = linkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        linkDraft = trimmed
        guard trimmed != externalPlaylistText else { return }
        rebuildExternal(provider: externalProvider, playlist: trimmed)
    }

    private var shareLinkExplanation: String {
        "A pasted share link opens directly in the \(externalProvider == "spotify" ? "Spotify" : "Music") app on this Mac, not a browser. If that app isn't installed, it opens in your browser instead."
    }

    private func rebuildExternal(provider: String, playlist: String) {
        sound.source = playlist.isEmpty ? "external:\(provider):command" : "external:\(provider):playlist:\(playlist)"
    }

    // MARK: Shared rows

    private var volumeRow: some View {
        HStack {
            Text("Volume").foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Slider(value: $sound.volume, in: 0...1)
            Text("\(Int(sound.volume * 100))%").font(.caption).monospacedDigit().frame(width: 36)
        }
    }

    private var orderRepeatRow: some View {
        HStack {
            Picker("Order", selection: $sound.order) {
                Text("Sequential").tag(PlaybackOrder.sequential)
                Text("Shuffle").tag(PlaybackOrder.shuffle)
            }
            Picker("Repeat", selection: $sound.repeatMode) {
                Text("All").tag(RepeatMode.all)
                Text("One").tag(RepeatMode.one)
                Text("Off").tag(RepeatMode.off)
            }
        }
        .font(.caption)
    }

    private var actionRow: some View {
        HStack {
            Text("Action").foregroundStyle(.secondary)
            Picker("", selection: $sound.action) {
                Text("Play").tag(SoundAction.play)
                Text("Pause").tag(SoundAction.pause)
                Text("Stop").tag(SoundAction.stop)
                Text("Duck").tag(SoundAction.duck)
                Text("Resume previous").tag(SoundAction.resumePrevious)
                Text("Do nothing").tag(SoundAction.doNothing)
            }
            .labelsHidden()
        }
    }

    private var perAppOverrides: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Per-app volume").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(memberApps, id: \.self) { bundle in
                HStack {
                    if let icon = installedApps.first(where: { $0.bundleID == bundle })?.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(installedApps.first { $0.bundleID == bundle }?.name ?? bundle)
                        .font(.caption)
                    Spacer()
                    let has = sound.perApp[bundle]?.volume != nil
                    Toggle("", isOn: Binding(
                        get: { has },
                        set: { on in
                            if on { sound.perApp[bundle, default: PerAppOverride()].volume = sound.volume }
                            else { sound.perApp[bundle]?.volume = nil }
                        }
                    )).labelsHidden()
                    if has {
                        Slider(value: Binding(
                            get: { sound.perApp[bundle]?.volume ?? sound.volume },
                            set: { sound.perApp[bundle, default: PerAppOverride()].volume = $0 }
                        ), in: 0...1).frame(width: 100)
                    }
                }
            }
        }
    }

    private func sourceSuffix(after prefix: String) -> String? {
        guard let s = sound.source, s.hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count))
    }
}
