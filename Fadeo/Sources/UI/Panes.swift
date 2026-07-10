import SwiftUI
import FadeoCore

// MARK: - Reusable card

struct Card<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Now / live dashboard

struct NowPane: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Card(title: "Active workspace") { activeWorkspace }
                Card(title: "Audio") { audio }
                Card(title: "Why") {
                    Text(controller.decision?.reason.explanation ?? "Evaluating…")
                        .font(.callout)
                        .textSelection(.enabled)
                }
                Card(title: "Live context") { liveContext }
                Card(title: "Energy") { energy }
                Card(title: "Recent events (push, zero polling)") { events }
            }
            .padding(20)
        }
        .navigationTitle("Now")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Fadeo is watching").font(.title3.weight(.semibold))
                Text("app focus, context, resolve, decision")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var audio: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.audioStatus == "silent" ? "speaker.slash" : "speaker.wave.2")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(controller.audioStatus).font(.callout.weight(.medium))
            Spacer()
        }
    }

    private var activeWorkspace: some View {
        HStack(spacing: 12) {
            let ws = controller.configStore.config.workspaces.first { $0.id == controller.decision?.activeWorkspace }
            Circle().fill(Brand.swatch(ws?.color)).frame(width: 14, height: 14)
            Text(ws?.name ?? "None").font(.title2.weight(.medium))
            Spacer()
            if let d = controller.decision {
                VStack(alignment: .trailing) {
                    Text(actionLabel(d.target)).font(.callout.weight(.medium))
                    if let src = d.target.source {
                        Text(src).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var liveContext: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            row("Frontmost app", controller.context.frontmostApp ?? "none")
            row("Desktop / Space", controller.context.activeSpace?.index.map { "Desktop \($0)" } ?? "not yet (M3)")
            row("In a meeting", controller.context.cameraActive || controller.context.micActive ? "Yes" : "not yet (M3)")
            row("Focus mode", controller.context.focusMode ?? "not yet (M3)")
        }
    }

    private var energy: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            row("Uptime", controller.uptimeString)
            row("Events observed", "\(controller.eventCount)")
            row("Steady-state polling", "none — all OS push")
        }
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: 4) {
            if controller.recentEvents.isEmpty {
                Text("Switch apps to see events arrive…").foregroundStyle(.secondary).font(.callout)
            } else {
                ForEach(Array(controller.recentEvents.prefix(12).enumerated()), id: \.offset) { _, e in
                    Text(e).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).fontWeight(.medium)
        }
    }

    private func actionLabel(_ t: AudioTarget) -> String {
        switch t.action {
        case .play: return "would play · vol \(Int(t.volume * 100))%"
        case .pause: return "would pause"
        case .stop: return "would stop"
        case .setVolume: return "would set volume"
        case .duck: return "would duck"
        case .resumePrevious: return "would resume previous"
        case .doNothing: return "no change"
        }
    }
}

// MARK: - Preferences (real)

struct PreferencesPane: View {
    @EnvironmentObject var controller: AppController
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "General") {
                    Toggle("Launch Fadeo at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, v in LoginItem.setEnabled(v) }
                    Toggle("Pause automation", isOn: $controller.automationPaused)
                }
                Card(title: "Configuration") {
                    HStack {
                        Text("config.json").font(.system(.callout, design: .monospaced))
                        Spacer()
                        Button("Reveal in Finder") { controller.configStore.revealInFinder() }
                    }
                    Text("Edit this file directly — Fadeo hot-reloads it. Or use the Workspaces editor (M4).")
                        .font(.caption).foregroundStyle(.secondary)
                    if let err = controller.configStore.lastError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Preferences")
    }
}

// MARK: - About

struct AboutPane: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image("AppLogo").resizable().scaledToFit().frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text("Fadeo").font(.largeTitle.weight(.semibold))
            Text("The right sound for what you're doing.").foregroundStyle(.secondary)
            Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
            Divider().frame(width: 220).padding(.vertical, 6)
            VStack(spacing: 4) {
                Text("Open source · GPLv3").font(.callout.weight(.medium))
                Text("Fully functional. A gentle reminder appears until licensed, never a lockout.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .navigationTitle("About")
    }
}

// MARK: - Placeholder for not-yet-built panes

struct PlaceholderPane: View {
    let pane: Pane
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: pane.systemImage).font(.system(size: 38)).foregroundStyle(.secondary)
            Text(pane.rawValue).font(.title2.weight(.semibold))
            if let m = pane.milestone {
                Text("Coming in \(m)")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }
            Text(blurb).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(pane.rawValue)
    }

    private var blurb: String {
        switch pane {
        case .workspaces: return "Create workspaces, drag apps in, set the sound, tune fades and per-app overrides."
        case .soundLibrary: return "Connect Spotify / Apple Music, add your own files, and the bundled ambient starter set."
        case .precedence: return "Order the tiebreak chain, pick the fallback, and simulate conflicts before they happen."
        case .triggers: return "Toggle sensors, define what counts as a meeting, and name your Spaces."
        case .advanced: return "Two-way YAML editor, import/export, logs, and the rule inspector."
        default: return ""
        }
    }
}
