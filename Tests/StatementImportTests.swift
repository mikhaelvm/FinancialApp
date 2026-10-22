import XCTest
import SwiftData
@testable import FinancialApp
@testable import class FinancialApp.Category

final class StatementParserTests: XCTestCase {
    func testBrazilianAndInternationalNumbers() {
        XCTAssertEqual(StatementParser.amount("-1.234,56"), -123456)
        XCTAssertEqual(StatementParser.amount("R$ (100,25)"), -10025)
        XCTAssertEqual(StatementParser.amount("15,00 D"), -1500)
        XCTAssertEqual(StatementParser.amount("15,00 C"), 1500)
        XCTAssertEqual(StatementParser.amount("1,234.56"), 123456)
        XCTAssertEqual(StatementParser.amount("-123.45", decimalPoint: true), -12345)
        XCTAssertNil(StatementParser.amount("NaN"))
        XCTAssertNil(StatementParser.amount("99999999999999999999"))
    }

    func testCSVQuotesEscapesAndWindowsLineEndings() throws {
        let rows = try StatementParser.csvRows("Data;Descrição;Valor\r\n02/01/2025;\"Loja; \"\"Centro\"\"\";-10,50\r\n03/01/2025;\"Texto\ncom quebra\";20,00", separator: ";")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][1], "Loja; \"Centro\"")
        XCTAssertEqual(rows[2][1], "Texto\ncom quebra")
        XCTAssertThrowsError(try StatementParser.csvRows("Data;\"campo aberto", separator: ";"))
    }

    func testSixBankHeaderFamiliesAndSignedMovements() throws {
        // Representative layout fixtures; the column-mapping UI handles bank-export variations.
        let examples: [(StatementBank, String)] = [
            (.itau, "Data;Lançamento;Valor (R$);Saldo\n02/01/2025;Compra;-120,50;900,00"),
            (.caixa, "Data;Histórico;Valor;D/C\n02/01/2025;Compra;120,50;D"),
            (.bradesco, "Data;Histórico;Crédito (R$);Débito (R$)\n02/01/2025;Compra;;120,50"),
            (.bb, "Data;Lançamento;Valor;Tipo Lançamento\n02/01/2025;Compra;120,50;Débito"),
            (.mercadoPago, "RELEASE_DATE,DESCRIPTION,TRANSACTION_AMOUNT,SETTLEMENT_NET_AMOUNT\n2025-01-02,Compra,999.99,-120.50"),
            (.mercadoPago, "DATE;DESCRIPTION;TRANSACTION_AMOUNT;NET_CREDIT_AMOUNT;NET_DEBIT_AMOUNT\n2025-01-02;Compra;999,99;;120,50"),
            (.inter, "Data Lançamento;Descrição;Valor;Saldo\n02/01/2025;Compra;-120,50;900,00")
        ]
        for (bank, text) in examples {
            let document = try StatementParser.csvDocument(text)
            let result = try StatementParser.csv(document, mapping: document.mapping, bank: bank, account: "Principal")
            XCTAssertEqual(result.rows.count, 1, bank.rawValue)
            XCTAssertEqual(result.rows.first?.signedCents, -12050, bank.rawValue)
            XCTAssertTrue(result.warnings.isEmpty, bank.rawValue)
        }
    }

    func testOFXSGMLAndXMLUseStableFITIDAndDoNotImportBalance() throws {
        let sgml = "OFXHEADER:100\n<OFX><CURDEF>BRL<BANKID>341<ACCTID>123<BANKTRANLIST><STMTTRN><DTPOSTED>20250102120000[-3:BRT]<TRNAMT>-12.34<FITID>A1<MEMO>Loja &amp; Cia</STMTTRN><STMTTRN><DTPOSTED>20250103<TRNAMT>100.00<FITID>A2<NAME>Salário</STMTTRN></BANKTRANLIST><LEDGERBAL><BALAMT>5000.00</LEDGERBAL></OFX>"
        let a = try StatementParser.ofx(sgml, bank: .itau)
        let b = try StatementParser.ofx(sgml, bank: .other)
        XCTAssertEqual(a.rows.map(\.signedCents), [-1234, 10000])
        XCTAssertEqual(a.rows.first?.title, "Loja & Cia")
        XCTAssertEqual(a.rows.map(\.importKey), b.rows.map(\.importKey))
        let xml = "<OFX><CURDEF>BRL</CURDEF><BANKID>077</BANKID><ACCTID>123</ACCTID><BANKTRANLIST><STMTTRN><DTPOSTED>20250102</DTPOSTED><TRNAMT>12.34</TRNAMT><FITID>1</FITID><NAME>Receita</NAME></STMTTRN></BANKTRANLIST></OFX>"
        XCTAssertEqual(try StatementParser.ofx(xml, bank: .inter).rows.first?.signedCents, 1234)
    }

    func testInvalidRowsAreReportedAndForeignCurrenciesRejected() throws {
        let document = try StatementParser.csvDocument("Data;Descrição;Valor\n32/13/2025;Inválido;-1,00\n02/01/2025;Sem valor;abc\n02/01/2025;Saldo anterior;300,00")
        let result = try StatementParser.csv(document, mapping: document.mapping, bank: .bb, account: "")
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.warnings.count, 2)
        XCTAssertThrowsError(try StatementParser.ofx("<OFX><CURDEF>USD</CURDEF></OFX>", bank: .other))
        let foreign = try StatementParser.csvDocument("Data;Descrição;Valor;Currency\n02/01/2025;Compra;10.00;USD")
        XCTAssertThrowsError(try StatementParser.csv(foreign, mapping: foreign.mapping, bank: .other, account: ""))
    }

    func testCSVPreservesTwoIdenticalLegitimateRowsWithDifferentOccurrenceKeys() throws {
        let text = "Data;Descrição;Valor\n02/01/2025;Café;-10,00\n02/01/2025;Café;-10,00"
        let doc = try StatementParser.csvDocument(text)
        let a = try StatementParser.csv(doc, mapping: doc.mapping, bank: .itau, account: "Principal")
        let b = try StatementParser.csv(doc, mapping: doc.mapping, bank: .itau, account: "Principal")
        XCTAssertEqual(Set(a.rows.map(\.importKey)).count, 2)
        XCTAssertEqual(a.rows.map(\.importKey), b.rows.map(\.importKey))
    }

    func testUTF16AndUTF8BOMAreDecoded() throws {
        let text = "Data;Descrição;Valor\n02/01/2025;Café;10,00"
        XCTAssertEqual(try StatementParser.text(from: XCTUnwrap(text.data(using: .utf16))), text)
        XCTAssertEqual(try StatementParser.text(from: Data(("\u{feff}" + text).utf8)), text)
    }
}

@MainActor
final class StatementPersistenceTests: XCTestCase {
    func testRecordedInvoiceAndRecurringPaymentsAreFlaggedEvenWithDifferentBankDescriptions() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let today = FinanceDate.day(.now)
        let card = CreditCard(name: "Principal", limitCents: 100_000, closingDay: 20, dueDay: 25)
        context.insert(card)
        context.insert(InvoicePayment(card: card, invoiceDueDate: today, date: today, amountCents: 2000))
        context.insert(Transaction(title: "Assinatura", amountCents: 3000, kind: .expense, date: today, recurrenceKey: "renewal:0"))
        try context.save()
        let imported = [StatementRow(id: "statement:a", date: today, title: "PGTO CARTAO", signedCents: -2000),
                        StatementRow(id: "statement:b", date: today, title: "DEBITO AUTOMATICO", signedCents: -3000),
                        StatementRow(id: "statement:c", date: today, title: "Compra nova", signedCents: -500)]
        let preview = try StatementImportService.prepare(imported, context: context)
        XCTAssertEqual(preview.map(\.isDuplicate), [true, true, false])
        XCTAssertEqual(try StatementImportService.commit(preview, context: context), 1)
        var distinctMovement = preview[0]
        distinctMovement.importAsNew = true; distinctMovement.selected = true
        XCTAssertEqual(try StatementImportService.commit([distinctMovement], context: context), 1)
    }

    func testConfirmedImportIsAtomicIdempotentAndEditable() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let doc = try StatementParser.csvDocument("Data;Descrição;Valor\n02/01/2025;Salário;1000,00\n03/01/2025;Compra;-100,00")
        let parsed = try StatementParser.csv(doc, mapping: doc.mapping, bank: .inter, account: "Principal")
        let rows = try StatementImportService.prepare(parsed.rows, context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try StatementImportService.commit(rows, context: context), 2)
        XCTAssertEqual(try StatementImportService.commit(rows, context: context), 0)
        XCTAssertTrue(try StatementImportService.prepare(parsed.rows, context: context).allSatisfy { $0.isDuplicate && !$0.selected })
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let balance = DashboardViewModel().snapshot(transactions: transactions, cards: [], subscriptions: [], payments: [], month: .now).balance
        XCTAssertEqual(balance, 90000)
        let expense = try XCTUnwrap(transactions.first { $0.kind == .expense })
        try TransactionViewModel().saveCash(context: context, transaction: expense, title: "Compra revisada", amountText: "100,00", kind: .expense, date: expense.date, category: nil)
        XCTAssertEqual(expense.title, "Compra revisada")
    }

    func testManualDuplicateAndFutureRowsAreNotSelectedByDefault() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let today = FinanceDate.day(.now)
        context.insert(Transaction(title: "Compra", amountCents: 100, kind: .expense, date: today))
        try context.save()
        let rows = [StatementRow(id: "statement:a", date: today, title: "Compra", signedCents: -100),
                    StatementRow(id: "statement:b", date: FinanceDate.calendar.date(byAdding: .day, value: 1, to: today)!, title: "Futuro", signedCents: 500)]
        let preview = try StatementImportService.prepare(rows, context: context)
        XCTAssertTrue(preview[0].isDuplicate)
        XCTAssertFalse(preview[0].selected)
        XCTAssertFalse(preview[1].selected)
        XCTAssertEqual(try StatementImportService.commit(preview, context: context), 0)
    }
}
