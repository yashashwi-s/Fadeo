import SwiftUI
import FadeoCore

/// The soft nag (PLAN.md §13): shown only when the trial has expired and there's no
/// valid license, and only when the user opens the main window themselves (never a
/// proactive popup, never during a meeting or otherwise interrupting anything, since it
/// only ever appears alongside a window the user deliberately opened). Two ways to
/// dismiss it for good: pay what you want for a lifetime license ($2 minimum, no upper
/// bound, no tier), or answer one quick question and opt into anonymous usage sharing.
/// Never blocks any feature either way.
struct NagSheet: View {
    @ObservedObject var licenseManager: LicenseManager
    @Binding var isPresented: Bool

    @State private var licenseKeyInput = ""
    @State private var showKeyEntry = false
    @State private var showSurvey = false
    @State private var surveyAnswer: String?
    @State private var diagnosticsOptIn = DiagnosticsPreference.isEnabled

    private let surveyOptions = [
        "Still deciding if it's useful",
        "Wasn't aware it needed a license",
        "Would rather not pay for this kind of app",
        "Something isn't working right",
        "Other",
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image("AppLogo").resizable().scaledToFit().frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                Text("Your Fadeo trial has ended").font(.title3.weight(.semibold))
                Text("Fadeo keeps working exactly as before. No feature is disabled. If you've found it useful, pay what you want for a lifetime license, $2 minimum.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            .padding(.top, 28).padding(.bottom, 20).padding(.horizontal, 24)

            Divider()

            if showKeyEntry {
                keyEntryView
            } else if showSurvey {
                surveyView
            } else {
                choiceView
            }
        }
        .frame(width: 440)
    }

    // MARK: Initial choice

    private var choiceView: some View {
        VStack(spacing: 10) {
            Button {
                if let url = URL(string: "https://puremac.yashashwi.me/fadeo") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Pay what you want ($2 min.)").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("I already have a license key") { licenseManager.licenseError = nil; showKeyEntry = true }
                .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)

            Divider().padding(.vertical, 6)

            Button("Not right now, but I'll help improve Fadeo") { showSurvey = true }
                .buttonStyle(.plain).font(.callout)

            Button("Remind me later") { isPresented = false }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(24)
    }

    // MARK: License key entry

    private var keyEntryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your license key").font(.callout.weight(.medium))
            TextField("FADEO1.\u{2026}", text: $licenseKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.callout, design: .monospaced))
            if let error = licenseManager.licenseError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Back") { showKeyEntry = false; licenseKeyInput = "" }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Activate") {
                    if licenseManager.activate(licenseKeyInput) { isPresented = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseKeyInput.isEmpty)
            }
        }
        .padding(24)
    }

    // MARK: Survey + diagnostics opt-in

    private var surveyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick question, then you're set").font(.callout.weight(.medium))
            Picker("", selection: $surveyAnswer) {
                Text("Choose one\u{2026}").tag(String?.none)
                ForEach(surveyOptions, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden().pickerStyle(.radioGroup)

            Divider()

            Toggle("Also share anonymous usage data", isOn: $diagnosticsOptIn)
            Text("A coarse summary only: session count, days used, workspace count, switches, and total active time. Never workspace or app names, or file paths. Sent at most once a day while this is on.")
                .font(.caption2).foregroundStyle(.secondary)

            HStack {
                Button("Back") { showSurvey = false }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    DiagnosticsPreference.isEnabled = diagnosticsOptIn
                    if let answer = surveyAnswer {
                        UserDefaults.standard.set(answer, forKey: "fadeo.nag.surveyAnswer")
                    }
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(surveyAnswer == nil)
            }
        }
        .padding(24)
    }
}
