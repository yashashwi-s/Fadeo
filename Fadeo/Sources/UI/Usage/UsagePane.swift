import SwiftUI
import FadeoCore

/// Your own "screen time for sound": how long each workspace has actually been active,
/// and how often you switch. Useful to you directly, not just diagnostics for the
/// developer. Updates when you switch workspaces, not on a live-ticking timer.
struct UsagePane: View {
    @EnvironmentObject var controller: AppController
    @ObservedObject var usageStore: UsageStore

    private var config: Config { controller.configStore.config }

    private var sortedUsage: [(id: String, name: String, color: String?, usage: WorkspaceUsage)] {
        usageStore.stats.perWorkspace
            .map { id, usage -> (String, String, String?, WorkspaceUsage) in
                let ws = config.workspaces.first { $0.id == id }
                return (id, ws?.name ?? id, ws?.color, usage)
            }
            .sorted { $0.3.totalSeconds > $1.3.totalSeconds }
    }

    private var totalSeconds: Double {
        usageStore.stats.perWorkspace.values.reduce(0) { $0 + $1.totalSeconds }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                perWorkspaceCard
            }
            .padding(20)
        }
        .navigationTitle("Usage")
    }

    private var summaryCard: some View {
        Card(title: "Overview") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Total active time").foregroundStyle(.secondary)
                    Text(formatDuration(totalSeconds)).fontWeight(.medium)
                }
                GridRow {
                    Text("Workspace switches").foregroundStyle(.secondary)
                    Text("\(usageStore.stats.totalSwitches)").fontWeight(.medium)
                }
                GridRow {
                    Text("Sessions").foregroundStyle(.secondary)
                    Text("\(usageStore.stats.sessionCount)").fontWeight(.medium)
                }
                GridRow {
                    Text("Tracking since").foregroundStyle(.secondary)
                    Text(usageStore.stats.firstLaunch, style: .date).fontWeight(.medium)
                }
            }
        }
    }

    private var perWorkspaceCard: some View {
        Card(title: "Time per workspace") {
            if sortedUsage.isEmpty {
                Text("No data yet. This fills in as you use workspaces.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sortedUsage, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle().fill(Brand.swatch(entry.color)).frame(width: 8, height: 8)
                                Text(entry.name).font(.callout)
                                Spacer()
                                Text(formatDuration(entry.usage.totalSeconds))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                Text("\u{00B7} \(entry.usage.activationCount)x")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Brand.swatch(entry.color).opacity(0.5))
                                    .frame(width: totalSeconds > 0
                                           ? geo.size.width * (entry.usage.totalSeconds / totalSeconds) : 0,
                                           height: 5)
                            }
                            .frame(height: 5)
                        }
                    }
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
