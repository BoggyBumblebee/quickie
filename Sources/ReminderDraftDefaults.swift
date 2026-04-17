import Foundation

enum ReminderTimeDefaultMode: String, CaseIterable, Identifiable {
    case nextWholeHour
    case currentTime
    case customTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nextWholeHour:
            "Next whole hour"
        case .currentTime:
            "Current time"
        case .customTime:
            "Custom time"
        }
    }
}

struct ReminderDraftDefaults: Equatable {
    let title: String
    let dateOffsetDays: Int
    let timeMode: ReminderTimeDefaultMode
    let customHour: Int
    let customMinute: Int
    let urgent: Bool
    let listName: String
    let tagsText: String

    static let standard = ReminderDraftDefaults(
        title: ReminderDraft.defaultTitle,
        dateOffsetDays: 0,
        timeMode: .nextWholeHour,
        customHour: 9,
        customMinute: 0,
        urgent: false,
        listName: "Reminders",
        tagsText: ReminderDraft.defaultTag
    )

    func makeDraft(now: Date, calendar: Calendar) -> ReminderDraft {
        let startOfDay = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: .day, value: dateOffsetDays, to: startOfDay) ?? now

        let time: Date
        switch timeMode {
        case .nextWholeHour:
            time = ReminderDraft.nextWholeHour(after: now, calendar: calendar)
        case .currentTime:
            time = now
        case .customTime:
            let baseComponents = calendar.dateComponents([.year, .month, .day], from: now)
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = baseComponents.year
            components.month = baseComponents.month
            components.day = baseComponents.day
            components.hour = customHour
            components.minute = customMinute
            time = calendar.date(from: components) ?? now
        }

        return ReminderDraft(
            title: title,
            date: date,
            time: time,
            urgent: urgent,
            listID: nil,
            tagsText: tagsText
        )
    }
}

enum ReminderDefaultsSettings {
    static let titleKey = "ReminderDefaults.title"
    static let dateOffsetDaysKey = "ReminderDefaults.dateOffsetDays"
    static let timeModeKey = "ReminderDefaults.timeMode"
    static let customHourKey = "ReminderDefaults.customHour"
    static let customMinuteKey = "ReminderDefaults.customMinute"
    static let urgentKey = "ReminderDefaults.urgent"
    static let listNameKey = "ReminderDefaults.listName"
    static let tagsTextKey = "ReminderDefaults.tagsText"

    static func registerDefaults(_ defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            titleKey: ReminderDraftDefaults.standard.title,
            dateOffsetDaysKey: ReminderDraftDefaults.standard.dateOffsetDays,
            timeModeKey: ReminderDraftDefaults.standard.timeMode.rawValue,
            customHourKey: ReminderDraftDefaults.standard.customHour,
            customMinuteKey: ReminderDraftDefaults.standard.customMinute,
            urgentKey: ReminderDraftDefaults.standard.urgent,
            listNameKey: ReminderDraftDefaults.standard.listName,
            tagsTextKey: ReminderDraftDefaults.standard.tagsText
        ])
    }

    static func current(_ defaults: UserDefaults = .standard) -> ReminderDraftDefaults {
        registerDefaults(defaults)

        return ReminderDraftDefaults(
            title: defaults.string(forKey: titleKey) ?? ReminderDraftDefaults.standard.title,
            dateOffsetDays: defaults.integer(forKey: dateOffsetDaysKey),
            timeMode: ReminderTimeDefaultMode(rawValue: defaults.string(forKey: timeModeKey) ?? "") ?? .nextWholeHour,
            customHour: defaults.object(forKey: customHourKey) as? Int ?? ReminderDraftDefaults.standard.customHour,
            customMinute: defaults.object(forKey: customMinuteKey) as? Int ?? ReminderDraftDefaults.standard.customMinute,
            urgent: defaults.bool(forKey: urgentKey),
            listName: defaults.string(forKey: listNameKey) ?? ReminderDraftDefaults.standard.listName,
            tagsText: defaults.string(forKey: tagsTextKey) ?? ReminderDraftDefaults.standard.tagsText
        )
    }
}
