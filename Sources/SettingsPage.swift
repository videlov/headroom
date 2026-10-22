import SwiftUI

/// The Settings page: the session cookie, general options and the alerts.
struct SettingsPage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var status: StatusStore
    @ObservedObject var usage: UsageStore   // the saved cookie, and the test notification
    let open: (PopupPage) -> Void
    @State private var notificationsAllowed = true   // checked each time the page opens

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsSection(title: "Account") {
                NavigationRow(title: "Session Cookie", value: cookieValue) { open(.cookie) }
            }

            SettingsSection(title: "General") {
                SettingsRow(title: "Open at Login") {
                    toggle($prefs.openAtLogin)
                }
                RowDivider()
                SettingsRow(title: "Keyboard Shortcut", detail: "⌘U opens the popup from anywhere") {
                    toggle($prefs.shortcutEnabled)
                }
                RowDivider()
                SettingsRow(title: "Refresh") {
                    Picker("Refresh", selection: $prefs.refreshIntervalMinutes) {
                        ForEach(Preferences.refreshIntervalChoices, id: \.self) { minutes in
                            Text(minutes == 1 ? "Every minute" : "Every \(minutes) minutes").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                RowDivider()
                SettingsRow(title: "Appearance") {
                    Picker("Appearance", selection: $prefs.appearanceMode) {
                        Text("System").tag(AppearanceMode.system)
                        Text("Dark").tag(AppearanceMode.dark)
                        Text("Light").tag(AppearanceMode.light)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
            }

            SettingsSection(title: "Notifications") {
                if !notificationsAllowed {
                    SettingsRow(title: "Notifications are off",
                                detail: "macOS shows no alerts from Headroom until you allow them in System Settings") {
                        Button("Turn On…") { NSWorkspace.shared.open(AppInfo.notificationSettingsURL) }
                            .buttonStyle(PillButtonStyle(kind: .prominent))
                    }
                    RowDivider()
                }
                SettingsRow(title: "Usage Alerts",
                            detail: "The session at 25, 50, 75 and 90 %, the weekly limit at 90 and 100 %, extra usage charges and an ended session") {
                    toggle($prefs.usageNotificationsEnabled)
                }
                RowDivider()
                SettingsRow(title: "Status Alerts", detail: "Incidents in the Claude services you track") {
                    toggle($prefs.statusNotificationsEnabled)
                }
                RowDivider()
                NavigationRow(title: "Tracked Services",
                              value: "\(status.trackedComponents.count) of \(status.components.count)") {
                    open(.services)
                }
                if notificationsAllowed {
                    RowDivider()
                    Button(action: { usage.sendTestNotification() }) {
                        Text("Send Test Notification")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("\(AppInfo.name) \(AppInfo.version)")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondaryText)
                Spacer()
                Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
                    .buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 4)
        }
        .task { notificationsAllowed = await Notifier.isAllowed() }
    }

    /// "…WXYZ" for a saved cookie, from the end of its sessionKey.
    private var cookieValue: String {
        guard usage.hasCookie else { return "Not set" }
        if usage.problem == .cookieRejected { return "Expired" }
        return usage.savedCookieHint ?? "Saved"
    }

    private func toggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .toggleStyle(PopupSwitchStyle())
            .labelsHidden()
    }
}

/// The Claude services whose incidents show in the popup and raise status alerts.
struct ServicesPage: View {
    @ObservedObject var status: StatusStore

    var body: some View {
        SettingsSection(title: "Claude services",
                        footer: "The status line and the status alerts cover only the services switched on here.") {
            ForEach(Array(status.components.enumerated()), id: \.element.id) { index, component in
                if index > 0 { RowDivider() }
                SettingsRow(title: component.name) {
                    Toggle("", isOn: Binding(
                        get: { status.isTracked(component.id) },
                        set: { _ in status.toggleTracking(component.id) }
                    ))
                    .toggleStyle(PopupSwitchStyle())
                    .labelsHidden()
                }
            }
        }
    }
}
