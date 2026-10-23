import Foundation
import SwiftData

struct RecurrenceOccurrence {
    let date: Date
    let index: Int
    let key: String
}

struct RecurrenceEngine {
    func date(for subscription: Subscription, index: Int) -> Date {
        let anchor = FinanceDate.day(subscription.anchorDate)
        switch subscription.cycle {
        case .weekly:
            return FinanceDate.calendar.date(byAdding: .day, value: index * 7, to: anchor)!
        case .monthly, .yearly:
            let offset = index * (subscription.cycle == .yearly ? 12 : 1)
            let day = FinanceDate.calendar.component(.day, from: anchor)
            return FinanceDate.date(day: day, inMonth: FinanceDate.monthOffset(offset, from: anchor))
        }
    }

    func occurrences(of subscription: Subscription, through end: Date) -> [RecurrenceOccurrence] {
        guard subscription.isActive else { return [] }
        var index = subscription.nextOccurrenceIndex
        var result: [RecurrenceOccurrence] = []
        while true {
            let occurrenceDate = date(for: subscription, index: index)
            guard occurrenceDate <= FinanceDate.day(end) else { break }
            result.append(RecurrenceOccurrence(date: occurrenceDate, index: index,
                                              key: "\(subscription.scheduleID.uuidString):\(index)"))
            index += 1
        }
        return result
    }

    @MainActor
    func synchronize(context: ModelContext, today: Date = .now) throws {
        let descriptor = FetchDescriptor<Subscription>(predicate: #Predicate { $0.isActive })
        let subscriptions = try context.fetch(descriptor)
        let existing = try context.fetch(FetchDescriptor<Transaction>())
        var keys = Set(existing.compactMap(\.recurrenceKey))
        for subscription in subscriptions {
            for occurrence in occurrences(of: subscription, through: today) {
                if keys.insert(occurrence.key).inserted {
                    let card = subscription.card
                    let dates = card.map {
                        InvoiceEngine().dates(for: occurrence.date, closingDay: $0.closingDay, dueDay: $0.dueDay)
                    }
                    let transaction = Transaction(title: subscription.title, amountCents: subscription.amountCents,
                                                  kind: .expense, date: occurrence.date,
                                                  category: subscription.category, card: card,
                                                  invoiceDueDate: dates?.due, invoiceClosingDate: dates?.closing,
                                                  subscription: subscription, recurrenceKey: occurrence.key)
                    context.insert(transaction)
                }
                subscription.nextOccurrenceIndex = occurrence.index + 1
                subscription.nextRenewalDate = date(for: subscription, index: occurrence.index + 1)
            }
        }
        do { try context.save(); FinanceEvents.saved() } catch { context.rollback(); throw error }
    }
}
