import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The pages the popup opens over its usage page.
enum PopupPage: Hashable {
    case settings, cookie, services

    var title: String {
        switch self {
        case .settings: return "Settings"
        case .cookie: return "Session Cookie"
        case .services: return "Tracked Services"
        }
    }
}

/// The popup: a header, and the usage page or one of the pages opened over it.
struct UsageView: View {
    @ObservedObject var usage: UsageStore
    @ObservedObject var status: StatusStore
    @ObservedObject var updates: UpdateStore
    @ObservedObject var prefs: Preferences
    @State private var path: [PopupPage]
    @State private var cookieInput = ""
    @State private var measuredHeight: CGFloat = 250
    @Environment(\.colorScheme) private var colorScheme

    init(usage: UsageStore, status: StatusStore, updates: UpdateStore, prefs: Preferences,
         path: [PopupPage] = []) {
        _usage = ObservedObject(wrappedValue: usage)
        _status = ObservedObject(wrappedValue: status)
        _updates = ObservedObject(wrappedValue: updates)
        _prefs = ObservedObject(wrappedValue: prefs)
        _path = State(initialValue: path)
    }

    private var page: PopupPage? { path.last }

    /// The icon as drawn in Headroom.icns, without the margin NSApp.applicationIconImage gets
    /// around app icons.
    private static let appIcon = Bundle.main.image(forResource: "Headroom") ?? NSApp.applicationIconImage!

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                // A page of its own each time, so a new page starts at the top.
                ScrollView {
                    pageContent
                        .padding(.horizontal, 12)
                        .padding(.bottom, 14)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                            }
                        )
                }
                .id(page)
                .transition(.opacity)
            }
            .frame(height: min(max(measuredHeight, 40), Metrics.maxBodyHeight))
        }
        .frame(width: Metrics.popupWidth)
        // Dark: a light scrim over the native material, between fully native (too
        // transparent) and a 0.62 scrim (too dark). Light: a near-opaque backing, or a
        // dark desktop bleeds through as murky blue-gray when forced.
        .background(
            colorScheme == .dark
                ? Color(red: 0.07, green: 0.07, blue: 0.08).opacity(0.3)
                : Color.white.opacity(0.85)
        )
        .onPreferenceChange(ContentHeightKey.self) { value in
            guard value > 0 else { return }
            measuredHeight = value
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            // The popup opens on the usage page again, except from the Session Cookie page,
            // so a cookie copied in the browser meanwhile can be pasted right away.
            if page != .cookie { path = [] }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if path.isEmpty {
                Image(nsImage: Self.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
            } else {
                IconButton(systemName: "chevron.left", help: "Back", action: back)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(page?.title ?? AppInfo.name)
                    .font(.system(size: 15, weight: .semibold))
                if page == nil, usage.usage != nil {
                    updatedLine
                }
            }
            Spacer(minLength: 8)
            if page == nil {
                IconButton(systemName: "arrow.clockwise", help: "Refresh now") {
                    usage.refresh(force: true)
                    status.refresh()
                    updates.refresh()
                }
                IconButton(systemName: "gearshape", help: "Settings") { open(.settings) }
            }
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// When the numbers were fetched; stale data says how old it is, in orange.
    private var updatedLine: some View {
        let stale = usage.isStale()
        let time = Format.time(usage.lastUpdated)
        return Text(stale ? "Updated \(time) · \(Format.relative(usage.lastUpdated))" : "Updated \(time)")
            .font(.system(size: 11))
            .foregroundColor(stale ? .orange : Color.secondaryText)
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case nil:
            UsagePage(usage: usage, status: status, updates: updates, open: open)
        case .settings:
            SettingsPage(prefs: prefs, status: status, usage: usage, open: open)
        case .cookie:
            CookiePage(usage: usage, cookieInput: $cookieInput, saved: { withAnimation(.easeInOut(duration: 0.15)) { path = [] } })
        case .services:
            ServicesPage(status: status)
        }
    }

    private func open(_ page: PopupPage) {
        withAnimation(.easeInOut(duration: 0.15)) { path.append(page) }
    }

    private func back() {
        if page == .cookie { cookieInput = "" }
        withAnimation(.easeInOut(duration: 0.15)) { _ = path.popLast() }
    }
}

/// The usage page: a banner, a problem, the limits and Claude's status.
private struct UsagePage: View {
    @ObservedObject var usage: UsageStore
    @ObservedObject var status: StatusStore
    @ObservedObject var updates: UpdateStore
    let open: (PopupPage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BannerCard(updates: updates)

            if let problem = usage.problem {
                ProblemCard(problem: problem,
                            dataTime: usage.usage == nil ? nil : usage.lastUpdated,
                            updateCookie: { open(.cookie) })
            }

            if let snapshot = usage.usage {
                if let notice = usage.notice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundColor(Color.secondaryText)
                        .padding(.horizontal, 4)
                }
                // Gray while the numbers aren't current, as in the menu bar.
                LimitsSummary(snapshot: snapshot, usage: usage)
                    .environment(\.usageIsStale, usage.isStale())
            } else if !usage.hasCookie {
                WelcomeCard(connect: { open(.cookie) })
            } else if usage.problem == nil {
                Card {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(usage.notice ?? "Fetching your usage…")
                            .font(.system(size: 12))
                            .foregroundColor(Color.secondaryText)
                    }
                }
            }

            if status.hasFetched {
                StatusSection(status: status)
            }
        }
    }
}

/// Why the latest fetch failed, in plain words, with a way to fix a rejected cookie.
private struct ProblemCard: View {
    let problem: UsageProblem
    let dataTime: Date?                  // when the data still on screen was fetched
    let updateCookie: () -> Void

    var body: some View {
        Card(tint: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(problem.message(dataTime: dataTime))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if problem == .cookieRejected {
                    Button("Update Session Cookie", action: updateCookie)
                        .buttonStyle(PillButtonStyle(kind: .prominent))
                }
            }
        }
    }
}

/// Before the first cookie: what Headroom needs, and the way to the Session Cookie page.
private struct WelcomeCard: View {
    let connect: () -> Void

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect your Claude account")
                    .font(.system(size: 13, weight: .semibold))
                Text("Headroom reads your usage from claude.ai with your session cookie, which it keeps in your keychain.")
                    .font(.system(size: 12))
                    .foregroundColor(Color.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add Session Cookie", action: connect)
                    .buttonStyle(PillButtonStyle(kind: .prominent))
                    .padding(.top, 2)
            }
        }
    }
}

private struct UsageIsStaleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The limits on screen are old: the last fetch failed long ago. They show in gray.
    var usageIsStale: Bool {
        get { self[UsageIsStaleKey.self] }
        set { self[UsageIsStaleKey.self] = newValue }
    }
}

/// A weekly limit besides the main one: Sonnet, or Fable while it's in use.
private struct NamedLimit: Identifiable {
    let title: String
    let window: UsageWindow
    var id: String { title }
}

/// The session and weekly limits as rings side by side, the other limits and extra usage as
/// bars in a card below, and the info line under them.
private struct LimitsSummary: View {
    let snapshot: UsageSnapshot
    @ObservedObject var usage: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GaugeTile(title: "Session", help: "The 5-hour session limit", window: snapshot.session)
                GaugeTile(title: "Weekly", help: "The weekly limit for all models", window: snapshot.weekly)
            }
            if !otherLimits.isEmpty || extraActive {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(otherLimits.enumerated()), id: \.element.id) { index, limit in
                            if index > 0 { RowDivider() }
                            LimitRow(title: limit.title, window: limit.window)
                        }
                        if extraActive {
                            if !otherLimits.isEmpty { RowDivider() }
                            ExtraUsageRow(usage: usage)
                        }
                    }
                }
            }
            infoLine
        }
    }

    private var otherLimits: [NamedLimit] {
        var limits: [NamedLimit] = []
        if let sonnet = snapshot.weeklySonnet {
            limits.append(NamedLimit(title: "Weekly Sonnet", window: sonnet))
        }
        // Fable shows only while it's in use (it's counted separately).
        if let fable = snapshot.weeklyFable, fable.percent >= 1 {
            limits.append(NamedLimit(title: "Weekly Fable", window: fable))
        }
        return limits
    }

    private var extraActive: Bool {
        usage.hasCreditUsage || usage.freeCreditsMinor > 0
    }

    // A discreet line: the limit resets left, if any; otherwise which of Fable and extra
    // usage isn't in use (nothing when both are).
    @ViewBuilder private var infoLine: some View {
        if usage.limitResets.count > 0 {
            let n = usage.limitResets.count
            // The last usable day: an end at local midnight would read as the next day.
            let until = usage.limitResets.endsAt.map { " until \(Format.monthDay($0.addingTimeInterval(-1)))" } ?? ""
            caption("\(n) usage-limit reset\(n == 1 ? "" : "s") available\(until)")
        } else {
            let fableActive = (snapshot.weeklyFable?.percent ?? 0) >= 1
            if !fableActive || !extraActive {
                caption(
                    !fableActive && !extraActive ? "No Fable or extra usage"
                    : !extraActive ? "No extra usage"
                    : "No Fable usage"
                )
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Color.secondaryText)
            .opacity(0.7)
            .padding(.horizontal, 4)
    }
}

/// A limit as a ring with its percentage inside, its name and when it resets.
private struct GaugeTile: View {
    let title: String
    let help: String
    let window: UsageWindow
    @Environment(\.usageIsStale) private var stale
    @Environment(\.fixedNow) private var fixedNow

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RingGauge(fraction: window.fraction, color: stale ? .gray : .usage(window.fraction))
                Text("\(window.percent)%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .frame(width: 76, height: 76)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(window.resetsAt.map { "Resets \(Format.resetShort($0, now: fixedNow ?? Date()))" } ?? " ")
                    .font(.system(size: 11))
                    .foregroundColor(Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(Color.card)
        )
        .help(help)
    }
}

/// A limit as a bar: its name and reset on the left, the percentage on the right.
private struct LimitRow: View {
    let title: String
    let window: UsageWindow
    @Environment(\.usageIsStale) private var stale
    @Environment(\.fixedNow) private var fixedNow

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let resetsAt = window.resetsAt {
                        Text("Resets \(Format.resetShort(resetsAt, now: fixedNow ?? Date()))")
                            .font(.system(size: 11))
                            .foregroundColor(Color.secondaryText)
                    }
                }
                Spacer()
                Text("\(window.percent)%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
            }
            LimitBar(value: window.fraction, color: stale ? .gray : .usage(window.fraction))
        }
    }
}

/// Pay-as-you-go spend against the monthly limit, and free credits left.
private struct ExtraUsageRow: View {
    @ObservedObject var usage: UsageStore
    @Environment(\.usageIsStale) private var stale

    var body: some View {
        let extra = usage.extra
        let fraction = extra.limitMinor > 0 ? Double(extra.spentMinor) / Double(extra.limitMinor) : 0
        let percent = Int((fraction * 100).rounded())
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Extra usage")
                    .font(.system(size: 12, weight: .semibold))
                // Switched off on claude.ai: the spend stays, but nothing more is charged.
                if !extra.isEnabled {
                    Text("off")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
                Spacer()
                if usage.hasCreditUsage {
                    Text(extra.limitMinor > 0
                         ? "\(money(extra.spentMinor)) of \(money(extra.limitMinor))"
                         : "\(money(extra.spentMinor)) spent")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
            }

            // Spend against the monthly limit, only when there's actual spend.
            if usage.hasCreditUsage, extra.limitMinor > 0 {
                LimitBar(value: min(fraction, 1.0), color: extra.isEnabled && !stale ? .usage(fraction) : .gray)
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    // The exact % up to the limit; once over, just "over the monthly limit".
                    if usage.hasCreditUsage, extra.limitMinor > 0 {
                        detail(percent > 100 ? "Over the monthly limit" : "\(percent)% of the monthly limit")
                    }
                    if let until = extra.disabledUntil, until > Date() {
                        detail("Off until \(Format.monthDay(until))")
                    }
                    if usage.freeCreditsMinor > 0 {
                        detail("\(money(usage.freeCreditsMinor)) free credits left")
                    }
                }
                Spacer()
                LinkButton(title: "Manage") { NSWorkspace.shared.open(AppInfo.usageSettingsURL) }
            }
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Color.secondaryText)
    }

    private func money(_ minor: Int) -> String {
        Format.shortMoney(minor, currency: usage.currency)
    }
}
