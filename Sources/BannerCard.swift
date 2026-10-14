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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let heading = message.heading, !heading.isEmpty {
                    Text(heading)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Spacer()
                closeButton
            }
            if !message.title.isEmpty {
                Text(message.title)
                    .font(.caption)
            }
            if !message.body.isEmpty {
                Text(message.body)
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttonRow(message.buttons)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.12))
        .cornerRadius(6)
    }

    private func updateCard(_ update: AvailableUpdate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("⬆️")
                Text("Version \(update.version) available")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                closeButton
            }
            Text(update.title)
                .font(.caption)
            Text(update.body)
                .font(.caption2)
                .foregroundColor(Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            buttonRow(update.buttons)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.12))
        .cornerRadius(6)
    }

    private var closeButton: some View {
        Button(action: { updates.dismissCurrent() }) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.secondaryText)
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private func buttonRow(_ buttons: [BannerButton]) -> some View {
        if !buttons.isEmpty {
            HStack(spacing: 6) {
                ForEach(buttons.indices, id: \.self) { i in
                    bannerButton(buttons[i])
                }
            }
        }
    }

    @ViewBuilder private func bannerButton(_ button: BannerButton) -> some View {
        let tap = {
            if let url = button.url {
                NSWorkspace.shared.open(url)
            }
            if button.dismisses {
                updates.dismissCurrent()
            }
        }
        if button.isPrimary {
            Button(button.label, action: tap)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Button(button.label, action: tap)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
