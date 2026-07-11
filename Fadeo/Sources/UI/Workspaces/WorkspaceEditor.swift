import SwiftUI
import AppKit
import FadeoCore

struct WorkspaceEditor: View {
    @Binding var workspace: Workspace
    let installedApps: [InstalledApp]
    let allPlaylists: [LocalPlaylist]
    var savedSounds: [SavedSound] = []
    var onSaveSound: ((String, String) -> Void)?
    var onTogglePreview: ((Sound) -> Void)?
    var previewingSource: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identityCard
                matchCard
                soundCard
                timingCard
            }
            .padding(20)
        }
    }

    // MARK: Identity

    private var identityCard: some View {
        Card(title: "Identity") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Name", text: $workspace.name).textFieldStyle(.roundedBorder)
                    ColorPicker("", selection: Binding(
                        get: { Color(hexString: workspace.color ?? "#67E4D2") ?? Brand.teal },
                        set: { workspace.color = $0.toHexString() }
                    )).labelsHidden().frame(width: 30)
                }
                HStack(spacing: 16) {
                    Toggle("Enabled", isOn: $workspace.enabled)
                    Toggle("Override (pre-empts everything else)", isOn: $workspace.isOverride)
                }
                HStack {
                    Text("Priority").foregroundStyle(.secondary)
                    Stepper(value: $workspace.priority, in: 0...100) {
                        Text("\(workspace.priority)").monospacedDigit()
                    }
                }
                Text("Used to break ties when multiple workspaces match at once. See Precedence.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Match

    private var matchCard: some View {
        Card(title: "Match: when this workspace activates") {
            VStack(alignment: .leading, spacing: 14) {
                if workspace.match.isEmpty {
                    Label(
                        "No conditions set. This workspace never activates until you add an app, Space, or other condition.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.orange)
                }
                appsSection
                Divider()
                spacesSection
                Divider()
                meetingSection
                Divider()
                focusSection
                Divider()
                timeSection
                Divider()
                weekdaySection
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(workspace.match.apps, id: \.bundle) { entry in
                HStack {
                    Image(nsImage: appIcon(entry.bundle))
                        .resizable().frame(width: 18, height: 18)
                    Text(appName(entry.bundle))
                    Spacer()
                    Picker("", selection: strengthBinding(entry.bundle)) {
                        Text("Strong").tag(MembershipStrength.strong)
                        Text("Weak").tag(MembershipStrength.weak)
                    }
                    .labelsHidden().frame(width: 100)
                    Button { workspace.match.apps.removeAll { $0.bundle == entry.bundle } } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            HStack {
                AppPickerButton(label: "Add App", apps: installedApps) { app in
                    if let app { addApp(app.bundleID) }
                }
                Button("Capture Frontmost") {
                    if let app = InstalledApps.frontmost() { addApp(app.bundleID) }
                }
            }
            .font(.caption)
            Text("Weak apps never pull you into this workspace. They only keep it playing if it's already active.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var spacesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Desktop / Space").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                ForEach(workspace.match.spaces, id: \.self) { s in
                    HStack(spacing: 4) {
                        Text("Desktop \(s)")
                        Image(systemName: "xmark").font(.system(size: 7))
                    }
                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .onTapGesture { workspace.match.spaces.removeAll { $0 == s } }
                }
                Menu("Add desktop") {
                    ForEach(1...16, id: \.self) { n in
                        Button("Desktop \(n)") {
                            if !workspace.match.spaces.contains(n) {
                                workspace.match.spaces.append(n)
                                workspace.match.spaces.sort()
                            }
                        }.disabled(workspace.match.spaces.contains(n))
                    }
                }.font(.caption)
            }
            Text("Tap a chip to remove it. Leave empty to ignore Space.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var meetingSection: some View {
        HStack {
            Text("Meeting").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { workspace.match.meeting.map { $0 ? "in" : "out" } ?? "any" },
                set: { workspace.match.meeting = $0 == "any" ? nil : $0 == "in" }
            )) {
                Text("Any").tag("any")
                Text("In a meeting").tag("in")
                Text("Not in a meeting").tag("out")
            }
            .labelsHidden().frame(width: 180)
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Focus mode").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Use current") {
                    if let mode = FocusSensor.currentModeIdentifierForUI() {
                        if !workspace.match.focus.contains(mode) { workspace.match.focus.append(mode) }
                    }
                }.font(.caption)
            }
            ForEach(workspace.match.focus, id: \.self) { f in
                HStack {
                    Text(f).font(.caption).lineLimit(1)
                    Spacer()
                    Button { workspace.match.focus.removeAll { $0 == f } } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Text("Leave empty to ignore Focus mode.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Time window").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { workspace.match.timeBetween != nil },
                    set: { workspace.match.timeBetween = $0 ? TimeWindow(start: "09:00", end: "18:00") : nil }
                )).labelsHidden()
            }
            if workspace.match.timeBetween != nil {
                HStack {
                    timeField("Start", \.start)
                    Text("–").foregroundStyle(.secondary)
                    timeField("End", \.end)
                }
            }
        }
    }

    private func timeField(_ label: String, _ keyPath: WritableKeyPath<TimeWindow, String>) -> some View {
        TextField(label, text: Binding(
            get: { workspace.match.timeBetween?[keyPath: keyPath] ?? "" },
            set: {
                guard workspace.match.timeBetween != nil else { return }
                workspace.match.timeBetween![keyPath: keyPath] = $0
            }
        ))
        .textFieldStyle(.roundedBorder).frame(width: 70)
    }

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weekdays").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { day in
                    let on = workspace.match.weekdays.contains(day)
                    Text(weekdayLabel(day))
                        .font(.caption2.weight(on ? .bold : .regular))
                        .frame(width: 30, height: 24)
                        .background(on ? Color.primary.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .onTapGesture {
                            if on { workspace.match.weekdays.removeAll { $0 == day } }
                            else { workspace.match.weekdays.append(day) }
                        }
                }
            }
            Text("Leave empty to ignore day of week.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: Sound

    private var soundCard: some View {
        Card(title: "Sound") {
            SoundEditor(sound: $workspace.sound, memberApps: workspace.match.apps.map(\.bundle),
                       installedApps: installedApps, allPlaylists: allPlaylists,
                       savedSounds: savedSounds, onSaveSound: onSaveSound,
                       onTogglePreview: onTogglePreview, previewingSource: previewingSource)
        }
    }

    // MARK: Timing

    private var timingCard: some View {
        Card(title: "Timing overrides") {
            TimingEditor(timing: $workspace.timing)
        }
    }

    private func appIcon(_ bundle: String) -> NSImage {
        if let app = installedApps.first(where: { $0.bundleID == bundle }) { return app.icon }
        // Not in the scanned list (e.g. a hand-typed or since-removed bundle id). Ask
        // LaunchServices directly rather than showing nothing.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    private func appName(_ bundle: String) -> String {
        installedApps.first { $0.bundleID == bundle }?.name ?? bundle
    }

    private func addApp(_ bundle: String) {
        guard !workspace.match.apps.contains(where: { $0.bundle == bundle }) else { return }
        workspace.match.apps.append(AppMembership(bundle: bundle, strength: .strong))
    }

    private func strengthBinding(_ bundle: String) -> Binding<MembershipStrength> {
        Binding(
            get: { workspace.match.apps.first(where: { $0.bundle == bundle })?.strength ?? .strong },
            set: { newValue in
                if let idx = workspace.match.apps.firstIndex(where: { $0.bundle == bundle }) {
                    workspace.match.apps[idx].strength = newValue
                }
            }
        )
    }

    private func weekdayLabel(_ d: Int) -> String {
        ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d]
    }
}
