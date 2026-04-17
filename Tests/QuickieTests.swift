import Carbon
import XCTest
@testable import Quickie

@MainActor
final class MockReminderService: ReminderService {
    var requestedAccess = false
    var addedDrafts: [ReminderDraft] = []
    var lists = [
        ReminderList(id: "personal", name: "Personal"),
        ReminderList(id: "work", name: "Work")
    ]

    func requestAccess() async throws {
        requestedAccess = true
    }

    func fetchLists() throws -> [ReminderList] {
        lists
    }

    func addReminder(_ draft: ReminderDraft) throws {
        addedDrafts.append(draft)
    }
}

final class ReminderDraftTests: XCTestCase {
    func testDefaultDraftUsesRequiredDefaults() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 16, hour: 10, minute: 37).date!

        let draft = ReminderDraft.defaultDraft(now: now, calendar: calendar)

        XCTAssertEqual(draft.title, "New Quickie")
        XCTAssertEqual(calendar.component(.day, from: draft.date), 16)
        XCTAssertEqual(calendar.component(.hour, from: draft.time), 11)
        XCTAssertEqual(calendar.component(.minute, from: draft.time), 0)
        XCTAssertFalse(draft.urgent)
        XCTAssertEqual(draft.tags, ["Quickie"])
    }

    func testDefaultDraftUsesSavedSettingsDefaults() {
        let defaults = UserDefaults(suiteName: "Quickie.ReminderDraftDefaultsTests")!
        defaults.removePersistentDomain(forName: "Quickie.ReminderDraftDefaultsTests")
        defaults.set("Inbox Zero", forKey: ReminderDefaultsSettings.titleKey)
        defaults.set(2, forKey: ReminderDefaultsSettings.dateOffsetDaysKey)
        defaults.set(ReminderTimeDefaultMode.customTime.rawValue, forKey: ReminderDefaultsSettings.timeModeKey)
        defaults.set(14, forKey: ReminderDefaultsSettings.customHourKey)
        defaults.set(45, forKey: ReminderDefaultsSettings.customMinuteKey)
        defaults.set(true, forKey: ReminderDefaultsSettings.urgentKey)
        defaults.set("Quickie Work", forKey: ReminderDefaultsSettings.tagsTextKey)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 16, hour: 10, minute: 37).date!

        let draft = ReminderDraft.defaultDraft(now: now, calendar: calendar, defaults: defaults)

        XCTAssertEqual(draft.title, "Inbox Zero")
        XCTAssertEqual(calendar.component(.day, from: draft.date), 18)
        XCTAssertEqual(calendar.component(.hour, from: draft.time), 14)
        XCTAssertEqual(calendar.component(.minute, from: draft.time), 45)
        XCTAssertTrue(draft.urgent)
        XCTAssertEqual(draft.tags, ["Quickie", "Work"])
    }

    func testDefaultDraftCanUseCurrentTimeMode() {
        let defaults = UserDefaults(suiteName: "Quickie.ReminderDraftCurrentTimeTests")!
        defaults.removePersistentDomain(forName: "Quickie.ReminderDraftCurrentTimeTests")
        defaults.set(ReminderTimeDefaultMode.currentTime.rawValue, forKey: ReminderDefaultsSettings.timeModeKey)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(calendar: calendar, year: 2026, month: 4, day: 16, hour: 10, minute: 37).date!

        let draft = ReminderDraft.defaultDraft(now: now, calendar: calendar, defaults: defaults)

        XCTAssertEqual(calendar.component(.hour, from: draft.time), 10)
        XCTAssertEqual(calendar.component(.minute, from: draft.time), 37)
    }

    func testDueDateComponentsCombineDateAndTimeFields() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = DateComponents(calendar: calendar, year: 2026, month: 4, day: 16, hour: 8).date!
        let time = DateComponents(calendar: calendar, year: 2026, month: 4, day: 18, hour: 14, minute: 30).date!
        let draft = ReminderDraft(title: "Pay invoice", date: date, time: time, urgent: true, listID: "work", tagsText: "Quickie Finance")

        let components = draft.dueDateComponents(calendar: calendar)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 16)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.calendar?.identifier, .gregorian)
    }

    func testTagParsingNormalizesWhitespaceHashesAndDuplicates() {
        XCTAssertEqual(ReminderDraft.parseTags(" Quickie, #Home quickie\nErrand "), ["Quickie", "Home", "Errand"])
    }
}

@MainActor
final class ReminderFormViewModelTests: XCTestCase {
    func testLoadListsSelectsRemindersListByDefault() async {
        let service = MockReminderService()
        service.lists = [
            ReminderList(id: "personal", name: "Personal"),
            ReminderList(id: "reminders", name: "Reminders"),
            ReminderList(id: "work", name: "Work")
        ]
        let viewModel = ReminderFormViewModel(reminderService: service)

        await viewModel.loadListsIfNeeded()

        XCTAssertTrue(service.requestedAccess)
        XCTAssertEqual(viewModel.lists.map(\.name), ["Personal", "Reminders", "Work"])
        XCTAssertEqual(viewModel.selectedListID, "reminders")
    }

    func testLoadListsFallsBackToFirstListWhenRemindersListIsMissing() async {
        let service = MockReminderService()
        let viewModel = ReminderFormViewModel(reminderService: service)

        await viewModel.loadListsIfNeeded()

        XCTAssertEqual(viewModel.selectedListID, "personal")
    }

    func testLoadListsUsesConfiguredDefaultListWhenAvailable() async {
        let service = MockReminderService()
        service.lists = [
            ReminderList(id: "personal", name: "Personal"),
            ReminderList(id: "work", name: "Work")
        ]
        let defaults = UserDefaults(suiteName: "Quickie.DefaultListPreferenceTests")!
        defaults.removePersistentDomain(forName: "Quickie.DefaultListPreferenceTests")
        defaults.set("Work", forKey: ReminderDefaultsSettings.listNameKey)
        let viewModel = ReminderFormViewModel(reminderService: service, defaults: defaults)

        await viewModel.loadListsIfNeeded()

        XCTAssertEqual(viewModel.selectedListID, "work")
    }

    func testResetFormSelectsRemindersListByDefault() async {
        let service = MockReminderService()
        service.lists = [
            ReminderList(id: "personal", name: "Personal"),
            ReminderList(id: "reminders", name: "Reminders"),
            ReminderList(id: "work", name: "Work")
        ]
        let viewModel = ReminderFormViewModel(reminderService: service)

        await viewModel.loadListsIfNeeded()
        viewModel.selectedListID = "work"
        viewModel.resetForm()

        XCTAssertEqual(viewModel.selectedListID, "reminders")
    }

    func testResetFormUsesConfiguredFieldDefaults() async {
        let service = MockReminderService()
        service.lists = [
            ReminderList(id: "personal", name: "Personal"),
            ReminderList(id: "work", name: "Work")
        ]
        let defaults = UserDefaults(suiteName: "Quickie.ResetDefaultsTests")!
        defaults.removePersistentDomain(forName: "Quickie.ResetDefaultsTests")
        defaults.set("Follow Up", forKey: ReminderDefaultsSettings.titleKey)
        defaults.set(true, forKey: ReminderDefaultsSettings.urgentKey)
        defaults.set("Quickie Waiting", forKey: ReminderDefaultsSettings.tagsTextKey)
        defaults.set("Work", forKey: ReminderDefaultsSettings.listNameKey)

        let viewModel = ReminderFormViewModel(reminderService: service, defaults: defaults)

        await viewModel.loadListsIfNeeded()
        viewModel.draft.title = "Temporary"
        viewModel.draft.urgent = false
        viewModel.draft.tagsText = "Scratch"
        viewModel.selectedListID = "personal"
        viewModel.resetForm()

        XCTAssertEqual(viewModel.draft.title, "Follow Up")
        XCTAssertTrue(viewModel.draft.urgent)
        XCTAssertEqual(viewModel.draft.tagsText, "Quickie Waiting")
        XCTAssertEqual(viewModel.selectedListID, "work")
    }

    func testAddUsesSelectedListAndCloses() async {
        let service = MockReminderService()
        let viewModel = ReminderFormViewModel(reminderService: service)
        var didClose = false
        viewModel.onClose = { didClose = true }

        await viewModel.loadListsIfNeeded()
        viewModel.selectedListID = "work"
        await viewModel.addReminder()

        XCTAssertEqual(service.addedDrafts.count, 1)
        XCTAssertEqual(service.addedDrafts.first?.listID, "work")
        XCTAssertTrue(didClose)
    }
}

final class HelpURLResolverTests: XCTestCase {
    func testHelpURLPrefersHelpDirectoryAndAddsAnchor() {
        let resolver = HelpURLResolver(resourceURL: { resource, extensionName, subdirectory in
            guard resource == "index", extensionName == "html", subdirectory == "Help" else { return nil }
            return URL(fileURLWithPath: "/tmp/Quickie/Help/index.html")
        })

        let url = resolver.url(for: .quickStart)

        XCTAssertEqual(url?.path, "/tmp/Quickie/Help/index.html")
        XCTAssertEqual(url?.fragment, "quick-start")
    }

    func testHelpURLFallsBackToRootIndex() {
        let resolver = HelpURLResolver(resourceURL: { resource, extensionName, subdirectory in
            guard resource == "index", extensionName == "html", subdirectory == nil else { return nil }
            return URL(fileURLWithPath: "/tmp/Quickie/index.html")
        })

        XCTAssertEqual(resolver.url(for: .troubleshooting)?.path, "/tmp/Quickie/index.html")
        XCTAssertEqual(resolver.url(for: .troubleshooting)?.fragment, "troubleshooting")
    }
}

final class HotKeyShortcutTests: XCTestCase {
    func testDefaultHotKeyIsControlOptionCommandSpace() {
        XCTAssertEqual(GlobalHotKey.defaultHotKey.displayName, "⌃⌥⌘Space")
        XCTAssertEqual(GlobalHotKey.defaultHotKey.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(GlobalHotKey.defaultHotKey.carbonModifiers, UInt32(cmdKey | optionKey | controlKey))
    }

    func testCustomHotKeyDisplayNameUsesStoredKeyCodeAndModifiers() {
        let hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: UInt32(cmdKey | shiftKey))

        XCTAssertEqual(hotKey.displayName, "⇧⌘N")
    }

    func testSettingsRegisterExpectedDefaults() {
        let defaults = UserDefaults(suiteName: "Quickie.HotKeyShortcutTests")!
        defaults.removePersistentDomain(forName: "Quickie.HotKeyShortcutTests")

        HotKeySettings.registerDefaults(defaults)

        XCTAssertTrue(HotKeySettings.isEnabled(defaults))
        XCTAssertEqual(HotKeySettings.selectedHotKey(defaults), .defaultHotKey)
        XCTAssertEqual(HotKeySettings.registrationStatus(defaults), noErr)
    }

    func testSettingsMigratesPreviousDefaultShortcut() {
        let defaults = UserDefaults(suiteName: "Quickie.HotKeyShortcutMigrationTests")!
        defaults.removePersistentDomain(forName: "Quickie.HotKeyShortcutMigrationTests")
        defaults.set(HotKeyShortcut.optionCommandSpace.rawValue, forKey: HotKeySettings.shortcutKey)

        HotKeySettings.registerDefaults(defaults)

        XCTAssertEqual(HotKeySettings.selectedHotKey(defaults), .defaultHotKey)
    }

    func testSettingsMigratesLegacyPresetEvenWhenOldDefaultMigrationAlreadyRan() {
        let defaults = UserDefaults(suiteName: "Quickie.HotKeyPresetMigrationTests")!
        defaults.removePersistentDomain(forName: "Quickie.HotKeyPresetMigrationTests")
        defaults.set(true, forKey: "GlobalHotKey.migratedDefaultToControlOptionCommandSpace")
        defaults.set(HotKeyShortcut.optionCommandN.rawValue, forKey: HotKeySettings.shortcutKey)

        HotKeySettings.registerDefaults(defaults)

        XCTAssertEqual(HotKeySettings.selectedHotKey(defaults), HotKeyShortcut.optionCommandN.hotKey)
    }

    func testRegistrationStatusIsOnlyPersistedWhenChanged() {
        let defaults = UserDefaults(suiteName: "Quickie.HotKeyRegistrationStatusTests")!
        defaults.removePersistentDomain(forName: "Quickie.HotKeyRegistrationStatusTests")
        HotKeySettings.registerDefaults(defaults)
        let registrationError = OSStatus(eventHotKeyExistsErr)

        HotKeySettings.setRegistrationStatus(registrationError, defaults: defaults)

        XCTAssertEqual(HotKeySettings.registrationStatus(defaults), registrationError)
    }

    func testRegistrationErrorMessageIncludesSymbolAndCode() {
        let message = HotKeyRegistrationError.message(for: OSStatus(eventHotKeyExistsErr))

        XCTAssertTrue(message.contains("eventHotKeyExistsErr"))
        XCTAssertTrue(message.contains("OSStatus \(eventHotKeyExistsErr)"))
    }
}
