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

    /// Bar color for a usage fraction: green, orange from 70 %, red from 90 % (UsageLevel).
    static func usage(_ fraction: Double) -> Color {
        switch UsageLevel(fraction: fraction) {
        case .normal: return .green
        case .high: return .orange
        case .critical: return .red
        }
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
        scrollView.borderType = .bezelBorder
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
