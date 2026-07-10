import SwiftUI
import FadeoCore

/// Pick a hypothetical context and see which workspace would win, and why — before it
/// ever happens for real. Runs the exact same `Resolver` the live app uses, just fed a
/// synthetic `Context` instead of the sensors' real one.
struct ConflictSimulator: View {
    let config: Config

    @State private var appBundle: String = ""
    @State private var spaceIndex: Int = 0
    @State private var meeting = false
    @State private var focus: String = ""
    @State private var hour: Double = 12
    @State private var installedApps: [InstalledApp] = []

    private var result: Decision {
        var ctx = Context()
        ctx.frontmostApp = appBundle.isEmpty ? nil : appBundle
        ctx.activeSpace = spaceIndex > 0 ? SpaceRef(index: spaceIndex) : nil
        ctx.cameraActive = meeting
        ctx.micActive = meeting
        ctx.focusMode = focus.isEmpty ? nil : focus
        var comps = DateComponents()
        comps.hour = Int(hour); comps.minute = 0
        ctx.localTime = Calendar.current.date(from: comps) ?? Date()
        return Resolver().resolve(context: ctx, config: config, state: ResolverState())
    }

    var body: some View {
        Card(title: "Conflict simulator") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Try a hypothetical situation and see which workspace wins, and why.")
                    .font(.caption).foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("App").foregroundStyle(.secondary)
                        Picker("", selection: $appBundle) {
                            Text("None").tag("")
                            ForEach(installedApps) { app in
                                Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                                    .tag(app.bundleID)
                            }
                        }.labelsHidden()
                    }
                    GridRow {
                        Text("Space").foregroundStyle(.secondary)
                        Stepper("Desktop \(spaceIndex == 0 ? "any" : String(spaceIndex))", value: $spaceIndex, in: 0...12)
                    }
                    GridRow {
                        Text("Meeting").foregroundStyle(.secondary)
                        Toggle("In a meeting", isOn: $meeting)
                    }
                    GridRow {
                        Text("Focus").foregroundStyle(.secondary)
                        TextField("mode identifier (optional)", text: $focus).textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Time").foregroundStyle(.secondary)
                        HStack {
                            Slider(value: $hour, in: 0...23, step: 1)
                            Text(String(format: "%02d:00", Int(hour))).font(.caption).monospacedDigit().frame(width: 40)
                        }
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 10) {
                    let ws = config.workspaces.first { $0.id == result.activeWorkspace }
                    Circle().fill(ws.map { Brand.swatch($0.color) } ?? Color.secondary.opacity(0.4))
                        .frame(width: 10, height: 10).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ws?.name ?? "Nothing").font(.callout.weight(.semibold))
                        Text(result.reason.explanation).font(.caption).foregroundStyle(.secondary)
                        Text(bandLabel(result.reason.band)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onAppear { installedApps = InstalledApps.scan() }
    }

    private func bandLabel(_ band: ResolutionBand) -> String {
        switch band {
        case .override: return "Decided by: override"
        case .single: return "Decided by: single match"
        case .tiebreak: return "Decided by: tiebreak chain"
        case .fallback: return "Decided by: fallback"
        }
    }
}
