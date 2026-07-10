import SwiftUI
import FadeoCore

/// Makes the lazy-activation architecture visible: a sensor only runs when some enabled
/// workspace actually references its fields (see CLAUDE.md "Sensors"). This pane answers
/// "why isn't this trigger firing" directly, rather than leaving it a mystery.
struct TriggersPane: View {
    @EnvironmentObject var controller: AppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card(title: "Sensors") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A sensor only runs when a workspace actually needs it. This keeps Fadeo at zero idle cost otherwise.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(controller.sensorStatuses) { status in
                            HStack {
                                Circle()
                                    .fill(status.running ? Color.green.opacity(0.7) : Color.secondary.opacity(0.35))
                                    .frame(width: 8, height: 8)
                                Text(status.name).font(.callout)
                                Spacer()
                                Text(status.running ? "Running" : "Idle")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Card(title: "Meeting definition") {
                    HStack {
                        Text("Counts as \"in a meeting\" when:").foregroundStyle(.secondary)
                        Spacer()
                        Text(meetingLabel).font(.callout.weight(.medium))
                    }
                    Text("Change this in Precedence & Transitions.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Triggers")
    }

    private var meetingLabel: String {
        switch controller.configStore.config.settings.meeting {
        case .cameraOrMic: return "Camera or mic in use"
        case .cameraAndMic: return "Camera and mic both in use"
        case .cameraOnly: return "Camera in use"
        case .micOnly: return "Mic in use"
        }
    }
}
