import SwiftUI
import FadeoCore

/// The always-present menu-bar companion. Clean, glanceable, minimal: what's active,
/// what it would do, a pause switch, and quick ways into the app.
struct MenuBarContent: View {
    @EnvironmentObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    private var activeWorkspace: Workspace? {
        controller.configStore.config.workspaces.first { $0.id == controller.decision?.activeWorkspace }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            VStack(spacing: 2) {
                pauseRow
            }
            .padding(.vertical, 4)

            Divider().opacity(0.6)

            VStack(spacing: 2) {
                MenuRow(icon: "macwindow", title: "Open Fadeo", shortcut: "⌘O") {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                MenuRow(icon: "folder", title: "Reveal config") {
                    controller.configStore.revealInFinder()
                }
            }
            .padding(.vertical, 4)

            Divider().opacity(0.6)

            MenuRow(icon: "power", title: "Quit Fadeo", tint: .secondary) {
                NSApp.terminate(nil)
            }
            .padding(.vertical, 4)
        }
        .frame(width: 292)
        .padding(.bottom, 4)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Circle()
                    .fill(Brand.swatch(activeWorkspace?.color))
                    .frame(width: 10, height: 10)
                    .shadow(color: Brand.swatch(activeWorkspace?.color).opacity(0.6), radius: 3)
                Text(activeWorkspace?.name ?? "No workspace")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                statusPill
            }

            HStack(spacing: 12) {
                metaItem(icon: "app.dashed", text: appName(controller.context.frontmostApp))
                metaItem(icon: "waveform", text: actionLabel, tint: Brand.teal)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 12)
    }

    private var statusPill: some View {
        let paused = controller.automationPaused
        return Text(paused ? "PAUSED" : "ACTIVE")
            .font(.system(size: 9, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(paused ? Color.orange : Brand.teal)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((paused ? Color.orange : Brand.teal).opacity(0.15), in: Capsule())
    }

    private func metaItem(icon: String, text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: Pause row

    private var pauseRow: some View {
        HStack(spacing: 10) {
            Image(systemName: controller.automationPaused ? "pause.circle.fill" : "bolt.fill")
                .font(.system(size: 14))
                .foregroundStyle(controller.automationPaused ? Color.orange : Brand.teal)
                .frame(width: 20)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    // MARK: Helpers

    private var actionLabel: String {
        guard let t = controller.decision?.target else { return "idle" }
        switch t.action {
        case .play: return "\(sourceShort(t.source)) · \(Int(t.volume * 100))%"
        case .pause: return "paused"
        case .stop: return "silent"
        case .resumePrevious: return "resume"
        case .doNothing: return "holding"
        default: return "—"
        }
    }

    private func sourceShort(_ s: String?) -> String {
        guard let s else { return "—" }
        return s.split(separator: ":").last.map(String.init) ?? s
    }

    private func appName(_ bundle: String?) -> String {
        guard let bundle else { return "—" }
        return bundle.split(separator: ".").last.map(String.init) ?? bundle
    }
}

/// A full-width menu row with a hover highlight — the building block for a clean,
/// native-feeling `.window`-style MenuBarExtra.
private struct MenuRow: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var tint: Color = .primary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(hovering ? Brand.teal : .secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(tint)
                Spacer()
                if let shortcut {
                    Text(shortcut).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(hovering ? Brand.teal.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }
}
