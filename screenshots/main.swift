import AppKit
import SwiftUI

// The README screenshots: the popup under its menu bar item, and the menu bar item in five
// states, each in dark and light at 2x. They come from the app's own views and menu bar code
// filled with sample data; the desktop, the popover's frame and the other menu bar items are
// drawn here. scripts/screenshots.sh compiles this with Sources/ (without HeadroomApp.swift,
// which has @main) and writes the PNGs next to it. It uses a preferences domain of its own
// and never touches the network or the Keychain.

let scale: CGFloat = 2
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
let suiteName = "io.github.videlov.headroom.screenshots"
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func freshDefaults() -> UserDefaults {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func json(_ text: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

let now = at(20, 14, 5)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func white(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }
func black(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }

struct Theme {
    let name: String
    let appearance: NSAppearance.Name
    let wallpaper: [CGColor]   // top to bottom
    let menuText: NSColor
    let glass: CGColor         // the popover's material over the wallpaper
    let scrim: CGColor         // UsageView's own backing, continued into the arrow
    let border: CGColor
    let shadow: CGColor
    let caption: NSColor
}

let themes = [
    Theme(name: "dark", appearance: .darkAqua,
          wallpaper: [rgb(0x3A4C80), rgb(0x1B2142)],
          menuText: .white, glass: rgb(0x1E1E24, 0.74),
          scrim: CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 0.3),
          border: white(0.16), shadow: black(0.50), caption: NSColor(white: 1, alpha: 0.85)),
    Theme(name: "light", appearance: .aqua,
          wallpaper: [rgb(0xB9CBEA), rgb(0xE6ECF7)],
          menuText: NSColor(white: 0, alpha: 0.85), glass: rgb(0xF2F2F5, 0.78),
          scrim: white(0.85),
          border: black(0.12), shadow: black(0.22), caption: NSColor(white: 0, alpha: 0.72)),
]

func spin(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Renders a view offscreen at 2x with a transparent background.
@MainActor func render(_ view: NSView, appearance: NSAppearance.Name, size fixedSize: NSSize? = nil) -> NSBitmapImageRep {
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 400),
                          styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: appearance)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.contentView = view
    window.orderFrontRegardless()
    view.layoutSubtreeIfNeeded()
    spin(1)
    window.setContentSize(fixedSize ?? view.fittingSize)
    view.layoutSubtreeIfNeeded()
    spin(0.5)
    let size = view.bounds.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    window.orderOut(nil)
    return rep
}

/// The status item as MenuBarController draws it, with the title in the menu bar's text color.
@MainActor func menuBarItem(_ state: MenuBarState, _ theme: Theme) -> NSBitmapImageRep {
    let button = NSButton(title: "", target: nil, action: nil)
    button.isBordered = false
    button.imagePosition = .imageLeft
    button.font = NSFont.menuBarFont(ofSize: 0)
    MenuBarController.show(state, on: button)
    button.attributedTitle = NSAttributedString(string: button.title, attributes: [
        .font: NSFont.menuBarFont(ofSize: 0),
        .foregroundColor: theme.menuText,
    ])
    button.sizeToFit()
    let container = NSView(frame: NSRect(origin: .zero, size: button.frame.size))
    container.addSubview(button)
    return render(container, appearance: theme.appearance, size: button.frame.size)
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

/// The popup with sample usage, and the menu bar state that goes with it.
@MainActor func popup(_ theme: Theme) -> (NSBitmapImageRep, MenuBarState) {
    let defaults = freshDefaults()
    let prefs = Preferences(defaults: defaults)
    let usage = UsageStore(prefs: prefs, defaults: defaults, cookie: "sessionKey=sk-ant-sid01-sample",
                           notify: { _, _ in })
    var snapshot = UsageSnapshot(session: UsageWindow(percent: 42, resetsAt: at(20, 16, 40)),
                                 weekly: UsageWindow(percent: 76, resetsAt: at(23, 8, 0)))
    snapshot.weeklyFable = UsageWindow(percent: 18, resetsAt: at(23, 8, 0))
    usage.apply(usage: .success(snapshot),
                extra: ExtraUsage(isEnabled: true, spentMinor: 464, limitMinor: 2000, currency: "EUR"),
                credits: nil, resets: nil, now: now)
    let status = StatusStore(prefs: prefs, defaults: defaults, notify: { _, _ in })
    status.apply(summary: statusSummary)
    let updates = UpdateStore(defaults: defaults, notify: { _, _ in })
    let view = NSHostingView(rootView: UsageView(usage: usage, status: status, updates: updates, prefs: prefs))
    return (render(view, appearance: theme.appearance), usage.menuBarState(now: now))
}

// MARK: Compositing

func context(_ size: CGSize) -> CGContext {
    let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high
    return ctx
}

func write(_ ctx: CGContext, _ name: String) {
    let url = outputDirectory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, ctx.makeImage()!, [
        kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale,
    ] as CFDictionary)
    CGImageDestinationFinalize(destination)
    print("\(name): \(ctx.width)×\(ctx.height)")
}

/// A plain desktop picture, clipped to a rounded canvas.
func drawWallpaper(_ ctx: CGContext, _ size: CGSize, _ theme: Theme) {
    ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: 10, cornerHeight: 10,
                       transform: nil))
    ctx.clip()
    // A vertical gradient, one solid color per pixel row: CGGradient dithers, and the noise
    // more than doubles the PNG size.
    let top = theme.wallpaper[0].components!, bottom = theme.wallpaper[1].components!
    let rows = Int(size.height * scale)
    for row in 0..<rows {
        let t = CGFloat(row) / CGFloat(rows - 1)   // 0 at the bottom
        let mix = (0..<3).map { bottom[$0] + (top[$0] - bottom[$0]) * t }
        ctx.setFillColor(CGColor(srgbRed: mix[0], green: mix[1], blue: mix[2], alpha: 1))
        ctx.fill(CGRect(x: 0, y: CGFloat(row) / scale, width: size.width, height: 1 / scale))
    }
}

func draw(_ rep: NSBitmapImageRep, _ ctx: CGContext, at origin: CGPoint) {
    ctx.draw(rep.cgImage!, in: CGRect(origin: origin, size: rep.size))
}

/// Draws with AppKit (text, symbols) into the CG context.
func withAppKit(_ ctx: CGContext, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func symbol(_ name: String, _ color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

/// The popover outline: a rounded body with the arrow on top, pointing at `apexX`.
func popoverPath(body: CGRect, apexX: CGFloat, arrow: CGFloat) -> CGPath {
    let radius: CGFloat = 12, half: CGFloat = 11
    let (minX, maxX, minY, maxY) = (body.minX, body.maxX, body.minY, body.maxY)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: minX + radius, y: minY))
    path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX, y: maxY), radius: radius)
    path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: minX, y: maxY), radius: radius)
    // The arrow, with a slightly rounded tip.
    path.addLine(to: CGPoint(x: apexX + half, y: maxY))
    path.addLine(to: CGPoint(x: apexX + 1.6, y: maxY + arrow - 1.2))
    path.addQuadCurve(to: CGPoint(x: apexX - 1.6, y: maxY + arrow - 1.2), control: CGPoint(x: apexX, y: maxY + arrow))
    path.addLine(to: CGPoint(x: apexX - half, y: maxY))
    path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX, y: minY), radius: radius)
    path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: maxX, y: minY), radius: radius)
    path.closeSubpath()
    return path
}

let menuBarHeight: CGFloat = 24

/// The menu bar clock at `now`: "Tue 20 Oct  14:05".
let clockText: String = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE d MMM  HH:mm"
    return formatter.string(from: now)
}()

/// The menu bar's right side: Headroom's item centered at `x`, then Wi-Fi, Control Center
/// and the clock.
func drawMenuBar(_ ctx: CGContext, _ size: CGSize, _ theme: Theme, item: NSBitmapImageRep, x: CGFloat) {
    let midY = size.height - menuBarHeight / 2
    draw(item, ctx, at: CGPoint(x: x - item.size.width / 2, y: midY - item.size.height / 2))
    withAppKit(ctx) {
        var left = x + item.size.width / 2 + 16
        for name in ["wifi", "switch.2"] {
            let image = symbol(name, theme.menuText)
            image.draw(in: NSRect(origin: NSPoint(x: left, y: midY - image.size.height / 2), size: image.size))
            left += image.size.width + 16
        }
        let clock = NSAttributedString(string: clockText, attributes: [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: theme.menuText,
        ])
        clock.draw(at: NSPoint(x: left, y: midY - clock.size().height / 2))
    }
}

@MainActor func popupScreenshot(_ theme: Theme) {
    let (content, state) = popup(theme)
    let item = menuBarItem(state, theme)
    let arrow: CGFloat = 10, bottom: CGFloat = 44, width: CGFloat = 520
    let size = CGSize(width: width, height: bottom + content.size.height + arrow + 2 + menuBarHeight)
    let ctx = context(size)
    drawWallpaper(ctx, size, theme)

    // NSPopover centers on the status item.
    let itemX = width / 2
    let body = CGRect(origin: CGPoint(x: itemX - content.size.width / 2, y: bottom), size: content.size)
    let path = popoverPath(body: body, apexX: itemX, arrow: arrow)

    // The shadow, outside the popover only.
    ctx.saveGState()
    ctx.addRect(CGRect(origin: .zero, size: size))
    ctx.addPath(path)
    ctx.clip(using: .evenOdd)
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: 28 * scale, color: theme.shadow)
    ctx.addPath(path)
    ctx.setFillColor(black(1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.setFillColor(theme.glass)
    ctx.fill(CGRect(origin: .zero, size: size))
    ctx.setFillColor(theme.scrim)
    ctx.fill(CGRect(x: 0, y: body.maxY, width: width, height: arrow + 1))
    draw(content, ctx, at: body.origin)
    ctx.restoreGState()

    ctx.addPath(path)
    ctx.setStrokeColor(theme.border)
    ctx.setLineWidth(1 / scale)
    ctx.strokePath()

    drawMenuBar(ctx, size, theme, item: item, x: itemX)
    write(ctx, "popup-\(theme.name).png")
}

let states: [(MenuBarState, String)] = [
    (.current(percent: 42, weekly: nil), "Session at 42 %"),
    (.current(percent: 78, weekly: nil), "Session at 78 %"),
    (.current(percent: 42, weekly: 85), "Weekly limit at 85 %"),
    (.extraUsage(spent: "€4.64", weekly: nil), "Limit used up: extra usage this month"),
    (.waiting(timeLeft: "11h 20m", weekly: 100), "Weekly limit used up: time until it resets"),
]

@MainActor func menuBarScreenshot(_ theme: Theme) {
    let cell: CGFloat = 132, captionHeight: CGFloat = 30, gap: CGFloat = 8, bottom: CGFloat = 12
    let size = CGSize(width: cell * CGFloat(states.count), height: menuBarHeight + gap + captionHeight + bottom)
    let ctx = context(size)
    drawWallpaper(ctx, size, theme)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    for (index, (state, caption)) in states.enumerated() {
        let item = menuBarItem(state, theme)
        let midX = cell * (CGFloat(index) + 0.5)
        let midY = size.height - menuBarHeight / 2
        draw(item, ctx, at: CGPoint(x: midX - item.size.width / 2, y: midY - item.size.height / 2))
        withAppKit(ctx) {
            NSAttributedString(string: caption, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: theme.caption,
                .paragraphStyle: paragraph,
            ]).draw(with: NSRect(x: midX - cell / 2 + 8, y: bottom, width: cell - 16, height: captionHeight),
                    options: [.usesLineFragmentOrigin])
        }
    }
    write(ctx, "menu-bar-\(theme.name).png")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for theme in themes {
        popupScreenshot(theme)
        menuBarScreenshot(theme)
    }
    UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
}
