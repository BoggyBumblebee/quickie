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
