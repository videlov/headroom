import AppKit

/// The menu bar icon: the Claude symbol in green, yellow or red by usage, or gray, and a ring
/// around it for a weekly limit.
enum MenuBarIcon {
    static func color(forPercent percent: Int) -> NSColor {
        switch UsageLevel(percent: percent) {
        case .normal: return NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1.0)   // green
        case .high: return NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)        // yellow
        case .critical: return NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)  // red
        }
    }

    /// For "no data", "cookie rejected" and stale data.
    static let inactiveColor = NSColor.secondaryLabelColor

    /// Drawn on demand so it stays sharp on 1x and Retina screens. A thin outline in the
    /// same color thickens the rays enough to read at 1x.
    ///
    /// With `weeklyPercent`, a ring around a smaller symbol shows that weekly limit, filled
    /// clockwise from 12 o'clock and colored by its level, the rest in translucent white.
    /// The symbol inside goes without the outline, which would merge its rays at 14 pt.
    static func image(color: NSColor, weeklyPercent: Int? = nil) -> NSImage {
        let side: CGFloat = weeklyPercent == nil ? 18 : 20
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let weeklyPercent else {
                drawSymbol(in: rect, color: color, outline: 0.8)
                return true
            }
            let stroke: CGFloat = 2
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = (rect.width - stroke) / 2
            // A fixed color: a label color such as tertiaryLabelColor renders as opaque gray here.
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = stroke
            NSColor(white: 1, alpha: 0.35).setStroke()
            track.stroke()
            // The image is flipped: angles grow clockwise and -90° is 12 o'clock.
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: -90,
                          endAngle: -90 + 360 * min(Double(weeklyPercent) / 100, 1), clockwise: false)
            arc.lineWidth = stroke
            Self.color(forPercent: weeklyPercent).setStroke()
            arc.stroke()
            drawSymbol(in: rect.insetBy(dx: stroke + 1, dy: stroke + 1), color: color, outline: 0)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The symbol scaled into `rect` of a flipped image; `outline` is in symbol units (24-unit box).
    private static func drawSymbol(in rect: NSRect, color: NSColor, outline: CGFloat) {
        let scale = rect.width / (24 + outline)
        let path = NSBezierPath(svgPathData: claudeSymbolPathData)
        path.transform(using: AffineTransform(translationByX: outline / 2, byY: outline / 2))
        path.transform(using: AffineTransform(scale: scale))
        path.transform(using: AffineTransform(translationByX: rect.minX, byY: rect.minY))
        path.lineWidth = outline * scale
        path.lineJoinStyle = .round
        color.set()
        path.fill()
        if outline > 0 { path.stroke() }
    }
}

// Claude symbol from Simple Icons (https://simpleicons.org, CC0), viewBox 0 0 24 24.
// The symbol is a trademark of Anthropic.
private let claudeSymbolPathData = "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"

// Minimal SVG path-data parser: M/m, L/l, H/h, V/v, C/c and Z/z, which is all the
// Claude symbol uses. Numbers may be packed SVG-style ("4.7174-2.6471.079");
// exponents aren't supported.
extension NSBezierPath {
    convenience init(svgPathData d: String) {
        self.init()
        enum Token { case command(Character), number(CGFloat) }
        var tokens: [Token] = []
        var number = ""
        func flush() {
            if let value = Double(number) { tokens.append(.number(CGFloat(value))) }
            number = ""
        }
        for ch in d {
            switch ch {
            case "0"..."9":
                number.append(ch)
            case ".":
                if number.contains(".") { flush() }
                number.append(ch)
            case "-":
                flush()
                number = "-"
            case _ where ch.isLetter:
                flush()
                tokens.append(.command(ch))
            default:
                flush()
            }
        }
        flush()

        var index = 0
        func next() -> CGFloat {
            defer { index += 1 }
            if index < tokens.count, case .number(let value) = tokens[index] { return value }
            return 0
        }
        var command: Character = "M"
        var point = NSPoint.zero
        var subpathStart = NSPoint.zero
        while index < tokens.count {
            if case .command(let c) = tokens[index] {
                command = c
                index += 1
            }
            let origin = command.isLowercase ? point : .zero
            switch command.lowercased() {
            case "m":
                point = NSPoint(x: origin.x + next(), y: origin.y + next())
                move(to: point)
                subpathStart = point
                command = command.isLowercase ? "l" : "L"   // further pairs are line-tos
            case "l":
                point = NSPoint(x: origin.x + next(), y: origin.y + next())
                line(to: point)
            case "h":
                point.x = origin.x + next()
                line(to: point)
            case "v":
                point.y = origin.y + next()
                line(to: point)
            case "c":
                let c1 = NSPoint(x: origin.x + next(), y: origin.y + next())
                let c2 = NSPoint(x: origin.x + next(), y: origin.y + next())
                point = NSPoint(x: origin.x + next(), y: origin.y + next())
                curve(to: point, controlPoint1: c1, controlPoint2: c2)
            case "z":
                close()
                point = subpathStart
                // A number right after Z would be malformed; stop rather than loop.
                if index < tokens.count, case .number = tokens[index] { return }
            default:
                return
            }
        }
    }
}
