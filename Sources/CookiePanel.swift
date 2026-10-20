import SwiftUI

/// Paste, save or clear the claude.ai session cookie. The saved cookie stays out of the
/// field, so it doesn't show on screen; the end of its sessionKey says which one it is.
struct CookiePanel: View {
    @ObservedObject var usage: UsageStore
    @Binding var cookieInput: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Session Cookie:")
                    Spacer()
                    if usage.hasCookie {
                        Text("Saved" + (usage.savedCookieHint.map { " · sessionKey \($0)" } ?? ""))
                    }
                }
                .font(.caption2)
                .foregroundColor(Color.secondaryText)
                VStack(spacing: 4) {
                    PasteableTextField(text: $cookieInput)
                        .frame(height: 60)
                        .cornerRadius(4)

                    HStack(spacing: 8) {
                        Button("Save") {
                            if usage.saveCookie(cookieInput) { cookieInput = "" }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if usage.hasCookie {
                            Button("Clear") {
                                cookieInput = ""
                                usage.clearCookie()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}
