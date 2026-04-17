import EventKit
import Foundation

@MainActor
protocol ReminderService {
    func requestAccess() async throws
    func fetchLists() throws -> [ReminderList]
    func addReminder(_ draft: ReminderDraft) throws
}

enum ReminderServiceError: LocalizedError, Equatable {
    case accessDenied
    case accessRestricted
    case remindersUnavailable(String)
    case noWritableLists
    case missingSelectedList
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Quickie does not have permission to use Reminders. Enable Quickie in System Settings > Privacy & Security > Reminders."
        case .accessRestricted:
            "Reminders access is restricted on this Mac."
        case .remindersUnavailable(let message):
            "Quickie could not connect to Reminders. \(message)"
        case .noWritableLists:
            "No writable Reminders lists were found."
        case .missingSelectedList:
            "The selected Reminders list is no longer available."
        case .saveFailed(let message):
            "Quickie could not save the reminder. \(message)"
        }
    }
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
            throw ReminderServiceError.remindersUnavailable(Self.accessFailureMessage(for: error))
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
            throw ReminderServiceError.saveFailed(Self.saveFailureMessage(for: error))
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

    private static func accessFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        let debugDescription = nsError.userInfo[NSDebugDescriptionErrorKey] as? String ?? ""

        if nsError.code == 4099,
           (nsError.domain == NSMachErrorDomain
            || nsError.domain == NSCocoaErrorDomain
            || debugDescription.localizedCaseInsensitiveContains("Sandbox restriction")
            || debugDescription.localizedCaseInsensitiveContains("CalendarAgent")) {
            return "Quickie could not reach the macOS Reminders service because Calendar and Reminders sandbox access is blocked. Rebuild and relaunch Quickie, then allow access in System Settings > Privacy & Security > Reminders."
        }

        return error.localizedDescription
    }

    private static func saveFailureMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == EKErrorDomain,
              let code = EKError.Code(rawValue: nsError.code) else {
            return error.localizedDescription
        }

        switch code {
        case .eventStoreNotAuthorized:
            return "Reminders access is not authorized. Enable Quickie in System Settings > Privacy & Security > Reminders."
        case .calendarReadOnly:
            return "The selected Reminders list is read-only. Choose a writable list and try again."
        case .calendarDoesNotAllowReminders, .sourceDoesNotAllowReminders:
            return "The selected list cannot accept reminders."
        case .noCalendar:
            return "The selected list is no longer available. Reopen Quickie and choose another list."
        case .priorityIsInvalid:
            return "The reminder priority was rejected by Reminders."
        case .internalFailure:
            return "Reminders reported an internal failure. Try opening Reminders once, then try Quickie again."
        default:
            return nsError.localizedDescription
        }
    }
}
