import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @AppStorage(HotKeySettings.enabledKey) private var isGlobalShortcutEnabled = true
    @AppStorage(HotKeySettings.keyCodeKey) private var hotKeyCode = Int(GlobalHotKey.defaultHotKey.keyCode)
    @AppStorage(HotKeySettings.modifiersKey) private var hotKeyModifiers = Int(GlobalHotKey.defaultHotKey.carbonModifiers)
    @AppStorage(HotKeySettings.registrationStatusKey) private var registrationStatus = Int(noErr)
    @State private var validationMessage: String?

    private var registrationErrorMessage: String? {
        guard isGlobalShortcutEnabled, registrationStatus != Int(noErr) else { return nil }
        return HotKeyRegistrationError.message(for: OSStatus(registrationStatus))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Global Shortcut")
                    .font(.headline)

                Toggle("Enable shortcut", isOn: $isGlobalShortcutEnabled)

                HStack {
                    Text("Shortcut")
                        .frame(width: 90, alignment: .leading)

                    ShortcutRecorderView(hotKey: hotKey, validationMessage: $validationMessage)
                        .disabled(!isGlobalShortcutEnabled)
                        .frame(width: 194, height: 24)
                        .accessibilityIdentifier("settings.shortcutRecorder")

                    Button("Reset to Default") {
                        validationMessage = nil
                        hotKey.wrappedValue = .defaultHotKey
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isGlobalShortcutEnabled)
                    .accessibilityIdentifier("settings.resetShortcut")

                    Spacer()
                }

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let registrationErrorMessage {
                    Label(
                        registrationErrorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.registrationWarning")
                }
            }

            Spacer(minLength: 0)

            Divider()

            HStack {
                Button {
                    HelpController.shared.open(.home)
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings.help")

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Quickie", systemImage: "power")
                }
                .accessibilityIdentifier("settings.quit")
            }
        }
        .padding(24)
        .frame(width: 460, height: 220)
    }

    private var hotKey: Binding<GlobalHotKey> {
        Binding {
            GlobalHotKey(
                keyCode: UInt32(hotKeyCode),
                carbonModifiers: UInt32(hotKeyModifiers)
            )
        } set: { newHotKey in
            hotKeyCode = Int(newHotKey.keyCode)
            hotKeyModifiers = Int(newHotKey.carbonModifiers)
            registrationStatus = Int(noErr)
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var hotKey: GlobalHotKey
    @Binding var validationMessage: String?

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onRecord = { hotKey = $0 }
        button.onValidation = { validationMessage = $0 }
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.hotKey = hotKey
    }
}

private final class ShortcutRecorderButton: NSButton {
    var hotKey = GlobalHotKey.defaultHotKey {
        didSet {
            updateTitle()
        }
    }

    var onRecord: (GlobalHotKey) -> Void = { _ in }
    var onValidation: (String?) -> Void = { _ in }
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        imagePosition = .imageLeading
        identifier = NSUserInterfaceItemIdentifier("settings.shortcutRecorder")
        setAccessibilityIdentifier("settings.shortcutRecorder")
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    @objc private func beginRecording() {
        isRecording = true
        onValidation(nil)
        window?.makeFirstResponder(self)
        updateTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        record(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        record(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }

        guard let recordedHotKey = GlobalHotKey(event: event) else {
            onValidation("Use Command, Control, or Option with another key.")
            return
        }

        hotKey = recordedHotKey
        onRecord(recordedHotKey)
        onValidation(nil)
        finishRecording()
    }

    private func finishRecording() {
        isRecording = false
        window?.makeFirstResponder(nil)
        updateTitle()
    }

    private func updateTitle() {
        title = isRecording ? "Press shortcut..." : hotKey.displayName
    }
}
