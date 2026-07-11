import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
    /// Audition a sound through the controller's dedicated preview engine.
    var onTogglePreview: ((Sound) -> Void)?
    /// The source currently previewing (from the controller), to show play/stop state.
    var previewingSource: String?

    /// Local draft of the external link/playlist text. Committing on submit/blur (not
    /// every keystroke) matters: each save re-evaluates, and if this workspace is
    /// active, a half-typed URL would fire a real handoff to Music/Spotify mid-typing.
    @State private var linkDraft: String = ""
    @FocusState private var linkFieldFocused: Bool
    @State private var showSavePrompt = false
    @State private var savePromptName = ""

    /// The kind the user picked before its source exists yet. Without this, choosing
    /// "A file"/"A folder" self-destructed: the pick set `source = nil` (waiting for the
    /// Choose… dialog), the picker's selection re-derived the kind from that nil source
    /// as "Nothing", and the file row never appeared. Derived state needs this one bit
    /// of memory for the not-yet-configured case.
    @State private var pendingKind: Kind?

    /// File/folder selection uses SwiftUI's declarative `.fileImporter`, driven by these
    /// two flags, rather than presenting `NSOpenPanel` imperatively from the picker's
    /// setter. The old approach opened the panel from a `DispatchQueue.main.async` inside
    /// the Picker's `set`, which double-presented (the panel appeared twice, the first
    /// pick not sticking) because a config-save re-render re-entered the setter mid-modal.
    /// A `.fileImporter` bound to a Bool can't double-present — setting the flag true
    /// twice is idempotent — and it never blocks the run loop.
    @State private var showFileImporter = false
    @State private var importingFolder = false

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

    private static let presets = ["brown-noise", "pink-noise", "white-noise", "rain", "ocean", "wind", "fan"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !savedSounds.isEmpty {
                librarySelector
            }

            Picker("Source", selection: kindBinding) {
                ForEach(availableKinds) { Text($0.label).tag($0) }
            }
            .labelsHidden()

            switch displayedKind {
            case .preset: presetPicker
            case .file: pathPicker(isFolder: false)
            case .folder: pathPicker(isFolder: true)
            case .playlist: playlistPicker
            case .external: externalPicker
            case .silence: EmptyView()
            }

            if displayedKind != .silence {
                playbackControls
                volumeRow
                previewRow
            }

            actionRow

            if !memberApps.isEmpty {
                Divider()
                perAppOverrides
            }
        }
        .alert("Save to Sound Library", isPresented: $showSavePrompt) {
            TextField("Name (e.g. Deep Focus Mix)", text: $savePromptName)
            Button("Save") {
                let fallback = suggestedSaveName()
                let name = savePromptName.isEmpty ? fallback : savePromptName
                onSaveSound?(name, sound.source ?? "")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved sounds appear in the library picker above and in Sound Library, so you never set this up twice.")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: importingFolder ? [.folder] : [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    sound.source = (importingFolder ? "internal:folder:" : "internal:file:") + url.path
                    sound.action = .play
                }
                pendingKind = nil   // the source now carries the kind (or the pick was empty)
            case .failure:
                pendingKind = nil   // cancelled/failed: fall back to the real current source
            }
        }
    }

    private func suggestedSaveName() -> String {
        guard let s = sound.source else { return "Untitled" }
        if s.hasPrefix("internal:file:") || s.hasPrefix("internal:folder:") {
            let path = s.split(separator: ":", maxSplits: 2).map(String.init).last ?? s
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return linkDraft.isEmpty ? s : linkDraft
    }

    // MARK: Library (saved sounds, any kind)

    /// One picker across every saved sound — link, file, or folder. Picking one copies
    /// its full source string; the kind row below follows automatically.
    private var librarySelector: some View {
        Picker("From your library", selection: Binding(
            get: { savedSounds.first(where: { $0.source == sound.source })?.id ?? "custom" },
            set: { id in
                guard id != "custom", let saved = savedSounds.first(where: { $0.id == id }) else { return }
                pendingKind = nil
                sound.source = saved.source
                sound.action = .play
                linkDraft = externalPlaylistText
            }
        )) {
            Text("Choose below…").tag("custom")
            ForEach(savedSounds) { Text($0.name).tag($0.id) }
        }
    }

    /// The playlist kind only appears while old configs still reference it — the
    /// standalone playlists UI was removed in favor of saved sounds.
    private var availableKinds: [Kind] {
        Kind.allCases.filter { $0 != .playlist || !allPlaylists.isEmpty || displayedKind == .playlist }
    }

    // MARK: Kind

    /// What the source string says the kind is. `nil`/empty is "Nothing".
    private var currentKind: Kind {
        guard let s = sound.source, !s.isEmpty else { return .silence }
        if s.hasPrefix("internal:preset:") { return .preset }
        if s.hasPrefix("internal:file:") { return .file }
        if s.hasPrefix("internal:folder:") { return .folder }
        if s.hasPrefix("internal:playlist:") { return .playlist }
        if s.hasPrefix("external:") { return .external }
        return .silence
    }

    /// What the UI shows: the user's not-yet-configured pick wins over the derived kind.
    private var displayedKind: Kind {
        pendingKind ?? currentKind
    }

    private var kindBinding: Binding<Kind> {
        Binding(
            get: { displayedKind },
            set: { newKind in
                switch newKind {
                case .preset:
                    pendingKind = nil
                    sound.source = "internal:preset:\(Self.presets[0])"
                case .file, .folder:
                    // Remember the pick so the row shows File/Folder, and open the system
                    // chooser right away — "A file" means "let me pick a file". The old
                    // source is left intact until a pick actually commits, so cancelling
                    // changes nothing. Declarative .fileImporter (see body) does the rest.
                    pendingKind = newKind
                    importingFolder = (newKind == .folder)
                    showFileImporter = true
                case .playlist:
                    pendingKind = nil
                    sound.source = allPlaylists.first.map { "internal:playlist:\($0.id)" }
                case .external:
                    pendingKind = nil
                    sound.source = "external:appleMusic:command"
                case .silence:
                    pendingKind = nil
                    sound.source = nil
                    sound.action = .pause
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
        case "ocean": return "Ocean waves"
        case "wind": return "Wind"
        case "fan": return "Fan / hum"
        default: return p
        }
    }

    // MARK: File / folder

    private func pathPicker(isFolder: Bool) -> some View {
        let hasPath = sourceSuffix(after: isFolder ? "internal:folder:" : "internal:file:") != nil
        return HStack {
            Text(sourceSuffix(after: isFolder ? "internal:folder:" : "internal:file:").map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "No \(isFolder ? "folder" : "file") chosen yet")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(hasPath ? "Change…" : "Choose…") {
                importingFolder = isFolder
                showFileImporter = true
            }
            if onSaveSound != nil && hasPath {
                Button("Save…") {
                    savePromptName = ""
                    showSavePrompt = true
                }
                .help("Name this and keep it in your Sound Library for reuse in any workspace")
            }
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

    // MARK: Playback controls (per source kind)

    @ViewBuilder
    private var playbackControls: some View {
        switch displayedKind {
        case .file:
            // A single file: loop it, or play once and fall silent.
            Toggle("Loop", isOn: Binding(
                get: { sound.repeatMode != .off },
                set: { sound.repeatMode = $0 ? .one : .off }
            ))
            .font(.callout)
        case .folder, .playlist:
            HStack(spacing: 16) {
                Picker("Order", selection: $sound.order) {
                    Text("In order").tag(PlaybackOrder.sequential)
                    Text("Shuffle").tag(PlaybackOrder.shuffle)
                }
                Picker("Repeat", selection: $sound.repeatMode) {
                    Text("All").tag(RepeatMode.all)
                    Text("One").tag(RepeatMode.one)
                    Text("Off").tag(RepeatMode.off)
                }
            }
            .font(.caption)
        case .external:
            // Fadeo sets these on Music/Spotify itself when the workspace activates.
            HStack(spacing: 16) {
                Toggle("Shuffle", isOn: Binding(
                    get: { sound.order == .shuffle },
                    set: { sound.order = $0 ? .shuffle : .sequential }
                ))
                Picker("Repeat", selection: $sound.repeatMode) {
                    Text("Off").tag(RepeatMode.off)
                    Text("Track").tag(RepeatMode.one)
                    Text("All").tag(RepeatMode.all)
                }
                .frame(maxWidth: 160)
            }
            .font(.callout)
        case .preset, .silence:
            EmptyView()
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var previewRow: some View {
        // Preview only internal sources; auditioning external would drive the same
        // Music/Spotify session the workspace uses (see AppController.togglePreview).
        if let onTogglePreview, let source = sound.source, source.hasPrefix("internal:") {
            let isPreviewingThis = (previewingSource == source)
            HStack(spacing: 8) {
                Button {
                    onTogglePreview(sound)
                } label: {
                    Label(isPreviewingThis ? "Stop preview" : "Preview",
                          systemImage: isPreviewingThis ? "stop.fill" : "play.fill")
                }
                if isPreviewingThis {
                    Text("Auditioning — the live workspace audio resumes when you stop.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
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
