import AppKit
import Combine
import SwiftUI

/// The status item: its icon and percentage, the popover, and the right-click menu.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let usage: UsageStore
    private var shownState: MenuBarState?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(usage: UsageStore, status: StatusStore, updates: UpdateStore, prefs: Preferences) {
        self.usage = usage
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // Redraw when the usage changes, and every 30 s so old data turns gray on time.
        // objectWillChange fires before the change, so look on the next run loop pass.
        usage.objectWillChange
            .merge(with: Timer.publish(every: 30, on: .main, in: .common).autoconnect().map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.render() }
            .store(in: &cancellables)
        render()

        popover.contentSize = NSSize(width: 360, height: 320)   // a first guess; SwiftUI sets the real size
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(rootView: UsageView(usage: usage, status: status, updates: updates, prefs: prefs))
        // Hand SwiftUI's size to the popover as preferredContentSize. The default sizing
        // (min/intrinsic/max-size constraints, no preferredContentSize) leaves the popover
        // positioned for the 320pt guess while its window grows upward to fit the content,
        // pushing the top of the popup above the screen (seen with the macOS 27 SDK).
        if #available(macOS 13.0, *) {
            host.sizingOptions = [.preferredContentSize]
        }
        popover.contentViewController = host
    }

    func setAppearance(_ appearance: NSAppearance?) {
        popover.appearance = appearance
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            openPopover()
        }
    }

    private func render() {
        let state = usage.menuBarState()
        guard state != shownState, let button = statusItem.button else { return }
        shownState = state
        switch state {
        case .noData:
            button.image = MenuBarIcon.image(color: MenuBarIcon.inactiveColor)
            button.title = ""
        case .cookieRejected:
            button.image = MenuBarIcon.image(color: MenuBarIcon.inactiveColor)
            button.title = " !"
        case .stale(let percent):
            button.image = MenuBarIcon.image(color: MenuBarIcon.inactiveColor)
            button.attributedTitle = NSAttributedString(string: " \(percent)%", attributes: [
                .font: NSFont.menuBarFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        case .current(let percent, let fullest):
            button.image = MenuBarIcon.image(color: MenuBarIcon.color(forPercent: fullest))
            button.title = " \(percent)%"
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // A transient popover doesn't always close on clicks in other apps; this does.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Toggle Usage (⌘U)", action: #selector(togglePopover), keyEquivalent: "u")
        toggle.keyEquivalentModifierMask = .command
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
