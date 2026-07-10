import SwiftUI
import FadeoCore

struct PrecedencePane: View {
    @EnvironmentObject var controller: AppController

    private var config: Config { controller.configStore.config }
    private var settingsBinding: Binding<FadeoCore.Settings> {
        Binding(
            get: { controller.configStore.config.settings },
            set: { newValue in
                var cfg = controller.configStore.config
                cfg.settings = newValue
                controller.configStore.save(cfg)
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tiebreakCard
                fallbackCard
                defaultsCard
                ConflictSimulator(config: config)
            }
            .padding(20)
        }
        .navigationTitle("Precedence")
    }

    // MARK: Tiebreak chain

    private var tiebreakCard: some View {
        Card(title: "Tiebreak order — when multiple workspaces match at once") {
            VStack(alignment: .leading, spacing: 4) {
                List {
                    ForEach(settingsBinding.tiebreak) { $strategy in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Text(label(strategy)).font(.callout)
                            Spacer()
                        }
                    }
                    .onMove { indices, offset in
                        var chain = settingsBinding.wrappedValue.tiebreak
                        chain.move(fromOffsets: indices, toOffset: offset)
                        settingsBinding.wrappedValue.tiebreak = chain
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(settingsBinding.wrappedValue.tiebreak.count * 30 + 10))
                Text("Drag to reorder. Applied top to bottom until one workspace wins.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func label(_ s: TiebreakStrategy) -> String {
        switch s {
        case .stickiness: return "Stickiness — keep the current workspace if it still matches"
        case .specificity: return "Specificity — the more constrained match wins"
        case .priority: return "Priority — your explicit rank"
        case .recency: return "Recency — whichever was active most recently"
        case .stableId: return "Stable order (always decides — not reorderable)"
        }
    }

    // MARK: Fallback

    private var fallbackCard: some View {
        Card(title: "Fallback — when nothing matches") {
            Picker("", selection: settingsBinding.fallback) {
                Text("Keep current audio").tag(Fallback.keepCurrent)
                Text("Resume previous").tag(Fallback.resumePrevious)
                Text("Fade to silence").tag(Fallback.silence)
            }
            .labelsHidden().pickerStyle(.radioGroup)

            Divider().padding(.vertical, 4)

            HStack {
                Text("Meeting trigger").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: settingsBinding.meeting) {
                    Text("Camera or mic").tag(MeetingTrigger.cameraOrMic)
                    Text("Camera and mic").tag(MeetingTrigger.cameraAndMic)
                    Text("Camera only").tag(MeetingTrigger.cameraOnly)
                    Text("Mic only").tag(MeetingTrigger.micOnly)
                }
                .labelsHidden().frame(width: 180)
            }
        }
    }

    // MARK: Global timing defaults

    private var defaultsCard: some View {
        Card(title: "Global timing defaults") {
            VStack(alignment: .leading, spacing: 8) {
                defaultRow("Fade in", settingsBinding.defaults.fadeInMs, 0...5000)
                defaultRow("Fade out", settingsBinding.defaults.fadeOutMs, 0...5000)
                defaultRow("Crossfade", settingsBinding.defaults.crossfadeMs, 0...5000)
                defaultRow("Enter delay", settingsBinding.defaults.enterDelayMs, 0...10000)
                defaultRow("Exit delay", settingsBinding.defaults.exitDelayMs, 0...10000)
                defaultRow("Minimum dwell", settingsBinding.defaults.minDwellMs, 0...60000)
                defaultRow("Evaluation debounce", settingsBinding.evaluationDebounceMs, 0...2000)
                Text("Any workspace can override these individually in its own Timing section.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func defaultRow(_ label: String, _ value: Binding<Int>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }), in: range)
            Text("\(value.wrappedValue) ms").font(.caption).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
        .font(.callout)
    }
}

extension TiebreakStrategy: Identifiable { public var id: String { rawValue } }
