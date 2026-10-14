import SwiftUI

/// The Settings panel at the bottom of the popup.
struct SettingsPanel: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var status: StatusStore
    let usage: UsageStore   // for the test notification

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $prefs.openAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at Login")
                        .font(.caption)
                    Text("Launch app automatically when you log in")
                        .font(.caption2)
                        .foregroundColor(Color.secondaryText)
                }
            }
            .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $prefs.usageNotificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Usage Notifications")
                            .font(.caption)
                        Text("Get alerts at 25%, 50%, 75%,\nand 90% session usage")
                            .font(.caption2)
                            .foregroundColor(Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $prefs.statusNotificationsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Status Notifications")
                            .font(.caption)
                        Text("Get alerts when tracked Claude services have an outage")
                            .font(.caption2)
                            .foregroundColor(Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)

                Button("Test Notification") {
                    usage.sendTestNotification()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $prefs.shortcutEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard Shortcut (⌘U)")
                            .font(.caption)
                        Text("Toggle popup from anywhere.\nDisable if it conflicts with other apps.")
                            .font(.caption2)
                            .foregroundColor(Color.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Status alerts: services to track")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("Only tick the Claude services you use. Status issues with unticked services won't be shown or trigger alerts.")
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(status.components) { component in
                    Toggle(isOn: Binding(
                        get: { status.isTracked(component.id) },
                        set: { _ in status.toggleTracking(component.id) }
                    )) {
                        Text(component.name)
                            .font(.caption2)
                    }
                    .toggleStyle(.checkbox)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh Interval")
                    .font(.caption)
                Picker("Refresh Interval", selection: $prefs.refreshIntervalMinutes) {
                    ForEach(Preferences.refreshIntervalChoices, id: \.self) { minutes in
                        Text(minutes == 1 ? "Every minute" : "Every \(minutes) minutes").tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                Text("How often usage is fetched from claude.ai")
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
            }

            Divider()

            // Appearance sits last on purpose: opening Settings scrolls to the end, so
            // this lands in view.
            VStack(alignment: .leading, spacing: 4) {
                Text("Appearance")
                    .font(.caption)
                Picker("Appearance", selection: $prefs.appearanceMode) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Dark").tag(AppearanceMode.dark)
                    Text("Light").tag(AppearanceMode.light)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Match macOS, or keep the classic dark look")
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}
