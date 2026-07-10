import SwiftUI
import FadeoCore

/// Every timing knob defaults to "inherit the global default" (PLAN.md §6) — toggling
/// one on gives it a workspace-specific value; off removes the override entirely rather
/// than storing a redundant copy of the default.
struct TimingEditor: View {
    @Binding var timing: Timing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("Fade in", $timing.fadeInMs, range: 0...5000)
            row("Fade out", $timing.fadeOutMs, range: 0...5000)
            row("Crossfade", $timing.crossfadeMs, range: 0...5000)
            row("Enter delay (grace before switching in)", $timing.enterDelayMs, range: 0...10000)
            row("Exit delay (grace before switching out)", $timing.exitDelayMs, range: 0...10000)
            row("Minimum dwell (anti-flap)", $timing.minDwellMs, range: 0...60000)
            Text("Off = use the global default from Precedence & Transitions.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func row(_ label: String, _ value: Binding<Int?>, range: ClosedRange<Double>) -> some View {
        HStack {
            Toggle(label, isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { on in value.wrappedValue = on ? Int((range.upperBound / 4)) : nil }
            ))
            Spacer()
            if let v = value.wrappedValue {
                Slider(value: Binding(
                    get: { Double(v) }, set: { value.wrappedValue = Int($0) }
                ), in: range).frame(width: 140)
                Text("\(v) ms").font(.caption).monospacedDigit().frame(width: 60, alignment: .trailing)
            }
        }
        .font(.callout)
    }
}
