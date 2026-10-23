import Foundation

struct ReminderPreferences: Equatable {
    var enabled = false
    var daysBefore = 1
    var hour = 9
    var minute = 0
    var showAmounts = false

    static var current: ReminderPreferences {
        let defaults = UserDefaults.standard
        return ReminderPreferences(enabled: defaults.bool(forKey: "reminders.enabled"),
                                   daysBefore: defaults.object(forKey: "reminders.daysBefore") as? Int ?? 1,
                                   hour: defaults.object(forKey: "reminders.hour") as? Int ?? 9,
                                   minute: defaults.object(forKey: "reminders.minute") as? Int ?? 0,
                                   showAmounts: defaults.bool(forKey: "reminders.showAmounts"))
    }
}

struct PlannedReminder: Identifiable {
    let id: String
    let fireDate: Date
    let commitment: PaymentCommitment
    let daysBefore: Int
}

struct ReminderPlanner {
    // Stay below the system's local-notification queue limit and keep the nearest reminders.
    static let capacity = 60
    func reminders(for commitments: [PaymentCommitment], preferences: ReminderPreferences,
                   now: Date = .now) -> [PlannedReminder] {
        guard preferences.enabled else { return [] }
        var result: [PlannedReminder] = []
        for commitment in commitments {
            for lead in Set([0, max(0, min(7, preferences.daysBefore))]) {
                guard let day = FinanceDate.calendar.date(byAdding: .day, value: -lead, to: commitment.dueDate),
                      let fire = FinanceDate.calendar.date(bySettingHour: max(0, min(23, preferences.hour)),
                                                           minute: max(0, min(59, preferences.minute)), second: 0, of: day),
                      fire > now else { continue }
                result.append(PlannedReminder(id: "trackr.payment.\(commitment.id).\(lead)",
                                               fireDate: fire, commitment: commitment, daysBefore: lead))
            }
        }
        var seen = Set<String>()
        return Array(result.sorted {
            $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate
        }.filter { seen.insert($0.id).inserted }.prefix(Self.capacity))
    }
}
