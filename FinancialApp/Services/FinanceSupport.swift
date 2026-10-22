import Foundation

enum FinanceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum Money {
    static let maximumCents: Int64 = 1_000_000_000_000
    static func parse(_ text: String) -> Int64? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
        // Entry uses Brazilian notation: 1.234,56 (or an integer).
        let normalized = cleaned.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0, decimal <= Decimal(maximumCents) / 100 else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).int64Value
    }
    static func format(_ cents: Int64) -> String {
        (Double(cents) / 100).formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR")))
    }
    static func input(_ cents: Int64) -> String {
        String(format: "%.2f", Double(cents) / 100).replacingOccurrences(of: ".", with: ",")
    }
}

enum FinanceDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
    static func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    static func month(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }
    static func monthOffset(_ offset: Int, from date: Date) -> Date {
        calendar.date(byAdding: .month, value: offset, to: month(date))!
    }
    static func date(day: Int, inMonth month: Date) -> Date {
        let start = self.month(month)
        let lastDay = calendar.range(of: .day, in: .month, for: start)!.count
        return calendar.date(byAdding: .day, value: min(max(day, 1), lastDay) - 1, to: start)!
    }
    static func sameMonth(_ a: Date, _ b: Date) -> Bool { month(a) == month(b) }
    static func monthTitle(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR")))
    }
}
