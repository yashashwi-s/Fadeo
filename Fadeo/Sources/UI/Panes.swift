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
    @State private var notificationsEnabled = NotificationsPreference.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "General") {
                    Toggle("Launch Fadeo at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, v in
                            if !LoginItem.setEnabled(v) { launchAtLogin = LoginItem.isEnabled }
                        }
                    Toggle("Pause automation", isOn: $controller.automationPaused)
                    Toggle("Notifications (updates, config errors)", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, v in NotificationsPreference.isEnabled = v }
                }
                Card(title: "Privacy") {
                    Toggle("Share anonymous usage data", isOn: $diagnosticsOptIn)
                        .onChange(of: diagnosticsOptIn) { _, v in DiagnosticsPreference.isEnabled = v }
                    Text("A coarse summary only: session count, days used, workspace count, switches, and total active time. Never workspace names, app names, or file paths. Local usage tracking (Usage tab) always runs regardless of this setting; only this coarse summary is sent, at most once a day.")
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
    @EnvironmentObject var controller: AppController
    @State private var licenseKeyInput = ""
    @State private var showKeyEntry = false
    @State private var rating = RatingPreference.value ?? 0
    @State private var feedbackText = ""
    @State private var sendState: SendState = .idle

    private enum SendState: Equatable { case idle, sending, sent, failed }

    private var shortVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    private var version: String {
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                Card(title: "License") { licenseSection }
                Card(title: "Rate & feedback") { ratingSection }
                Card(title: "Updates") { updatesSection }
                Card(title: "About") { aboutLinksSection }
            }
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .navigationTitle("About")
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image("AppLogo").resizable().scaledToFit().frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Text("Fadeo").font(.title.weight(.semibold))
            Text("The right sound for what you're doing.").font(.callout).foregroundStyle(.secondary)
            Text("Version \(version)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
    }

    // MARK: Rating + feedback

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(i <= rating ? Color.yellow : Color.secondary)
                        .onTapGesture { rating = i; RatingPreference.value = i }
                }
                if rating > 0 {
                    Text("Thanks!").font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
                }
            }
            TextEditor(text: $feedbackText)
                .font(.callout)
                .frame(height: 72)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .overlay(alignment: .topLeading) {
                    if feedbackText.isEmpty {
                        Text("Anything you'd like me to know? Bugs, ideas, a texture you want…")
                            .font(.callout).foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                Button(sendState == .sending ? "Sending…" : "Send feedback") { sendFeedback() }
                    .buttonStyle(.borderedProminent)
                    .disabled(sendState == .sending || (feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && rating == 0))
                switch sendState {
                case .sent: Label("Sent, thank you", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                case .failed: Label("Couldn't send. Try email below.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                default: EmptyView()
                }
            }
            Text("Sent anonymously (a random install id, no personal data) so I can see it and improve Fadeo.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func sendFeedback() {
        sendState = .sending
        let ratingToSend = rating > 0 ? rating : nil
        FeedbackSender.send(installID: controller.usageStore.stats.installID,
                            rating: ratingToSend,
                            text: feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)) { ok in
            sendState = ok ? .sent : .failed
            if ok { feedbackText = "" }
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You're on \(shortVersion). Fadeo checks for updates daily and notifies you.")
                .font(.callout)
            Text("Installed via Homebrew? Update with brew upgrade --cask fadeo. Otherwise download the latest from the releases page.")
                .font(.caption).foregroundStyle(.secondary)
            Button("View releases") {
                if let url = URL(string: "https://github.com/yashashwi-s/Fadeo/releases/latest") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }

    // MARK: About / links

    private var aboutLinksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open source · GPLv3").font(.callout.weight(.medium))
            Text("Fully functional. A gentle reminder appears until licensed, never a lockout.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button("Source on GitHub") {
                    if let url = URL(string: "https://github.com/yashashwi-s/Fadeo") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
                Button("Email me") { openFeedbackEmail() }
                    .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    private func openFeedbackEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "fadeo.puremac@gmail.com"
        components.queryItems = [URLQueryItem(name: "subject", value: "Fadeo feedback (v\(shortVersion))")]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    // MARK: License

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch licenseManager.status {
            case .licensed:
                Label("Licensed · thank you", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.green)
            case .trial(let daysRemaining):
                Text("Trial · \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining")
                    .font(.callout).foregroundStyle(.secondary)
            case .trialExpired:
                Text("Trial ended · Fadeo keeps working").font(.callout).foregroundStyle(.secondary)
            }

            if !licenseManager.isLicensed {
                if showKeyEntry {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("FADEO1.\u{2026}", text: $licenseKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                        if let error = licenseManager.licenseError {
                            Text(error).font(.caption).foregroundStyle(.red)
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
                        Button("Support Fadeo ($2)") {
                            if let url = URL(string: "https://puremac.yashashwi.me/fadeo") { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Enter License Key") { showKeyEntry = true }
                    }
                }
            }
        }
    }
}

