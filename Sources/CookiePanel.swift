import SwiftUI

/// Paste, save or clear the claude.ai session cookie.
struct CookiePanel: View {
    @ObservedObject var usage: UsageStore
    @Binding var cookieInput: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cookie:")
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
                VStack(spacing: 4) {
                    PasteableTextField(text: $cookieInput)
                        .frame(height: 60)
                        .cornerRadius(4)

                    HStack(spacing: 8) {
                        Button("Save") {
                            usage.saveCookie(cookieInput)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if usage.usage != nil {
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
