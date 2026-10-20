import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The popup.
struct UsageView: View {
    @ObservedObject var usage: UsageStore
    @ObservedObject var status: StatusStore
    @ObservedObject var updates: UpdateStore
    @ObservedObject var prefs: Preferences
    @State private var cookieInput = ""
    @State private var showingCookieInput: Bool
    @State private var showingSettings: Bool
    @State private var measuredHeight: CGFloat = 250
    @Environment(\.colorScheme) private var colorScheme

    private let maxPopupHeight: CGFloat = 600

    init(usage: UsageStore, status: StatusStore, updates: UpdateStore, prefs: Preferences,
         showingCookieInput: Bool = false, showingSettings: Bool = false) {
        _usage = ObservedObject(wrappedValue: usage)
        _status = ObservedObject(wrappedValue: status)
        _updates = ObservedObject(wrappedValue: updates)
        _prefs = ObservedObject(wrappedValue: prefs)
        _showingCookieInput = State(initialValue: showingCookieInput)
        _showingSettings = State(initialValue: showingSettings)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                        }
                    )
            }
            .frame(width: 360, height: min(max(measuredHeight, 100), maxPopupHeight))
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
            .onChange(of: showingSettings) { isOpen in
                guard isOpen else { return }
                // Opening Settings scrolls to its end, so the last options are in view.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("settings-anchor", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Usage")
                .font(.headline)
                .padding(.bottom, 4)

            BannerCard(updates: updates)

            if let problem = usage.problem {
                ProblemNotice(problem: problem,
                              dataTime: usage.usage == nil ? nil : usage.lastUpdated,
                              updateCookie: showingCookieInput ? nil : { showingCookieInput = true })
            } else if let notice = usage.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.bottom, 8)
            }

            if let snapshot = usage.usage {
                UsageRows(snapshot: snapshot, usage: usage)
            } else if !usage.hasCookie {
                Text("👋 Welcome! Set your session cookie below to get started.")
                    .font(.subheadline)
                    .foregroundColor(Color.secondaryText)
                    .padding(.vertical, 8)
            } else if usage.problem == nil && usage.notice == nil {
                Text("Fetching your usage…")
                    .font(.subheadline)
                    .foregroundColor(Color.secondaryText)
                    .padding(.vertical, 8)
            }

            if status.hasFetched {
                Divider()
                StatusSection(status: status)
            }

            if usage.usage != nil {
                Divider()
                lastUpdatedRow
            }

            Button(showingCookieInput ? "Hide Session Cookie" : "Session Cookie") {
                showingCookieInput.toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)

            if showingCookieInput {
                CookiePanel(usage: usage, cookieInput: $cookieInput)
            }

            Button(showingSettings ? "Hide Settings" : "Settings") {
                showingSettings.toggle()
            }
            .buttonStyle(.borderless)
            .font(.caption)

            if showingSettings {
                SettingsPanel(prefs: prefs, status: status, usage: usage)

                // Anchor for scroll-to-bottom when Settings opens
                Color.clear
                    .frame(height: 1)
                    .id("settings-anchor")
            }
        }
    }

    private var lastUpdatedRow: some View {
        // Stale data says how old it is, in orange.
        let stale = usage.isStale()
        let time = Format.time(usage.lastUpdated)
        return HStack {
            Text(stale ? "Last updated: \(time) · \(Format.relative(usage.lastUpdated))" : "Last updated: \(time)")
                .font(.caption)
                .foregroundColor(stale ? .orange : Color.secondaryText)
            Spacer()
            Button("Refresh") {
                usage.refresh(force: true)
                status.refresh()
                updates.refresh()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}

/// Why the latest fetch failed, in plain words, with a way to fix a rejected cookie.
private struct ProblemNotice: View {
    let problem: UsageProblem
    let dataTime: Date?                  // when the data still on screen was fetched
    let updateCookie: (() -> Void)?      // nil while the cookie panel is open

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(problem.message(dataTime: dataTime))
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if problem == .cookieRejected, let updateCookie {
                Button(action: updateCookie) {
                    Text("Update session cookie →")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.bottom, 8)
    }
}

/// The limits, extra usage, and the info line under them.
private struct UsageRows: View {
    let snapshot: UsageSnapshot
    @ObservedObject var usage: UsageStore

    var body: some View {
        UsageRow(title: "Session (5 hour)", window: snapshot.session, includeDate: false)
        UsageRow(title: "Weekly (7 day)", window: snapshot.weekly, includeDate: true)
        if let sonnet = snapshot.weeklySonnet {
            UsageRow(title: "Weekly Sonnet (7 day)", window: sonnet, includeDate: true)
        }
        // Fable shows only while it's in use (it's counted separately).
        if let fable = snapshot.weeklyFable, fable.percent >= 1 {
            UsageRow(title: "Weekly Fable (7 day)", window: fable, includeDate: true)
        }
        if extraActive {
            ExtraUsageRow(usage: usage)
        }
        infoLine
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
            Text("\(n) usage-limit reset\(n == 1 ? "" : "s") available\(until)")
                .font(.caption2)
                .foregroundColor(Color.secondaryText)
                .opacity(0.6)
        } else {
            let fableActive = (snapshot.weeklyFable?.percent ?? 0) >= 1
            if !fableActive || !extraActive {
                Text(
                    !fableActive && !extraActive ? "No Fable or extra usage"
                    : !extraActive ? "No extra usage"
                    : "No Fable usage"
                )
                .font(.caption2)
                .foregroundColor(Color.secondaryText)
                .opacity(0.6)
            }
        }
    }
}

private struct UsageRow: View {
    let title: String
    let window: UsageWindow
    let includeDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                if let resetsAt = window.resetsAt {
                    Text("Resets \(Format.reset(resetsAt, includeDate: includeDate))")
                        .font(.caption)
                        .foregroundColor(Color.secondaryText)
                }
            }

            LimitBar(value: window.fraction, color: .usage(window.fraction))

            Text("\(window.percent)% used")
                .font(.caption)
                .foregroundColor(Color.secondaryText)
        }
    }
}

/// Pay-as-you-go spend against the monthly limit, and free credits left.
private struct ExtraUsageRow: View {
    @ObservedObject var usage: UsageStore

    var body: some View {
        let extra = usage.extra
        let fraction = extra.limitMinor > 0 ? Double(extra.spentMinor) / Double(extra.limitMinor) : 0
        let percent = Int((fraction * 100).rounded())
        // The exact % up to the limit; once over, just "over limit".
        let percentLabel = percent > 100 ? "over limit" : "\(percent)%"
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Extra usage")
                    .font(.subheadline)
                // Switched off on claude.ai: the spend stays, but nothing more is charged.
                if !extra.isEnabled {
                    Text("off")
                        .font(.caption)
                        .foregroundColor(Color.secondaryText)
                }
                Spacer()
                Button(action: { NSWorkspace.shared.open(AppInfo.usageSettingsURL) }) {
                    Text("Manage →")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
            }

            // Spend against the monthly limit, only when there's actual spend.
            if usage.hasCreditUsage {
                if extra.limitMinor > 0 {
                    LimitBar(value: min(fraction, 1.0), color: extra.isEnabled ? .usage(fraction) : .gray)
                }
                HStack {
                    Text(extra.limitMinor > 0
                         ? "\(money(extra.spentMinor)) of \(money(extra.limitMinor)) · \(percentLabel)"
                         : "\(money(extra.spentMinor)) spent")
                        .font(.caption)
                        .foregroundColor(Color.secondaryText)
                    Spacer()
                    if let until = extra.disabledUntil, until > Date() {
                        Text("Off until \(Format.monthDay(until))")
                            .font(.caption)
                            .foregroundColor(Color.secondaryText)
                    }
                }
            }

            if usage.freeCreditsMinor > 0 {
                Text("\(money(usage.freeCreditsMinor)) free credits left")
                    .font(.caption2)
                    .foregroundColor(Color.secondaryText)
                    .opacity(0.85)
            }
        }
    }

    private func money(_ minor: Int) -> String {
        Format.money(minor, currency: usage.currency)
    }
}
