import SwiftUI

/// A searchable app picker: a button that opens a popover with a filter field and a
/// scrollable icon+name list. A flat menu of 80+ installed apps is unusable to scan;
/// this fixes that everywhere an app list appears.
struct AppPickerButton: View {
    let label: String
    let apps: [InstalledApp]
    /// Shown as a pinned first row when set, for "pick one, with a way back to none"
    /// use sites (e.g. the Conflict Simulator) as opposed to "add one to a list" sites.
    var noneOption: String? = nil
    let onPick: (InstalledApp?) -> Void

    @State private var isPresented = false
    @State private var query = ""

    private var filtered: [InstalledApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Button(label) { isPresented = true }
            .popover(isPresented: $isPresented) {
                VStack(spacing: 0) {
                    TextField("Search apps", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .padding(10)
                    Divider()
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if let noneOption, query.isEmpty {
                                row(icon: nil, name: noneOption) {
                                    onPick(nil)
                                    dismiss()
                                }
                                Divider()
                            }
                            ForEach(filtered) { app in
                                row(icon: app.icon, name: app.name) {
                                    onPick(app)
                                    dismiss()
                                }
                            }
                            if filtered.isEmpty && !query.isEmpty {
                                Text("No apps match \u{201C}\(query)\u{201D}")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .padding(12)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
                .frame(width: 260)
            }
    }

    private func row(icon: NSImage?, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                } else {
                    Color.clear.frame(width: 18, height: 18)
                }
                Text(name)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dismiss() {
        isPresented = false
        query = ""
    }
}
