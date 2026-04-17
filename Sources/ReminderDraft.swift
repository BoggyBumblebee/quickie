import Foundation

struct ReminderDraft: Equatable {
    static let defaultTitle = "New Quickie"
    static let defaultTag = "Quickie"

    var title: String
    var date: Date
    var time: Date
    var urgent: Bool
    var listID: String?
    var tagsText: String

    var trimmedTitle: String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? Self.defaultTitle : value
    }

    var tags: [String] {
        Self.parseTags(tagsText)
    }

    static func defaultDraft(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> ReminderDraft {
        ReminderDraft(
            title: defaultTitle,
            date: now,
            time: nextWholeHour(after: now, calendar: calendar),
            urgent: false,
            listID: nil,
            tagsText: defaultTag
        )
    }

    static func nextWholeHour(after date: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        let startOfCurrentHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: startOfCurrentHour) ?? date
    }

    static func parseTags(_ text: String) -> [String] {
        text
            .split { character in
                character == "," || character == " " || character == "\n" || character == "\t"
            }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { tags, tag in
                if !tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) {
                    tags.append(tag)
                }
            }
    }

    func dueDateComponents(calendar: Calendar = .autoupdatingCurrent) -> DateComponents {
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        var eventKitCalendar = Calendar(identifier: .gregorian)
        eventKitCalendar.timeZone = calendar.timeZone

        var components = DateComponents()
        components.calendar = eventKitCalendar
        components.timeZone = calendar.timeZone
        components.year = dateComponents.year
        components.month = dateComponents.month
        components.day = dateComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return components
    }

    func hashtagNotes() -> String? {
        let hashtags = tags.map { "#\($0)" }
        return hashtags.isEmpty ? nil : hashtags.joined(separator: " ")
    }
}
