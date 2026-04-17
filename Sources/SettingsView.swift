import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    private let labelColumnWidth: CGFloat = 140
    private let inputColumnWidth: CGFloat = 320

    @AppStorage(LaunchAtLoginSettings.enabledKey) private var launchesAtLogin = LaunchAtLoginSettings.defaultEnabled
    @AppStorage(HotKeySettings.enabledKey) private var isGlobalShortcutEnabled = true
    @AppStorage(HotKeySettings.keyCodeKey) private var hotKeyCode = Int(GlobalHotKey.defaultHotKey.keyCode)
    @AppStorage(HotKeySettings.modifiersKey) private var hotKeyModifiers = Int(GlobalHotKey.defaultHotKey.carbonModifiers)
    @AppStorage(HotKeySettings.registrationStatusKey) private var registrationStatus = Int(noErr)

    @AppStorage(ReminderDefaultsSettings.titleKey) private var defaultReminderTitle = ReminderDraftDefaults.standard.title
    @AppStorage(ReminderDefaultsSettings.dateOffsetDaysKey) private var defaultDateOffsetDays = ReminderDraftDefaults.standard.dateOffsetDays
    @AppStorage(ReminderDefaultsSettings.timeModeKey) private var defaultTimeMode = ReminderDraftDefaults.standard.timeMode.rawValue
    @AppStorage(ReminderDefaultsSettings.customHourKey) private var defaultCustomHour = ReminderDraftDefaults.standard.customHour
    @AppStorage(ReminderDefaultsSettings.customMinuteKey) private var defaultCustomMinute = ReminderDraftDefaults.standard.customMinute
    @AppStorage(ReminderDefaultsSettings.urgentKey) private var defaultUrgent = ReminderDraftDefaults.standard.urgent
    @AppStorage(ReminderDefaultsSettings.listNameKey) private var defaultListName = ReminderDraftDefaults.standard.listName
    @AppStorage(ReminderDefaultsSettings.tagsTextKey) private var defaultTagsText = ReminderDraftDefaults.standard.tagsText

    @StateObject private var reminderDefaultsModel = ReminderDefaultsSettingsViewModel()
    @State private var isSyncingLaunchAtLoginToggle = false
    @State private var launchAtLoginStatusMessage: String?
    @State private var launchAtLoginErrorMessage: String?
    @State private var validationMessage: String?

    private var registrationErrorMessage: String? {
        guard isGlobalShortcutEnabled, registrationStatus != Int(noErr) else { return nil }
        return HotKeyRegistrationError.message(for: OSStatus(registrationStatus))
    }

    private var selectedTimeMode: ReminderTimeDefaultMode {
        ReminderTimeDefaultMode(rawValue: defaultTimeMode) ?? .nextWholeHour
    }

    private var dateOffsetDescription: String {
        switch defaultDateOffsetDays {
        case 0:
            "Today"
        case 1:
            "Tomorrow"
        default:
            "In \(defaultDateOffsetDays) days"
        }
    }

    private var dateOffsetDetail: String {
        switch defaultDateOffsetDays {
        case 0:
            "Quickie will prefill today's date."
        case 1:
            "Quickie will prefill tomorrow's date."
        default:
            "Quickie will prefill a date \(defaultDateOffsetDays) days ahead."
        }
    }

    private var availableReminderListNames: [String] {
        let names = reminderDefaultsModel.lists.map(\.name)
        if defaultListName.isEmpty {
            return names
        }

        if names.contains(where: { $0.localizedCaseInsensitiveCompare(defaultListName) == .orderedSame }) {
            return names
        }

        return [defaultListName] + names
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appSection
                shortcutSection
                reminderDefaultsSection
                Divider()
                footerSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 460)
        .task {
            refreshLaunchAtLoginState()
            await reminderDefaultsModel.loadListsIfNeeded()
        }
        .onChange(of: launchesAtLogin) { _, newValue in
            guard !isSyncingLaunchAtLoginToggle else { return }
            applyLaunchAtLoginPreference(newValue)
        }
    }

    private var appSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App")
                .font(.headline)

            Toggle("Launch Quickie at login", isOn: $launchesAtLogin)

            if let launchAtLoginStatusMessage {
                Text(launchAtLoginStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let launchAtLoginErrorMessage {
                Label(launchAtLoginErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Shortcut")
                .font(.headline)

            Toggle("Enable shortcut", isOn: $isGlobalShortcutEnabled)

            HStack(alignment: .top) {
                Text("Shortcut")
                    .frame(width: labelColumnWidth, alignment: .leading)

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
                .help("Reset the global shortcut to the default Control-Option-Command-Space.")
                .disabled(!isGlobalShortcutEnabled)
                .accessibilityIdentifier("settings.resetShortcut")
                .padding(.bottom, 18)
                .overlay(alignment: .bottomLeading) {
                    Text("Default: \(GlobalHotKey.defaultHotKey.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .allowsTightening(true)
                }

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
    }

    private var reminderDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminder Defaults")
                .font(.headline)

            HStack {
                Text("Title")
                    .frame(width: labelColumnWidth, alignment: .leading)

                TextField("Title", text: $defaultReminderTitle)
                    .frame(width: inputColumnWidth, alignment: .leading)
            }

            HStack {
                Text("Date")
                    .frame(width: labelColumnWidth, alignment: .leading)

                dateOffsetControl
            }

            HStack(alignment: .top) {
                Text("Time")
                    .frame(width: labelColumnWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Picker("Time", selection: $defaultTimeMode) {
                        ForEach(ReminderTimeDefaultMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: inputColumnWidth, alignment: .leading)

                    if selectedTimeMode == .customTime {
                        DatePicker(
                            "Custom time",
                            selection: customTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        .frame(width: inputColumnWidth, alignment: .leading)
                    }

                    Text("Current time uses the moment you open Quickie. Next whole hour rounds forward. Custom time always uses the saved clock time.")
                        .font(.callout)
                        .foregroundStyle(.secondary.opacity(0.9))
                        .frame(width: inputColumnWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Text("Urgent")
                    .frame(width: labelColumnWidth, alignment: .leading)

                Toggle("Urgent by default", isOn: $defaultUrgent)
                    .labelsHidden()
                    .frame(width: inputColumnWidth, alignment: .leading)
            }

            HStack {
                Text("Organisation / List")
                    .frame(width: labelColumnWidth, alignment: .leading)

                Picker("Organisation / List", selection: $defaultListName) {
                    ForEach(availableReminderListNames, id: \.self) { listName in
                        Text(listName).tag(listName)
                    }
                }
                .labelsHidden()
                .frame(width: inputColumnWidth, alignment: .leading)
                .disabled(availableReminderListNames.isEmpty)
            }

            HStack {
                Text("Tags")
                    .frame(width: labelColumnWidth, alignment: .leading)

                TextField("Tags", text: $defaultTagsText)
                    .frame(width: inputColumnWidth, alignment: .leading)
            }

            if let errorMessage = reminderDefaultsModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Reset Reminder Defaults") {
                let standard = ReminderDraftDefaults.standard
                defaultReminderTitle = standard.title
                defaultDateOffsetDays = standard.dateOffsetDays
                defaultTimeMode = standard.timeMode.rawValue
                defaultCustomHour = standard.customHour
                defaultCustomMinute = standard.customMinute
                defaultUrgent = standard.urgent
                defaultListName = standard.listName
                defaultTagsText = standard.tagsText
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            Text(AppMetadata.current.docsVersionString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
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

    private var dateOffsetControl: some View {
        HStack(spacing: 12) {
            Button {
                defaultDateOffsetDays -= 1
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(defaultDateOffsetDays > 0 ? .primary : .secondary)
            .disabled(defaultDateOffsetDays == 0)
            .accessibilityIdentifier("settings.defaultDate.decrement")

            VStack(alignment: .leading, spacing: 2) {
                Text(dateOffsetDescription)
                    .font(.body)

                Text(dateOffsetDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                defaultDateOffsetDays += 1
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(defaultDateOffsetDays < 30 ? .primary : .secondary)
            .disabled(defaultDateOffsetDays == 30)
            .accessibilityIdentifier("settings.defaultDate.increment")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: inputColumnWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var customTimeBinding: Binding<Date> {
        Binding {
            var calendar = Calendar.autoupdatingCurrent
            calendar.timeZone = .autoupdatingCurrent
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = 2001
            components.month = 1
            components.day = 1
            components.hour = defaultCustomHour
            components.minute = defaultCustomMinute
            return calendar.date(from: components) ?? Date()
        } set: { newDate in
            let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: newDate)
            defaultCustomHour = components.hour ?? ReminderDraftDefaults.standard.customHour
            defaultCustomMinute = components.minute ?? ReminderDraftDefaults.standard.customMinute
        }
    }

    private func refreshLaunchAtLoginState() {
        let state = LaunchAtLoginManager.shared.currentState()
        launchAtLoginStatusMessage = state.statusMessage
        launchAtLoginErrorMessage = state.errorMessage

        if launchesAtLogin != state.isEnabled {
            isSyncingLaunchAtLoginToggle = true
            launchesAtLogin = state.isEnabled
            isSyncingLaunchAtLoginToggle = false
        }
    }

    private func applyLaunchAtLoginPreference(_ isEnabled: Bool) {
        let state = LaunchAtLoginManager.shared.setEnabled(isEnabled)
        launchAtLoginStatusMessage = state.statusMessage
        launchAtLoginErrorMessage = state.errorMessage

        if launchesAtLogin != state.isEnabled {
            isSyncingLaunchAtLoginToggle = true
            launchesAtLogin = state.isEnabled
            isSyncingLaunchAtLoginToggle = false
        }
    }
}

@MainActor
private final class ReminderDefaultsSettingsViewModel: ObservableObject {
    @Published private(set) var lists: [ReminderList] = []
    @Published private(set) var errorMessage: String?

    private let reminderService: ReminderService

    init(reminderService: ReminderService = EventKitReminderService()) {
        self.reminderService = reminderService
    }

    func loadListsIfNeeded() async {
        guard lists.isEmpty else { return }

        do {
            try await reminderService.requestAccess()
            lists = try reminderService.fetchLists()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var hotKey: GlobalHotKey
    @Binding var validationMessage: String?

    func makeNSView(context _: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onRecord = { hotKey = $0 }
        button.onValidation = { validationMessage = $0 }
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context _: Context) {
        button.update(hotKey: hotKey)
    }
}

private func ignoreRecordedHotKey(_: GlobalHotKey) {
    // Default no-op until ShortcutRecorderView supplies the real callback.
}

private func ignoreValidationMessage(_: String?) {
    // Default no-op until ShortcutRecorderView supplies the real callback.
}

private final class ShortcutRecorderButton: NSButton {
    var hotKey = GlobalHotKey.defaultHotKey {
        didSet {
            guard oldValue != hotKey else { return }
            updateTitle()
        }
    }

    var onRecord: (GlobalHotKey) -> Void = ignoreRecordedHotKey
    var onValidation: (String?) -> Void = ignoreValidationMessage
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

    required init?(coder _: NSCoder) {
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

    func update(hotKey: GlobalHotKey) {
        guard self.hotKey != hotKey else { return }
        self.hotKey = hotKey
    }

    private func updateTitle() {
        let nextTitle = isRecording ? "Press shortcut..." : hotKey.displayName
        guard title != nextTitle else { return }
        title = nextTitle
    }
}
