import SwiftUI

/// Paste, save or remove the claude.ai session cookie. The saved cookie stays out of the
/// field, so it doesn't show on screen; the end of its sessionKey says which one it is.
struct CookiePage: View {
    @ObservedObject var usage: UsageStore
    @Binding var cookieInput: String
    let saved: () -> Void   // after Save: back to the usage page, which shows the fetch

    private var isEmpty: Bool {
        cookieInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            savedCard

            VStack(alignment: .leading, spacing: 6) {
                Text(usage.hasCookie ? "Replace it" : "Paste it here")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.secondaryText)
                    .padding(.leading, 12)
                PasteableTextField(text: $cookieInput)
                    .frame(height: 64)
                    .overlay(alignment: .topLeading) {
                        if cookieInput.isEmpty {
                            Text("The Cookie request header, sessionKey=…")
                                .font(.system(size: 11))
                                .foregroundColor(Color.secondaryText)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                HStack(spacing: 8) {
                    Button("Save") {
                        if usage.saveCookie(cookieInput) {
                            cookieInput = ""
                            saved()
                        }
                    }
                    .buttonStyle(PillButtonStyle(kind: .prominent))
                    .disabled(isEmpty)

                    if usage.hasCookie {
                        Button("Remove") {
                            cookieInput = ""
                            usage.clearCookie()
                        }
                        .buttonStyle(PillButtonStyle(kind: .destructive))
                    }
                }
                .padding(.top, 2)
            }

            SettingsSection(title: "How to get it") {
                VStack(alignment: .leading, spacing: 7) {
                    step(1, "Open claude.ai/settings/usage in your browser.")
                    step(2, "In the developer tools, find the **usage** REST API request.")
                    step(3, "Copy the value of its **Cookie** request header.")
                    LinkButton(title: "Open claude.ai/settings/usage") {
                        NSWorkspace.shared.open(AppInfo.usagePageURL)
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 10)
            }
        }
    }

    /// Whether a cookie is saved, which one, and whether claude.ai still takes it.
    private var savedCard: some View {
        let rejected = usage.problem == .cookieRejected
        return Card {
            HStack(spacing: 10) {
                Image(systemName: usage.hasCookie ? "key.fill" : "key")
                    .font(.system(size: 15))
                    .foregroundColor(!usage.hasCookie ? Color.secondaryText : rejected ? .orange : .green)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(!usage.hasCookie ? "No session cookie yet"
                         : rejected ? "claude.ai no longer accepts it"
                         : "Saved in your keychain")
                        .font(.system(size: 12, weight: .semibold))
                    Text(usage.hasCookie
                         ? usage.savedCookieHint.map { "sessionKey \($0)" } ?? "Saved"
                         : "Headroom needs it to read your usage.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondaryText)
                }
            }
        }
    }

    /// A numbered step; the text is Markdown, for **bold** and `code`.
    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundColor(Color.secondaryText)
            Text(LocalizedStringKey(text))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
