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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: controller.audioStatus == "silent" ? "speaker.slash" : "speaker.wave.2")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(controller.audioStatus).font(.callout.weight(.medium))
                Spacer()
            }
            if let issue = controller.audioIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.caption)
            }
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
            row("Desktop / Space", spaceLabel)
            row("In a meeting", meetingLabel)
            row("Focus mode", focusLabel)
        }
    }

    // A sensor that no enabled workspace references is off by design (lazy activation),
    // so say "not watched" rather than implying the feature is missing.
    private var spaceLabel: String {
        guard controller.spaceTracked else { return "not watched (no Space rule)" }
        return controller.context.activeSpace?.index.map { "Desktop \($0)" } ?? "detecting…"
    }
    private var meetingLabel: String {
        guard controller.meetingTracked else { return "not watched (no meeting rule)" }
        return (controller.context.cameraActive || controller.context.micActive) ? "Yes" : "No"
    }
    private var focusLabel: String {
        guard controller.focusTracked else { return "not watched (no Focus rule)" }
        return controller.context.focusMode ?? "None"
    }

    private var energy: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            row("Uptime", controller.uptimeString)
            row("Events observed", "\(controller.eventCount)")
            row("Active sensors", "\(activeSensorCount) of \(controller.sensorStatuses.count)")
            row("Memory (RSS)", memoryLabel)
            row("Steady-state polling", "none, all OS push")
        }
    }

    private var activeSensorCount: Int {
        controller.sensorStatuses.filter(\.running).count
    }

    private var memoryLabel: String {
        guard let mb = ProcessStats.residentMemoryMB() else { return "unavailable" }
        return String(format: "%.1f MB", mb)
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
        case .duck: return controller.isAudioPlaying ? "would duck" : "no change (nothing playing)"
        case .resumePrevious: return "would resume previous"
        case .doNothing: return "no change"
        }
    }
}

// MARK: - Preferences (real)

struct PreferencesPane: View {
    @EnvironmentObject var controller: AppController
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var diagnosticsOptIn = DiagnosticsPreference.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "General") {
                    Toggle("Launch Fadeo at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, v in
                            if !LoginItem.setEnabled(v) { launchAtLogin = LoginItem.isEnabled }
                        }
                    Toggle("Pause automation", isOn: $controller.automationPaused)
                }
                Card(title: "Privacy") {
                    Toggle("Share anonymous usage data", isOn: $diagnosticsOptIn)
                        .onChange(of: diagnosticsOptIn) { _, v in DiagnosticsPreference.isEnabled = v }
                    Text("A coarse summary only: session count, days used, workspace count, switches, and total active time. Never workspace names, app names, or file paths. Local usage tracking (Usage tab) always runs regardless of this setting. There's no server to send it to yet, so this toggle doesn't transmit anything today — it just records your preference for when that exists.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Card(title: "Configuration") {
                    HStack {
                        Text("config.yaml").font(.system(.callout, design: .monospaced))
                        Spacer()
                        Button("Reveal in Finder") { controller.configStore.revealInFinder() }
                    }
                    Text("Edit this file directly. Fadeo hot-reloads it. Or use the Workspaces editor.")
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
    @EnvironmentObject var licenseManager: LicenseManager
    @EnvironmentObject var softwareUpdater: SoftwareUpdater
    @State private var licenseKeyInput = ""
    @State private var showKeyEntry = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
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

                Divider().frame(width: 220).padding(.vertical, 6)
                licenseSection

                Divider().frame(width: 220).padding(.vertical, 6)
                updateSection

                Divider().frame(width: 220).padding(.vertical, 6)
                feedbackSection
            }
            .frame(maxWidth: .infinity)
            .padding(30)
        }
        .navigationTitle("About")
    }

    private var updateSection: some View {
        VStack(spacing: 6) {
            Button("Check for Updates…") { softwareUpdater.checkForUpdates() }
                .buttonStyle(.bordered)
                .disabled(!softwareUpdater.canCheckForUpdates)
            Toggle("Automatically check for updates", isOn: $softwareUpdater.automaticallyChecksForUpdates)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
    }

    private var feedbackSection: some View {
        VStack(spacing: 6) {
            Button("Send Feedback or Report a Bug") { openFeedbackEmail() }
                .buttonStyle(.bordered)
            Text("Opens your email client, addressed to me directly.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func openFeedbackEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "fadeo.puremac@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Fadeo feedback (v\(version))"),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private var licenseSection: some View {
        VStack(spacing: 10) {
            switch licenseManager.status {
            case .licensed:
                Label("Licensed · thank you", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.green)
            case .trial(let daysRemaining):
                Text("Trial · \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining")
                    .font(.callout).foregroundStyle(.secondary)
            case .trialExpired:
                Text("Trial ended").font(.callout).foregroundStyle(.secondary)
            }

            if !licenseManager.isLicensed {
                if showKeyEntry {
                    VStack(spacing: 8) {
                        TextField("FADEO1.\u{2026}", text: $licenseKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                            .frame(width: 280)
                        if let error = licenseManager.licenseError {
                            Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: 280)
                        }
                        HStack {
                            Button("Cancel") { showKeyEntry = false; licenseKeyInput = "" }
                            Button("Activate") { licenseManager.activate(licenseKeyInput) }
                                .buttonStyle(.borderedProminent)
                                .disabled(licenseKeyInput.isEmpty)
                        }
                    }
                } else {
                    HStack(spacing: 10) {
                        Button("Support Fadeo") {
                            if let url = URL(string: "https://puremac.yashashwi.me/fadeo") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Enter License Key") { showKeyEntry = true }
                    }
                }
            }
        }
    }
}

