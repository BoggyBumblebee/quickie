import AppKit
import SwiftUI

struct AppLaunchConfiguration {
    let opensSettingsOnLaunch: Bool
    let simulatedRegistrationStatus: OSStatus?
    let resetsShortcutToDefault: Bool
    let disablesStatusItem: Bool
    let disablesGlobalHotKey: Bool

    static let current = AppLaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)

    init(arguments: [String]) {
        let environment = ProcessInfo.processInfo.environment
        opensSettingsOnLaunch = arguments.contains("--uitesting-show-settings")
        resetsShortcutToDefault = arguments.contains("--uitesting-reset-shortcut-default")
        disablesStatusItem = arguments.contains("--diagnostic-disable-status-item") || environment["QUICKIE_DISABLE_STATUS_ITEM"] == "1"
        disablesGlobalHotKey = arguments.contains("--diagnostic-disable-global-hotkey") || environment["QUICKIE_DISABLE_GLOBAL_HOTKEY"] == "1"

        if let statusArgument = arguments.first(where: { $0.hasPrefix("--uitesting-registration-status=") }),
           let rawStatus = Int32(statusArgument.split(separator: "=").last ?? "") {
            simulatedRegistrationStatus = OSStatus(rawStatus)
        } else {
            simulatedRegistrationStatus = nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private lazy var statusMenu = makeStatusMenu()
    private var hotKeyRegistrar: GlobalHotKeyRegistrar?
    private let launchAtLoginManager = LaunchAtLoginManager.shared
    private var defaultsObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var needsStatusItemConfiguration = false

    func applicationDidFinishLaunching(_ : Notification) {
        HotKeySettings.registerDefaults()
        LaunchAtLoginSettings.registerDefaults()
        ReminderDefaultsSettings.registerDefaults()
        configureUITestDefaultsIfNeeded()
        configurePopover()
        configureGlobalHotKey()
        _ = launchAtLoginManager.synchronize()
        observeHotKeySettings()
        scheduleStatusItemConfiguration()

        if AppLaunchConfiguration.current.opensSettingsOnLaunch {
            showSettings()
        }
    }

    private func scheduleStatusItemConfiguration() {
        guard !AppLaunchConfiguration.current.disablesStatusItem else { return }

        needsStatusItemConfiguration = true

        if NSApp.isActive {
            configureStatusItem()
        }
    }

    private func configureUITestDefaultsIfNeeded() {
        guard AppLaunchConfiguration.current.resetsShortcutToDefault else { return }

        let defaults = UserDefaults.standard
        defaults.set(Int(GlobalHotKey.defaultHotKey.keyCode), forKey: HotKeySettings.keyCodeKey)
        defaults.set(Int(GlobalHotKey.defaultHotKey.carbonModifiers), forKey: HotKeySettings.modifiersKey)
        defaults.set(Int(noErr), forKey: HotKeySettings.registrationStatusKey)
        defaults.synchronize()
    }

    func applicationWillTerminate(_ : Notification) {
        hotKeyRegistrar?.unregister()
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func applicationDidBecomeActive(_ : Notification) {
        guard needsStatusItemConfiguration else { return }
        configureStatusItem()
    }

    private func configureStatusItem() {
        guard !AppLaunchConfiguration.current.disablesStatusItem else { return }
        guard statusItem == nil else { return }

        needsStatusItemConfiguration = false
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

    private func showPopoverFromHotKey() {
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
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

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

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
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: AppMetadata.current.aboutPanelVersionString
        ])
    }

    @objc private func showSettings() {
        closePopover()

        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettingsFromCommand() {
        showSettings()
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quickie Settings"
        window.minSize = NSSize(width: 540, height: 420)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView())
        return window
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

    private func configureGlobalHotKey() {
        guard !AppLaunchConfiguration.current.disablesGlobalHotKey else {
            hotKeyRegistrar?.unregister()
            HotKeySettings.setRegistrationStatus(noErr)
            return
        }

        if let simulatedStatus = AppLaunchConfiguration.current.simulatedRegistrationStatus {
            HotKeySettings.setRegistrationStatus(simulatedStatus)
            return
        }

        if hotKeyRegistrar == nil {
            hotKeyRegistrar = GlobalHotKeyRegistrar { [weak self] in
                self?.showPopoverFromHotKey()
            }
        }

        guard HotKeySettings.isEnabled() else {
            hotKeyRegistrar?.unregister()
            HotKeySettings.setRegistrationStatus(noErr)
            return
        }

        guard let status = hotKeyRegistrar?.register(hotKey: HotKeySettings.selectedHotKey()) else {
            return
        }

        HotKeySettings.setRegistrationStatus(status)

        if status != noErr {
            NSLog("Quickie could not register global shortcut: \(status)")
        }
    }

    private func observeHotKeySettings() {
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureGlobalHotKey()
            }
        }
    }
}
