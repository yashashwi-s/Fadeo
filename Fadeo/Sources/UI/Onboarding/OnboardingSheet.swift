import SwiftUI

/// First-run explanation. Kept to one screen deliberately: today's real permission
/// surface is thin (Automation prompts macOS shows natively; camera/mic *usage*
/// detection and the Focus-mode file read need no permission at all), so a multi-step
/// wizard would be padding, not substance. Says what Fadeo does, what it might ask for
/// and why, and gets out of the way.
struct OnboardingSheet: View {
    @Binding var isPresented: Bool
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var diagnosticsOptIn = DiagnosticsPreference.isEnabled

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image("AppLogo").resizable().scaledToFit().frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Welcome to Fadeo").font(.title2.weight(.semibold))
                Text("Fadeo watches what you're doing and plays, switches, or fades sound to match, silently, in the background.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            .padding(.top, 32).padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 14) {
                permissionRow(
                    icon: "music.note.list", title: "Controlling Spotify or Apple Music",
                    detail: "macOS will ask you to approve this the first time a workspace needs it (Automation). Fadeo only sends play, pause, and volume commands. Nothing is read or uploaded."
                )
                permissionRow(
                    icon: "video", title: "Camera & microphone",
                    detail: "Fadeo only checks whether they're in use, to detect meetings. It never opens or records from either, so no permission prompt happens for this."
                )
                permissionRow(
                    icon: "moon", title: "Focus mode",
                    detail: "Read locally to match workspaces against it. No permission needed, nothing leaves your Mac."
                )
            }
            .padding(.horizontal, 32)

            Divider().padding(.vertical, 20)

            Toggle("Launch Fadeo at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, v in LoginItem.setEnabled(v) }
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Help improve Fadeo with anonymous usage data", isOn: $diagnosticsOptIn)
                    .onChange(of: diagnosticsOptIn) { _, v in DiagnosticsPreference.isEnabled = v }
                Text(privacyExplanation)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32).padding(.top, 12)

            Spacer(minLength: 20)

            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: OnboardingSheet.completedKey)
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 28)
        }
        .frame(width: 460)
    }

    private var privacyExplanation: String {
        "Fadeo always tracks your own usage locally so you can see it (Usage tab). This toggle only prepares a coarse summary for future sharing (session count, days used, number of workspaces, total switches, total active time, never workspace or app names, file paths, or anything else on your Mac) — there's no server to send it to yet, so turning this on doesn't transmit anything today. Change this anytime in Preferences."
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static let completedKey = "fadeo.onboarding.completed"
    static var hasCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }
}
