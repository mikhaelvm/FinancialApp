import Foundation

enum FinanceError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum Money {
    static let maximumCents: Int64 = 1_000_000_000_000
    /// Bank-style entry: each typed digit shifts the amount by one cent.
    static func bankInput(_ proposed: String, previous: String = "") -> String {
        let digits = proposed.filter { $0 >= "0" && $0 <= "9" }
        guard !digits.isEmpty else { return "" }
        let significant = String(digits.drop(while: { $0 == "0" }))
        guard !significant.isEmpty else { return "" }
        guard significant.count <= 13, let cents = Int64(significant), cents <= maximumCents else { return previous }
        let integer = (cents / 100).formatted(.number.locale(Locale(identifier: "pt_BR")))
        return integer + "," + String(format: "%02lld", cents % 100)
    }
    static func parse(_ text: String) -> Int64? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
        // Brazilian notation, with decimal-point keyboards also accepted. A point
        // with one or two trailing digits is decimal, not a thousands separator.
        let normalized: String
        if cleaned.contains(",") {
            normalized = cleaned.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            let groups = cleaned.components(separatedBy: ".")
            if groups.count == 2 && (1...2).contains(groups[1].count) { normalized = cleaned }
            else if groups.count > 1 {
                guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
                normalized = groups.joined()
            } else { normalized = cleaned }
        }
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
    /// Weekend-only business calendar; public holidays are not included.
    static func nextWeekday(_ date: Date) -> Date {
        let start = day(date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = weekday == 7 ? 2 : (weekday == 1 ? 1 : 0)
        return calendar.date(byAdding: .day, value: offset, to: start)!
    }
    static func sameMonth(_ a: Date, _ b: Date) -> Bool { month(a) == month(b) }
    static func monthTitle(_ date: Date) -> String {
        capitalizedMonth(date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR"))))
    }
    static func shortMonthTitle(_ date: Date) -> String {
        capitalizedMonth(date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "pt_BR"))))
    }
    private static func capitalizedMonth(_ text: String) -> String {
        String(text.prefix(1)).uppercased(with: Locale(identifier: "pt_BR")) + String(text.dropFirst())
    }
}
