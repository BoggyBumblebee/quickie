import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private lazy var statusMenu = makeStatusMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.image()
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.toolTip = "Quickie"
        statusItem = item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 392, height: 430)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard shouldShowStatusMenu(for: NSApp.currentEvent) else {
            togglePopover()
            return
        }

        closePopover()
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    private func shouldShowStatusMenu(for event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }

        let viewModel = ReminderFormViewModel(reminderService: EventKitReminderService())
        viewModel.onClose = { [weak self] in
            self?.closePopover()
        }

        popover.contentViewController = NSHostingController(rootView: ReminderFormView(viewModel: viewModel))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: "About Quickie", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let helpMenu = NSMenu(title: "Help")

        let quickieHelpItem = NSMenuItem(title: "Quickie Help", action: #selector(openQuickieHelp), keyEquivalent: "")
        quickieHelpItem.target = self
        helpMenu.addItem(quickieHelpItem)

        let quickStartItem = NSMenuItem(title: "Quick Start", action: #selector(openQuickStart), keyEquivalent: "")
        quickStartItem.target = self
        helpMenu.addItem(quickStartItem)

        let troubleshootingItem = NSMenuItem(title: "Troubleshooting", action: #selector(openTroubleshooting), keyEquivalent: "")
        troubleshootingItem.target = self
        helpMenu.addItem(troubleshootingItem)

        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = helpMenu
        menu.addItem(helpItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Quickie", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openQuickieHelp() {
        HelpController.shared.open(.home)
    }

    @objc private func openQuickStart() {
        HelpController.shared.open(.quickStart)
    }

    @objc private func openTroubleshooting() {
        HelpController.shared.open(.troubleshooting)
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
