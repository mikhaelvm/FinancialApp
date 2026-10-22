import Foundation

struct CashFlowMonth: Identifiable {
    let month: Date
    var income: Int64 = 0
    var expenses: Int64 = 0
    var id: Date { month }
    var net: Int64 { income - expenses }
}

struct SpendingComparison {
    let current: Int64
    let previous: Int64
    let day: Int
    var percentChange: Double? { previous > 0 ? Double(current - previous) / Double(previous) * 100 : nil }
}

enum FinancialReview {
    static func months(transactions: [Transaction], payments: [InvoicePayment], today: Date = .now, count: Int = 6) -> [CashFlowMonth] {
        guard count > 0 && count <= 24 else { return [] }
        let month = FinanceDate.month(today)
        let end = FinanceDate.calendar.date(byAdding: .day, value: 1, to: FinanceDate.day(today))!
        var values = (0..<count).map { CashFlowMonth(month: FinanceDate.monthOffset($0 - count + 1, from: month)) }
        let indices = Dictionary(uniqueKeysWithValues: values.enumerated().map { ($0.element.month, $0.offset) })
        for transaction in transactions where transaction.card == nil && transaction.date < end {
            guard let index = indices[FinanceDate.month(transaction.date)] else { continue }
            if transaction.kind == .income { values[index].income += transaction.amountCents }
            else { values[index].expenses += transaction.amountCents }
        }
        for payment in payments where payment.date < end {
            guard let index = indices[FinanceDate.month(payment.date)] else { continue }
            values[index].expenses += payment.amountCents
        }
        return values
    }

    /// Compare the same number of elapsed calendar days; card payments count once.
    static func comparison(transactions: [Transaction], payments: [InvoicePayment], today: Date = .now) -> SpendingComparison {
        let currentMonth = FinanceDate.month(today)
        let previousMonth = FinanceDate.monthOffset(-1, from: currentMonth)
        let day = FinanceDate.calendar.component(.day, from: today)
        let previousEndDay = FinanceDate.date(day: day, inMonth: previousMonth)
        let previousEnd = FinanceDate.calendar.date(byAdding: .day, value: 1, to: previousEndDay)!
        let currentEnd = FinanceDate.calendar.date(byAdding: .day, value: 1, to: FinanceDate.day(today))!
        func sum(start: Date, end: Date) -> Int64 {
            transactions.filter { $0.card == nil && $0.kind == .expense && $0.date >= start && $0.date < end }
                .reduce(0) { $0 + $1.amountCents }
                + payments.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amountCents }
        }
        return SpendingComparison(current: sum(start: currentMonth, end: currentEnd), previous: sum(start: previousMonth, end: previousEnd), day: day)
    }
}

enum LedgerTransactionPeriod: String, CaseIterable, Identifiable {
    case all = "Todo o período", month = "Este mês", previousMonth = "Mês anterior", thirtyDays = "Últimos 30 dias"
    var id: String { rawValue }
    func includes(_ date: Date, today: Date = .now) -> Bool {
        let start: Date
        let end: Date
        switch self {
        case .all: return true
        case .month:
            start = FinanceDate.month(today); end = FinanceDate.monthOffset(1, from: today)
        case .previousMonth:
            start = FinanceDate.monthOffset(-1, from: today); end = FinanceDate.month(today)
        case .thirtyDays:
            start = FinanceDate.calendar.date(byAdding: .day, value: -29, to: FinanceDate.day(today))!
            end = FinanceDate.calendar.date(byAdding: .day, value: 1, to: FinanceDate.day(today))!
        }
        return date >= start && date < end
    }
}

struct LedgerTransactionDraft: Identifiable {
    let id = UUID()
    let title: String
    let amountCents: Int64
    let kind: TransactionKind
    let categoryID: UUID?
    init(transaction: Transaction) {
        title = transaction.title; amountCents = transaction.amountCents; kind = transaction.kind; categoryID = transaction.category?.id
    }
}
