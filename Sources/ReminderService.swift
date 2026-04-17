import EventKit
import Foundation

@MainActor
protocol ReminderService {
    func requestAccess() async throws
    func fetchLists() throws -> [ReminderList]
    func addReminder(_ draft: ReminderDraft) throws
}

@MainActor
final class EventKitReminderService: ReminderService {
    private let store = EKEventStore()

    func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess:
            return
        case .writeOnly:
            throw ReminderServiceError.accessDenied
        case .authorized:
            return
        case .denied:
            throw ReminderServiceError.accessDenied
        case .restricted:
            throw ReminderServiceError.accessRestricted
        case .notDetermined:
            break
        @unknown default:
            break
        }

        let granted: Bool

        do {
            granted = try await requestRemindersAccess()
        } catch {
            throw ReminderServiceError.remindersUnavailable(ReminderServiceMessageFormatter.accessFailureMessage(for: error))
        }

        guard granted else {
            throw ReminderServiceError.accessDenied
        }
    }

    func fetchLists() throws -> [ReminderList] {
        let lists = store
            .calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .map { ReminderList(id: $0.calendarIdentifier, name: $0.title) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !lists.isEmpty else {
            throw ReminderServiceError.noWritableLists
        }

        return lists
    }

    func addReminder(_ draft: ReminderDraft) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.trimmedTitle
        reminder.calendar = try calendar(for: draft)
        reminder.dueDateComponents = draft.dueDateComponents()
        reminder.priority = draft.urgent ? 1 : 0
        reminder.notes = draft.hashtagNotes()

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw ReminderServiceError.saveFailed(ReminderServiceMessageFormatter.saveFailureMessage(for: error))
        }
    }

    private func calendar(for draft: ReminderDraft) throws -> EKCalendar {
        if let listID = draft.listID,
           let selectedCalendar = store.calendar(withIdentifier: listID),
           selectedCalendar.allowsContentModifications {
            return selectedCalendar
        }

        if draft.listID != nil {
            throw ReminderServiceError.missingSelectedList
        }

        if let defaultCalendar = store.defaultCalendarForNewReminders(),
           defaultCalendar.allowsContentModifications {
            return defaultCalendar
        }

        if let fallback = store.calendars(for: .reminder).first(where: \.allowsContentModifications) {
            return fallback
        }

        throw ReminderServiceError.noWritableLists
    }

    private func requestRemindersAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            if #available(macOS 14.0, *) {
                store.requestFullAccessToReminders { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            } else {
                store.requestAccess(to: .reminder) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
}
