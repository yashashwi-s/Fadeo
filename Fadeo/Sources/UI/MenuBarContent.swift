import SwiftUI
import FadeoCore

/// The always present menu bar companion. Sober and native: system colors, no tint, no
/// decoration. The only color is the workspace's own dot, which carries meaning.
struct MenuBarContent: View {
    @EnvironmentObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    private var activeWorkspace: Workspace? { controller.activeWorkspaceForDisplay }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if controller.canControlPlayback {
                playbackRow.padding(.vertical, 4)
                Divider()
            }

            pauseRow.padding(.vertical, 4)

            Divider()

            VStack(spacing: 1) {
                MenuRow(icon: "macwindow", title: "Open Fadeo") {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                MenuRow(icon: "folder", title: "Reveal Config") {
                    controller.configStore.revealInFinder()
                }
            }
            .padding(.vertical, 4)

            Divider()

            MenuRow(icon: "power", title: "Quit Fadeo") {
                NSApp.terminate(nil)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280)
        .padding(.bottom, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(activeWorkspace.map { Brand.swatch($0.color) } ?? Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(activeWorkspace?.name ?? "No workspace")
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(controller.automationPaused ? "Paused" : "Active")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 5) {
                Text(appName(controller.context.frontmostApp))
                Text("·").foregroundStyle(.tertiary)
                Text(controller.audioStatus)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.top, 12)
        .padding(.bottom, 11)
    }

    private var playbackRow: some View {
        HStack(spacing: 18) {
            Spacer()
            Button {
                controller.togglePlayPause()
            } label: {
                Image(systemName: controller.isAudioPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help(controller.isAudioPlaying ? "Pause" : "Play")

            Button {
                controller.skipNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .disabled(!controller.isAudioPlaying)
            .help("Skip")
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 13)
        .padding(.vertical, 2)
    }

    private var pauseRow: some View {
        HStack(spacing: 9) {
            Image(systemName: "bolt")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text("Automation")
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(
                get: { !controller.automationPaused },
                set: { controller.automationPaused = !$0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 4)
    }

    private func appName(_ bundle: String?) -> String {
        guard let bundle else { return "no app" }
        return bundle.split(separator: ".").last.map(String.init) ?? bundle
    }
}

/// Full width menu row with a neutral hover highlight (system selection tone, not a tint).
private struct MenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.07) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .onHover { hovering = $0 }
    }
}
