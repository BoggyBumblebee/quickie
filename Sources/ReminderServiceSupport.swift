import EventKit
import Foundation

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

enum ReminderServiceMessageFormatter {
    static func accessFailureMessage(for error: Error) -> String {
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

    static func saveFailureMessage(for error: Error) -> String {
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
