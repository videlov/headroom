import AppKit
import SwiftUI

extension Color {
    // Secondary text: system gray in dark; darker in light, where the vibrant
    // ~50% gray over the white popover backing reads as washed out.
    static let secondaryText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .secondaryLabelColor
            : NSColor(white: 0.24, alpha: 1.0)   // opaque: vibrancy washes out alpha grays
    })

    /// Ring and bar color for a usage fraction: the menu bar icon's green, yellow from 70 %,
    /// red from 90 % (UsageLevel).
    static func usage(_ fraction: Double) -> Color {
        Color(nsColor: UsageLevel(fraction: fraction).color)
    }

    /// A card on the popup's background: a light veil in dark, a light shade in light.
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.045)
    })
}

private struct DrawsGlassKey: EnvironmentKey {
    static let defaultValue = true
}

private struct FixedNowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// Whether the buttons use Liquid Glass on macOS 26 and later. The README screenshots
    /// turn it off: cacheDisplay leaves the glass out, so they show the look before macOS 26.
    var drawsGlass: Bool {
        get { self[DrawsGlassKey.self] }
        set { self[DrawsGlassKey.self] = newValue }
    }

    /// The time the popup counts reset times from; nil is the clock. The README screenshots
    /// fix it, so they come out the same on every run.
    var fixedNow: Date? {
        get { self[FixedNowKey.self] }
        set { self[FixedNowKey.self] = newValue }
    }
}

/// The popup's size and the cards' corners.
enum Metrics {
    static let popupWidth: CGFloat = 340
    // Under the header; taller pages scroll. With a mouse, macOS shows a scroll bar that
    // narrows the cards, so every page fits as long as nothing expands.
    static let maxBodyHeight: CGFloat = 640
    static let cardRadius: CGFloat = 14
}

/// A rounded card that groups content on the popup's background; `tint` colors it for
/// banners and problems.
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    var tint: Color?
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(tint.map { $0.opacity(0.14) } ?? Color.card)
            )
    }
}

/// A usage limit as a ring, filled clockwise from 12 o'clock like the menu bar's ring.
struct RingGauge: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// A round icon button in the popup's header: Liquid Glass from macOS 26, a soft circle
/// before. It draws its own colors, so it doesn't look disabled while the app is inactive,
/// as AppKit's buttons do.
struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(GlassCircleButtonStyle())
        .help(help)
    }
}

private struct GlassCircleButtonStyle: ButtonStyle {
    @Environment(\.drawsGlass) private var drawsGlass

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .foregroundColor(.primary)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.6 : 1)
        if #available(macOS 26, *), drawsGlass {
            label.glassEffect(.regular.interactive(), in: Circle())
        } else {
            label.background(Circle().fill(Color.primary.opacity(0.08)))
        }
    }
}

/// A capsule button for the action of a card or a page: filled with the accent color when
/// prominent, red text when destructive, Liquid Glass otherwise from macOS 26. The prominent
/// one is a solid fill: a glass tinted with the accent color came out washed out in the
/// popover, which stays inactive until it's clicked.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case normal, prominent, destructive }
    var kind = Kind.normal
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.drawsGlass) private var drawsGlass

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(kind == .prominent ? .white : kind == .destructive ? .red : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
        if kind == .prominent {
            label.background(Capsule().fill(Color.accentColor.opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)))
        } else if #available(macOS 26, *), drawsGlass {
            label
                .opacity(configuration.isPressed ? 0.7 : 1)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            label.background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.1)))
        }
    }
}

/// A switch in the accent color. AppKit's switch turns gray, on or off, while the app is
/// inactive, as it is when the popup opens.
struct PopupSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { configuration.isOn.toggle() } }) {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.16))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
            }
            .frame(width: 30, height: 18)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// A text link in the accent color, "Manage ↗"; plain, so it keeps its color while the app
/// is inactive.
struct LinkButton: View {
    let title: String
    var systemImage: String? = "arrow.up.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.accentColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A titled group of rows in one card, like a section in System Settings.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.secondaryText)
                .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .fill(Color.card)
            )
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
    }
}

/// One row of a SettingsSection: a title, an optional explanation and a control on the right.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 8)
    }
}

/// A SettingsSection row that opens a page: the title, a value and a chevron.
struct NavigationRow: View {
    let title: String
    var value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.system(size: 12))
                        .foregroundColor(Color.secondaryText)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.secondaryText)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The hairline between the rows of a card: one pixel, so it stays crisp at 1x.
struct RowDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 1 / displayScale)
    }
}

/// A deterministic usage bar: the native linear ProgressView ignores .tint() in light
/// (aqua) and vibrant rendering and falls back to the accent blue.
struct LimitBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 6)
    }
}

/// A multi-line text box where ⌘V, ⌘C, ⌘X, ⌘A, ⌘Z and ⇧⌘Z work: a menu bar app has no
/// Edit menu to route them.
struct PasteableTextField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteableNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 11)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = false
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true

        // Wrap lines
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class PasteableNSTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "v":
                paste(nil)
                return true
            case "c":
                copy(nil)
                return true
            case "x":
                cut(nil)
                return true
            case "a":
                selectAll(nil)
                return true
            case "z":
                if undoManager?.canUndo == true { undoManager?.undo() }
                return true
            case "Z":   // ⇧⌘Z: Shift still applies to charactersIgnoringModifiers
                if undoManager?.canRedo == true { undoManager?.redo() }
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
