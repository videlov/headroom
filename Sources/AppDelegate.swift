import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var prefs: Preferences!
    private var usage: UsageStore!
    private var status: StatusStore!
    private var updates: UpdateStore!
    private var menuBar: MenuBarController!
    private var hotKey: HotKey!
    private var usageTimer: Timer?
    private var timers: [Timer] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        HTTP.removeLegacyStorage()
        Notifier.setUp()

        prefs = Preferences()
        usage = UsageStore(prefs: prefs)
        status = StatusStore(prefs: prefs)
        updates = UpdateStore()
        menuBar = MenuBarController(usage: usage, status: status, updates: updates, prefs: prefs)
        hotKey = HotKey { [weak self] in self?.menuBar.togglePopover() }

        applyPreferences()
        observeSystem()

        refreshAll()
        // Usage polls at the interval chosen in Settings (see applyPreferences). The
        // Anthropic status changes less often, and new versions rarely.
        timers = [
            Self.repeatingTimer(every: 5 * 60) { [weak self] in self?.status.refresh() },
            Self.repeatingTimer(every: 3 * 3600) { [weak self] in self?.updates.refresh() },
        ]
    }

    /// Applies the saved settings now and again whenever they change in Settings.
    private func applyPreferences() {
        prefs.$refreshIntervalMinutes
            .removeDuplicates()
            .sink { [weak self] minutes in self?.scheduleUsageRefresh(minutes: minutes) }
            .store(in: &cancellables)
        prefs.$shortcutEnabled
            .sink { [weak self] enabled in self?.hotKey.setEnabled(enabled) }
            .store(in: &cancellables)
        prefs.$appearanceMode
            .sink { [weak self] mode in self?.applyAppearance(mode) }
            .store(in: &cancellables)
    }

    private func observeSystem() {
        // Re-resolve "System" when macOS switches between light and dark. The defaults key
        // can lag the notification, so wait a moment.
        DistributedNotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                self.applyAppearance(self.prefs.appearanceMode)
            }
        }
        // The numbers are stale after sleep. Give the network a few seconds to come back.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.refreshAll()
            }
        }
    }

    private func refreshAll() {
        usage.refresh()
        status.refresh()
        updates.refresh()
    }

    private func scheduleUsageRefresh(minutes: Int) {
        usageTimer?.invalidate()
        usageTimer = Self.repeatingTimer(every: TimeInterval(minutes * 60)) { [weak self] in self?.usage.refresh() }
    }

    /// A timer on the main run loop that also fires while a menu is open.
    private static func repeatingTimer(every seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = min(seconds / 10, 10)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        // Always set an explicit, resolved appearance ("System" resolves to the current
        // macOS setting) so every mode uses the same rendering path: inherited "vibrant"
        // rendering drops the bar tints and shades colors slightly differently. Set it on
        // the popover too; it doesn't reliably restyle from NSApp.appearance alone.
        let systemIsDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let isDark = mode == .dark || (mode == .system && systemIsDark)
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        menuBar.setAppearance(appearance)
    }
}
