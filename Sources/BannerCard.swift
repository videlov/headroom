import SwiftUI

/// The message or update banner at the top of the popup; at most one shows.
struct BannerCard: View {
    @ObservedObject var updates: UpdateStore

    var body: some View {
        switch updates.visibleBanner {
        case .message:
            if let message = updates.announcement {
                messageCard(message)
            }
        case .update:
            if let update = updates.available {
                updateCard(update)
            }
        case .none:
            EmptyView()
        }
    }

    private func messageCard(_ message: Announcement) -> some View {
        Card(tint: .accentColor) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let heading = message.heading, !heading.isEmpty {
                        Text(heading)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    closeButton
                }
                if !message.title.isEmpty {
                    Text(message.title)
                        .font(.system(size: 12))
                }
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttonRow(message.buttons)
            }
        }
    }

    private func updateCard(_ update: AvailableUpdate) -> some View {
        Card(tint: .accentColor) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Version \(update.version) available")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    closeButton
                }
                Text(update.title)
                    .font(.system(size: 12))
                Text(update.body)
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                buttonRow(update.buttons)
            }
        }
    }

    private var closeButton: some View {
        Button(action: { updates.dismissCurrent() }) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.secondaryText)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }

    @ViewBuilder private func buttonRow(_ buttons: [BannerButton]) -> some View {
        if !buttons.isEmpty {
            HStack(spacing: 8) {
                ForEach(buttons.indices, id: \.self) { i in
                    bannerButton(buttons[i])
                }
            }
            .padding(.top, 4)
        }
    }

    private func bannerButton(_ button: BannerButton) -> some View {
        Button(button.label) {
            if let url = button.url {
                NSWorkspace.shared.open(url)
            }
            if button.dismisses {
                updates.dismissCurrent()
            }
        }
        .buttonStyle(PillButtonStyle(kind: button.isPrimary ? .prominent : .normal))
    }
}
