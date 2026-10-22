import AppKit
import SwiftUI

// Previews of the popup for design work: every page and state with sample data, dark and
// light, one PNG each plus a sheet of all of them (pages.png). The real UsageView sits in an
// off-screen window over a drawn wallpaper and popover body, and the window server captures
// the window, so Liquid Glass shows; cacheDisplay, as in main.swift, leaves the glass out.
// The capture has the display's scale (1x on a 1x display). CGWindowListCreateImage is
// unavailable in the macOS 15+ SDK but still works at run time, so it's looked up with dlsym.
// scripts/preview.sh compiles this with Sources/ (without HeadroomApp.swift, which has its own
// @main); it never touches the network or the Keychain.

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
let only = Set(CommandLine.arguments.dropFirst(2)).intersection(Scenario.allCases.map(\.rawValue))
let suiteName = "io.github.videlov.headroom.preview"

typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let coreGraphics = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW)
let createImage = unsafeBitCast(dlsym(coreGraphics, "CGWindowListCreateImage"), to: CreateImage.self)

func spin(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func json(_ text: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

struct Theme {
    let name: String
    let appearance: NSAppearance.Name
    let wallpaper: (NSColor, NSColor)
    let glass: NSColor
    let border: NSColor
}

let themes = [
    Theme(name: "dark", appearance: .darkAqua, wallpaper: (rgb(0x3A4C80), rgb(0x1B2142)),
          glass: rgb(0x1E1E24, 0.74), border: NSColor(white: 1, alpha: 0.16)),
    Theme(name: "light", appearance: .aqua, wallpaper: (rgb(0xB9CBEA), rgb(0xE6ECF7)),
          glass: rgb(0xF2F2F5, 0.78), border: NSColor(white: 0, alpha: 0.12)),
]

/// The wallpaper and the popover's body, drawn behind the hosting view.
final class Backdrop: NSView {
    let theme: Theme
    var body = NSRect.zero

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: theme.wallpaper.0, ending: theme.wallpaper.1)!.draw(in: bounds, angle: -90)
        let path = NSBezierPath(roundedRect: body, xRadius: 16, yRadius: 16)
        theme.glass.setFill()
        path.fill()
        theme.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

enum Scenario: String, CaseIterable {
    case usage, banner, settings, cookie, services, rejected, welcome
}

let statusSummary = json("""
{"status": {"indicator": "none", "description": "All Systems Operational"},
 "components": [{"id": "c1", "name": "claude.ai", "status": "operational"},
                {"id": "c2", "name": "Claude Console (platform.claude.com)", "status": "operational"},
                {"id": "c3", "name": "Claude API (api.anthropic.com)", "status": "operational"},
                {"id": "c4", "name": "Claude Code", "status": "operational"},
                {"id": "c5", "name": "Claude Cowork", "status": "operational"},
                {"id": "c6", "name": "Claude for Government", "status": "operational"}],
 "incidents": []}
""")

let feed = json("""
{"version": "9.9.0", "title": "Headroom 9.9.0",
 "description": "A fresh popup: the limits at a glance, Settings and the session cookie on pages of their own.",
 "buttons": [{"label": "Download", "url": "https://github.com/videlov/headroom/releases/latest/download/Headroom.dmg", "style": "primary"}]}
""")

@MainActor func view(for scenario: Scenario) -> some View {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    let prefs = Preferences(defaults: defaults)
    let now = Date()
    let cookie = scenario == .welcome ? "" : "sessionKey=sk-ant-sid01-sample-cookie-WXYZ"
    let usage = UsageStore(prefs: prefs, defaults: defaults, cookie: cookie, notify: { _, _ in })
    if scenario != .welcome {
        var snapshot = UsageSnapshot(
            session: UsageWindow(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 35 * 60)),
            weekly: UsageWindow(percent: 76, resetsAt: now.addingTimeInterval(2 * 86_400 + 18 * 3600)))
        snapshot.weeklyFable = UsageWindow(percent: 18, resetsAt: now.addingTimeInterval(2 * 86_400 + 18 * 3600))
        usage.apply(usage: .success(snapshot),
                    extra: ExtraUsage(isEnabled: true, spentMinor: 464, limitMinor: 2000, currency: "EUR"),
                    credits: nil, resets: nil, now: scenario == .rejected ? now.addingTimeInterval(-40 * 60) : now)
    }
    if scenario == .rejected {
        usage.apply(usage: .failure(ClaudeAPI.Failure.sessionEnded), extra: nil, credits: nil, resets: nil)
    }
    let status = StatusStore(prefs: prefs, defaults: defaults, notify: { _, _ in })
    status.apply(summary: statusSummary)
    let updates = UpdateStore(defaults: defaults, notify: { _, _ in })
    if scenario == .banner { updates.apply(feed: feed) }
    let path: [PopupPage] = switch scenario {
    case .settings: [.settings]
    case .cookie: [.settings, .cookie]
    case .services: [.settings, .services]
    default: []
    }
    return UsageView(usage: usage, status: status, updates: updates, prefs: prefs, path: path)
}

@MainActor func capture(_ scenario: Scenario, _ theme: Theme) -> CGImage {
    let margin: CGFloat = 28
    let host = NSHostingView(rootView: view(for: scenario))
    let backdrop = Backdrop(theme: theme)
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 400),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: theme.appearance)
    window.contentView = backdrop
    backdrop.addSubview(host)
    window.orderFrontRegardless()
    for _ in 0..<3 {
        let size = host.fittingSize
        window.setContentSize(NSSize(width: size.width + 2 * margin, height: size.height + 2 * margin))
        host.frame = NSRect(x: margin, y: margin, width: size.width, height: size.height)
        backdrop.body = host.frame
        backdrop.needsDisplay = true
        spin(0.6)
    }
    let image = createImage(.null, 1 << 3, CGWindowID(window.windowNumber), 1 << 0)!.takeRetainedValue()
    window.orderOut(nil)
    return image
}

func write(_ image: CGImage, _ name: String) {
    let url = outputDirectory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

/// Rows of captures, top-aligned, each with its label above, on a neutral gray.
func grid(_ rows: [[(String, CGImage)]]) -> CGImage {
    let gap = 20, label = 24
    let rowHeights = rows.map { ($0.map { $0.1.height }.max() ?? 0) + label }
    let width = rows.map { $0.reduce(gap) { $0 + $1.1.width + gap } }.max() ?? 0
    let height = rowHeights.reduce(gap) { $0 + $1 + gap }
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    var top = height - gap
    for (row, rowHeight) in zip(rows, rowHeights) {
        var x = gap
        for (name, image) in row {
            NSAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]).draw(at: NSPoint(x: x + 2, y: top - 18))
            context.draw(image, in: CGRect(x: x, y: top - label - image.height, width: image.width, height: image.height))
            x += image.width + gap
        }
        top -= rowHeight + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

@main
enum Preview {
    @MainActor static func main() {
        _ = NSApplication.shared
        // The header shows the app icon, which this process doesn't have.
        NSApp.applicationIconImage = NSImage(contentsOfFile: "Resources/AppIcon.png")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        var shots: [String: CGImage] = [:]
        for theme in themes {
            for scenario in Scenario.allCases where only.isEmpty || only.contains(scenario.rawValue) {
                let image = capture(scenario, theme)
                write(image, "\(scenario.rawValue)-\(theme.name).png")
                shots["\(scenario.rawValue)-\(theme.name)"] = image
            }
        }
        if only.isEmpty {
            let pages: [(String, String)] = [("Usage", "usage"), ("Update banner", "banner"), ("Session ended", "rejected"),
                                             ("First start", "welcome"), ("Settings", "settings"),
                                             ("Session Cookie", "cookie"), ("Tracked Services", "services")]
            write(grid(themes.map { theme in pages.map { ($0.0, shots["\($0.1)-\(theme.name)"]!) } }), "pages.png")
            print("pages.png")
        }
        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    }
}
