import Carbon
import EventKit
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

@MainActor
final class FailingReminderService: ReminderService {
    var accessError: Error?
    var fetchError: Error?
    var addError: Error?

    func requestAccess() async throws {
        if let accessError {
            throw accessError
        }
    }

    func fetchLists() throws -> [ReminderList] {
        if let fetchError {
            throw fetchError
        }

        return []
    }

    func addReminder(_ draft: ReminderDraft) throws {
        if let addError {
            throw addError
        }
    }
}

final class MockWorkspace: WorkspaceOpening {
    private(set) var openedURLs: [URL] = []

    @discardableResult
    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
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

    func testTrimmedTitleFallsBackToDefaultForWhitespaceOnlyTitle() {
        let draft = ReminderDraft(
            title: "   \n",
            date: Date(),
            time: Date(),
            urgent: false,
            listID: nil,
            tagsText: ""
        )

        XCTAssertEqual(draft.trimmedTitle, ReminderDraft.defaultTitle)
    }

    func testHashtagNotesReturnsJoinedTagsAndNilForEmptyTags() {
        let populatedDraft = ReminderDraft(
            title: "Test",
            date: Date(),
            time: Date(),
            urgent: false,
            listID: nil,
            tagsText: "Quickie Home"
        )
        let emptyDraft = ReminderDraft(
            title: "Test",
            date: Date(),
            time: Date(),
            urgent: false,
            listID: nil,
            tagsText: "   "
        )

        XCTAssertEqual(populatedDraft.hashtagNotes(), "#Quickie #Home")
        XCTAssertNil(emptyDraft.hashtagNotes())
    }
}

final class ReminderDraftDefaultsTests: XCTestCase {
    func testTimeModesExposeStableIdentifiersAndNames() {
        XCTAssertEqual(ReminderTimeDefaultMode.nextWholeHour.id, ReminderTimeDefaultMode.nextWholeHour.rawValue)
        XCTAssertEqual(ReminderTimeDefaultMode.nextWholeHour.displayName, "Next whole hour")
        XCTAssertEqual(ReminderTimeDefaultMode.currentTime.displayName, "Current time")
        XCTAssertEqual(ReminderTimeDefaultMode.customTime.displayName, "Custom time")
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

    func testLoadListsExposesPickerStateAfterSuccess() async {
        let service = MockReminderService()
        let viewModel = ReminderFormViewModel(reminderService: service)

        await viewModel.loadListsIfNeeded()

        XCTAssertTrue(viewModel.showsListPicker)
        XCTAssertNil(viewModel.listLoadingMessage)
        XCTAssertFalse(viewModel.canRetryListLoading)
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

    func testRefreshListsSurfacesServiceError() async {
        let service = FailingReminderService()
        service.accessError = ReminderServiceError.accessDenied
        let viewModel = ReminderFormViewModel(reminderService: service)

        await viewModel.refreshLists()

        XCTAssertFalse(viewModel.isBusy)
        XCTAssertTrue(viewModel.lists.isEmpty)
        XCTAssertFalse(viewModel.showsListPicker)
        XCTAssertEqual(viewModel.errorMessage, ReminderServiceError.accessDenied.localizedDescription)
        XCTAssertEqual(viewModel.listLoadingMessage, ReminderServiceError.accessDenied.localizedDescription)
        XCTAssertTrue(viewModel.canRetryListLoading)
        XCTAssertNil(viewModel.selectedListID)
    }

    func testAddReminderSurfacesServiceErrorAndDoesNotClose() async {
        let service = FailingReminderService()
        service.addError = ReminderServiceError.saveFailed("Boom")
        let viewModel = ReminderFormViewModel(reminderService: service)
        var didClose = false
        viewModel.onClose = { didClose = true }
        viewModel.selectedListID = "work"

        await viewModel.addReminder()

        XCTAssertEqual(viewModel.errorMessage, ReminderServiceError.saveFailed("Boom").localizedDescription)
        XCTAssertFalse(didClose)
        XCTAssertFalse(viewModel.isBusy)
    }

    func testCancelResetsDraftAndCloses() async {
        let service = MockReminderService()
        let viewModel = ReminderFormViewModel(reminderService: service)
        var didClose = false
        viewModel.onClose = { didClose = true }

        await viewModel.loadListsIfNeeded()
        viewModel.draft.title = "Changed"
        viewModel.selectedListID = "work"
        viewModel.cancel()

        XCTAssertEqual(viewModel.draft.title, ReminderDraft.defaultTitle)
        XCTAssertEqual(viewModel.selectedListID, "personal")
        XCTAssertTrue(didClose)
    }

    func testCanAddRequiresIdleStateAndSelectedList() async {
        let service = MockReminderService()
        let viewModel = ReminderFormViewModel(reminderService: service)

        XCTAssertFalse(viewModel.canAdd)

        await viewModel.loadListsIfNeeded()

        XCTAssertTrue(viewModel.canAdd)
    }
}

final class HelpURLResolverTests: XCTestCase {
    func testHomeURLDoesNotAddFragment() {
        let resolver = HelpURLResolver(resourceURL: { resource, extensionName, subdirectory in
            guard resource == "index", extensionName == "html", subdirectory == "Help" else { return nil }
            return URL(fileURLWithPath: "/tmp/Quickie/Help/index.html")
        })

        let url = resolver.url(for: .home)

        XCTAssertEqual(url?.path, "/tmp/Quickie/Help/index.html")
        XCTAssertNil(url?.fragment)
    }

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

@MainActor
final class HelpControllerTests: XCTestCase {
    func testOpenUsesWorkspaceWhenResolverReturnsURL() {
        let workspace = MockWorkspace()
        let controller = HelpController(
            resolver: HelpURLResolver(resourceURL: { _, _, _ in
                URL(fileURLWithPath: "/tmp/Quickie/Help/index.html")
            }),
            workspace: workspace
        )

        controller.open(.quickStart)

        XCTAssertEqual(workspace.openedURLs.first?.path, "/tmp/Quickie/Help/index.html")
    }

    func testOpenDoesNothingWhenResolverReturnsNil() {
        let workspace = MockWorkspace()
        let controller = HelpController(
            resolver: HelpURLResolver(resourceURL: { _, _, _ in nil }),
            workspace: workspace
        )

        controller.open(.home)

        XCTAssertTrue(workspace.openedURLs.isEmpty)
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

    func testShortcutFallbackUsesDefaultShortcut() {
        XCTAssertEqual(HotKeyShortcut.shortcut(rawValue: "nope"), .defaultShortcut)
    }

    func testShortcutDisplayNamesCoverEachPreset() {
        XCTAssertEqual(HotKeyShortcut.optionCommandSpace.displayName, "⌥⌘Space")
        XCTAssertEqual(HotKeyShortcut.optionCommandN.displayName, "⌥⌘N")
        XCTAssertEqual(HotKeyShortcut.shiftOptionCommandN.displayName, "⇧⌥⌘N")
        XCTAssertEqual(HotKeyShortcut.controlOptionCommandN.displayName, "⌃⌥⌘N")
    }

    func testRegistrationErrorMessageCoversParameterAndUnknownFailures() {
        XCTAssertTrue(HotKeyRegistrationError.message(for: OSStatus(paramErr)).contains("paramErr"))
        XCTAssertTrue(HotKeyRegistrationError.message(for: -9999).contains("Unknown Carbon hot key registration failure"))
    }

    func testGlobalHotKeyRejectsModifierOnlyAndMissingModifierEvents() {
        let modifierOnly = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Command)
        )
        let missingModifier = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "n",
            charactersIgnoringModifiers: "n",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_N)
        )

        XCTAssertNil(modifierOnly.flatMap { GlobalHotKey(event: $0) })
        XCTAssertNil(missingModifier.flatMap { GlobalHotKey(event: $0) })
    }

    func testGlobalHotKeyBuildsFromCommandOptionEvent() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "n",
            charactersIgnoringModifiers: "n",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_N)
        ))

        let hotKey = try XCTUnwrap(GlobalHotKey(event: event))

        XCTAssertEqual(hotKey, HotKeyShortcut.optionCommandN.hotKey)
    }
}

final class AppMetadataTests: XCTestCase {
    func testAppMetadataBuildsAboutAndDocsStrings() {
        let metadata = AppMetadata(infoDictionary: [
            "CFBundleDisplayName": "Quickie",
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "34"
        ])

        XCTAssertEqual(metadata.docsVersionString, "Quickie 1.2 (34)")
        XCTAssertEqual(metadata.aboutPanelVersionString, "1.2 (34)")
    }

    func testAppMetadataFallsBackToBundleNameAndDefaultVersions() {
        let metadata = AppMetadata(infoDictionary: [
            "CFBundleName": "QuickieFallback"
        ])

        XCTAssertEqual(metadata.docsVersionString, "QuickieFallback 1.0 (1)")
        XCTAssertEqual(metadata.aboutPanelVersionString, "1.0 (1)")
    }
}

final class ReminderServiceSupportTests: XCTestCase {
    func testReminderServiceErrorsExposeUserFacingDescriptions() {
        XCTAssertEqual(ReminderServiceError.accessDenied.errorDescription, "Quickie does not have permission to use Reminders. Enable Quickie in System Settings > Privacy & Security > Reminders.")
        XCTAssertEqual(ReminderServiceError.accessRestricted.errorDescription, "Reminders access is restricted on this Mac.")
        XCTAssertEqual(ReminderServiceError.remindersUnavailable("Offline").errorDescription, "Quickie could not connect to Reminders. Offline")
        XCTAssertEqual(ReminderServiceError.noWritableLists.errorDescription, "No writable Reminders lists were found.")
        XCTAssertEqual(ReminderServiceError.missingSelectedList.errorDescription, "The selected Reminders list is no longer available.")
        XCTAssertEqual(ReminderServiceError.saveFailed("Oops").errorDescription, "Quickie could not save the reminder. Oops")
    }

    func testAccessFailureMessageRecognizesSandboxRestrictionErrors() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 4099,
            userInfo: [NSDebugDescriptionErrorKey: "Connection init failed at lookup with error 159 - Sandbox restriction."]
        )

        let message = ReminderServiceMessageFormatter.accessFailureMessage(for: error)

        XCTAssertTrue(message.contains("sandbox access is blocked"))
    }

    func testAccessFailureMessageFallsBackToLocalizedDescription() {
        let error = NSError(domain: "Example", code: 7, userInfo: [NSLocalizedDescriptionKey: "Plain failure"])

        XCTAssertEqual(ReminderServiceMessageFormatter.accessFailureMessage(for: error), "Plain failure")
    }

    func testSaveFailureMessageMapsKnownEventKitErrors() {
        let notAuthorized = NSError(domain: EKErrorDomain, code: EKError.Code.eventStoreNotAuthorized.rawValue)
        let readOnly = NSError(domain: EKErrorDomain, code: EKError.Code.calendarReadOnly.rawValue)
        let unsupported = NSError(domain: EKErrorDomain, code: EKError.Code.calendarDoesNotAllowReminders.rawValue)
        let missingCalendar = NSError(domain: EKErrorDomain, code: EKError.Code.noCalendar.rawValue)
        let invalidPriority = NSError(domain: EKErrorDomain, code: EKError.Code.priorityIsInvalid.rawValue)
        let internalFailure = NSError(domain: EKErrorDomain, code: EKError.Code.internalFailure.rawValue)

        XCTAssertTrue(ReminderServiceMessageFormatter.saveFailureMessage(for: notAuthorized).contains("not authorized"))
        XCTAssertTrue(ReminderServiceMessageFormatter.saveFailureMessage(for: readOnly).contains("read-only"))
        XCTAssertTrue(ReminderServiceMessageFormatter.saveFailureMessage(for: unsupported).contains("cannot accept reminders"))
        XCTAssertTrue(ReminderServiceMessageFormatter.saveFailureMessage(for: missingCalendar).contains("no longer available"))
        XCTAssertTrue(ReminderServiceMessageFormatter.saveFailureMessage(for: invalidPriority).contains("priority"))
        XCTAssertTrue(ReminderServiceMessageFormatter.saveFailureMessage(for: internalFailure).contains("internal failure"))
    }

    func testSaveFailureMessageFallsBackToNSErrorDescriptionForUnknownErrors() {
        let error = NSError(domain: "Example", code: 8, userInfo: [NSLocalizedDescriptionKey: "Other failure"])

        XCTAssertEqual(ReminderServiceMessageFormatter.saveFailureMessage(for: error), "Other failure")
    }
}
