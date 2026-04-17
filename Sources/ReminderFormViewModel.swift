import Foundation

@MainActor
final class ReminderFormViewModel: ObservableObject {
    @Published var draft: ReminderDraft
    @Published private(set) var lists: [ReminderList] = []
    @Published var selectedListID: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false

    var onClose: (() -> Void)?

    private let reminderService: ReminderService
    private let calendar: Calendar
    private let now: () -> Date

    init(
        reminderService: ReminderService,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.reminderService = reminderService
        self.calendar = calendar
        self.now = now
        self.draft = ReminderDraft.defaultDraft(now: now(), calendar: calendar)
    }

    var canAdd: Bool {
        !isBusy && !draft.trimmedTitle.isEmpty && selectedListID != nil
    }

    func loadListsIfNeeded() async {
        guard lists.isEmpty else { return }
        await refreshLists()
    }

    func refreshLists() async {
        isBusy = true
        errorMessage = nil

        do {
            try await reminderService.requestAccess()
            lists = try reminderService.fetchLists()
            if selectedListID == nil || !lists.contains(where: { $0.id == selectedListID }) {
                selectedListID = defaultListID()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isBusy = false
    }

    func addReminder() async {
        isBusy = true
        errorMessage = nil

        do {
            try await reminderService.requestAccess()
            var reminderDraft = draft
            reminderDraft.listID = selectedListID
            try reminderService.addReminder(reminderDraft)
            resetForm()
            onClose?()
        } catch {
            errorMessage = error.localizedDescription
        }

        isBusy = false
    }

    func cancel() {
        resetForm()
        onClose?()
    }

    func resetForm() {
        draft = ReminderDraft.defaultDraft(now: now(), calendar: calendar)
        selectedListID = defaultListID()
        errorMessage = nil
    }

    private func defaultListID() -> String? {
        lists.first { $0.name.localizedCaseInsensitiveCompare("Reminders") == .orderedSame }?.id
            ?? lists.first?.id
    }
}
