import SwiftUI
import FadeoCore

/// Raw two-way YAML editor — the power-user surface. Note the one real tradeoff: every
/// GUI edit elsewhere (Workspaces, Precedence, ...) regenerates the whole file from the
/// `Config` model and will silently drop any comments you hand-add here. Comments survive
/// as long as you stick to this pane, or don't mind them being lost on the next GUI edit.
struct AdvancedPane: View {
    @EnvironmentObject var controller: AppController
    @State private var text: String = ""
    @State private var localError: String?
    @State private var savedFlash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .padding(8)
            Divider()
            footer
        }
        .onAppear { reload() }
        .navigationTitle("Advanced")
    }

    private var header: some View {
        HStack {
            Text("config.yaml").font(.system(.callout, design: .monospaced))
            Spacer()
            Button("Reveal in Finder") { controller.configStore.revealInFinder() }
            Button("Reload") { reload() }
            Button("Save") { save() }.keyboardShortcut("s", modifiers: .command)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if let localError {
                Label(localError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else if savedFlash {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Editing here preserves comments. Editing other panes regenerates the whole file and drops them.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(10)
    }

    private func reload() {
        if let data = try? ConfigCodec.encode(controller.configStore.config),
           let string = String(data: data, encoding: .utf8) {
            text = string
        }
        localError = nil
    }

    private func save() {
        do {
            let cfg = try ConfigCodec.decode(string: text)
            controller.configStore.save(cfg)
            localError = nil
            savedFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
        } catch {
            localError = "Invalid YAML: \(error.localizedDescription)"
        }
    }
}
