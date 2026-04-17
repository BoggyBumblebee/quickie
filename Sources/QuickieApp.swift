import SwiftUI

@main
struct QuickieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showSettingsFromCommand()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .help) {
                Button("Quickie Help") {
                    HelpController.shared.open(.home)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])

                Button("Quick Start") {
                    HelpController.shared.open(.quickStart)
                }

                Button("Troubleshooting") {
                    HelpController.shared.open(.troubleshooting)
                }
            }
        }
    }
}
