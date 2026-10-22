import Foundation
import Observation
import SwiftData
import UserNotifications

@MainActor @Observable
final class NotificationService {
    static let shared = NotificationService()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount = 0
    private(set) var coveredUntil: Date?
    private(set) var lastError: String?
    private var work: Task<Void, Never>?
    private var pendingContext: ModelContext?
    private let center = UNUserNotificationCenter.current()
    private var resetRevision = 0

    func reset(context: ModelContext) {
        resetRevision += 1
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        scheduledCount = 0; coveredUntil = nil; lastError = nil
        refresh(context: context)
    }

    var canNotify: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }

    func requestPermission(context: ModelContext) async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(granted, forKey: "reminders.enabled")
            lastError = nil
        } catch {
            UserDefaults.standard.set(false, forKey: "reminders.enabled")
            lastError = error.localizedDescription
        }
        refresh(context: context)
    }

    /// Serialize reconciliation so a save during scheduling cannot leave stale requests behind.
    func refresh(context: ModelContext) {
        pendingContext = context
        guard work == nil else { return }
        work = Task {
            while let next = pendingContext {
                pendingContext = nil
                await reconcile(context: next)
            }
            work = nil
        }
    }

    private func reconcile(context: ModelContext) async {
        let revision = resetRevision
        authorization = await center.notificationSettings().authorizationStatus
        let preferences = ReminderPreferences.current
        let pending = await center.pendingNotificationRequests()
        guard revision == resetRevision else { return }
        let ownedIDs = pending.map(\.identifier).filter { $0.hasPrefix("ledger.payment.") }
        guard preferences.enabled && canNotify else {
            center.removePendingNotificationRequests(withIdentifiers: ownedIDs)
            scheduledCount = 0
            coveredUntil = nil
            return
        }
        do {
            let horizon = FinanceDate.calendar.date(byAdding: .day, value: 60, to: FinanceDate.day(.now))!
            let commitments = PaymentPlanner().commitments(cards: try context.fetch(FetchDescriptor<CreditCard>()),
                                                           subscriptions: try context.fetch(FetchDescriptor<Subscription>()),
                                                           scheduled: try context.fetch(FetchDescriptor<ScheduledPayment>()),
                                                           through: horizon)
            let reminders = ReminderPlanner().reminders(for: commitments, preferences: preferences)
            let desiredIDs = Set(reminders.map(\.id))
            center.removePendingNotificationRequests(withIdentifiers: ownedIDs.filter { !desiredIDs.contains($0) })
            let existing = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
            var completed = 0
            for reminder in reminders {
                guard revision == resetRevision else { return }
                let content = UNMutableNotificationContent()
                content.title = reminder.commitment.title
                let when = reminder.daysBefore == 0 ? "hoje" : (reminder.daysBefore == 1 ? "amanhã" : "em \(reminder.daysBefore) dias")
                let event = reminder.commitment.kind == .subscription ? "Renovação" : "Vencimento"
                let amount = preferences.showAmounts ? " • \(Money.format(reminder.commitment.amountCents))" : ""
                content.body = "\(event) \(when)\(amount). Abra o Ledger para conferir."
                content.sound = .default
                content.threadIdentifier = "ledger.payments"
                content.userInfo = ["kind": reminder.commitment.kind.rawValue,
                                    "sourceID": reminder.commitment.sourceID.uuidString]
                let components = FinanceDate.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let old = existing[reminder.id]
                let sameDate = (old?.trigger as? UNCalendarNotificationTrigger)?.dateComponents == components
                if old?.content.title != content.title || old?.content.body != content.body || !sameDate {
                    try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
                    if revision != resetRevision {
                        center.removePendingNotificationRequests(withIdentifiers: [reminder.id])
                        return
                    }
                }
                completed += 1
            }
            scheduledCount = completed
            coveredUntil = reminders.last?.fireDate
            lastError = nil
        } catch {
            guard revision == resetRevision else { return }
            lastError = "Não foi possível atualizar os lembretes: \(error.localizedDescription)"
        }
    }
}

final class LedgerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LedgerNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? "scheduled"
        let sourceID = info["sourceID"] as? String
        Task { @MainActor in
            LedgerRouter.shared.openReminder(kind: kind, cardID: sourceID)
            completionHandler()
        }
    }
}
