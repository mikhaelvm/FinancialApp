import XCTest
@testable import FinancialApp

final class InvoiceEngineTests: XCTestCase {
    private let engine = InvoiceEngine()
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        FinanceDate.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testPurchaseBeforeClosingHasNextMonthDueDate() {
        let result = engine.dates(for: date(2026, 1, 24), closingDay: 25, dueDay: 5)
        XCTAssertEqual(result.closing, date(2026, 1, 26))
        XCTAssertEqual(result.due, date(2026, 2, 5))
    }

    func testPurchaseOnClosingDayMovesToFollowingCycle() {
        for day in [26, 27] {
            let result = engine.dates(for: date(2026, 1, day), closingDay: 25, dueDay: 5)
            XCTAssertEqual(result.closing, date(2026, 2, 25))
            XCTAssertEqual(result.due, date(2026, 3, 5))
        }
    }

    func testDueDateAfterClosingCanUseSameMonth() {
        XCTAssertEqual(engine.dates(for: date(2026, 1, 9), closingDay: 10, dueDay: 20).due, date(2026, 1, 20))
    }

    func testYearBoundary() {
        XCTAssertEqual(engine.dates(for: date(2026, 12, 26), closingDay: 25, dueDay: 5).due, date(2027, 2, 5))
    }

    func testShortMonthsClampAndRecoverOriginalDay() {
        let purchase = date(2026, 1, 1)
        XCTAssertEqual(engine.dates(for: purchase, closingDay: 31, dueDay: 5, installmentOffset: 1).closing, date(2026, 3, 2))
        XCTAssertEqual(engine.dates(for: purchase, closingDay: 31, dueDay: 5, installmentOffset: 2).closing, date(2026, 3, 31))
        XCTAssertEqual(engine.dates(for: date(2028, 2, 1), closingDay: 31, dueDay: 5).closing, date(2028, 2, 29))
    }

    func testWeekendClosingUsesMondayAsThePurchaseBoundary() {
        let sunday = engine.dates(for: date(2026, 1, 25), closingDay: 25, dueDay: 5)
        XCTAssertEqual(sunday.closing, date(2026, 1, 26))
        XCTAssertEqual(sunday.due, date(2026, 2, 5))
        let monday = engine.dates(for: date(2026, 1, 26), closingDay: 25, dueDay: 5)
        XCTAssertEqual(monday.closing, date(2026, 2, 25))
    }

    func testWeekendDueDateAndClosingCrossingMonthBoundary() {
        XCTAssertEqual(engine.dates(for: date(2026, 1, 1), closingDay: 10, dueDay: 25).due, date(2026, 1, 26))
        let result = engine.dates(for: date(2026, 3, 1), closingDay: 31, dueDay: 5)
        XCTAssertEqual(result.closing, date(2026, 3, 2))
        XCTAssertEqual(result.due, date(2026, 3, 5))
        XCTAssertEqual(FinanceDate.nextWeekday(date(2026, 2, 28)), date(2026, 3, 2))
    }

    func testTwelveHundredInTenInstallments() throws {
        XCTAssertEqual(try engine.installmentAmounts(totalCents: 120_000, count: 10), Array(repeating: Int64(12_000), count: 10))
    }

    func testRemainderNeverCreatesOrLosesCentavos() throws {
        let amounts = try engine.installmentAmounts(totalCents: 10_000, count: 3)
        XCTAssertEqual(amounts, [3334, 3333, 3333])
        XCTAssertEqual(amounts.reduce(0, +), 10_000)
        XCTAssertThrowsError(try engine.installmentAmounts(totalCents: 2, count: 3))
        XCTAssertThrowsError(try engine.installmentAmounts(totalCents: 100, count: 0))
        XCTAssertThrowsError(try engine.installmentAmounts(totalCents: 1000, count: 121))
    }

    func testBrazilianMoneyInput() {
        XCTAssertEqual(Money.parse("R$ 1.234,56"), 123456)
        XCTAssertEqual(Money.parse("1200"), 120000)
        XCTAssertEqual(Money.parse("0,01"), 1)
        XCTAssertEqual(Money.parse("12.34"), 1234)
        XCTAssertEqual(Money.parse("1200.00"), 120000)
        XCTAssertEqual(Money.parse("1.234"), 123400)
        XCTAssertNil(Money.parse("12.34.56"))
        XCTAssertNil(Money.parse("-20,00"))
        XCTAssertNil(Money.parse("1,234"))
        XCTAssertNil(Money.parse("NaN"))
        XCTAssertNil(Money.parse("99999999999999999999999"))
    }
}
