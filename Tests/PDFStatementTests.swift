import XCTest
import UIKit
@testable import FinancialApp

final class PDFStatementTests: XCTestCase {
    func testPDFTextSkipsBalanceAndRequiresIndividualReview() throws {
        let result = try PDFStatementReader.parseText("""
        Extrato em reais 2025
        01/01/2025 SALDO ANTERIOR 5.000,00
        02/01/2025 Pix recebido 1.200,00 C
        03/01/2025 Mercado -45,60 6.154,40
        04/01/2025 TOTAL 6.154,40
        """)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows.map(\.signedCents), [120000, -4560])
        XCTAssertTrue(result.rows.allSatisfy { $0.requiresReview && !$0.selected })
        XCTAssertTrue(result.warnings.contains { $0.contains("vários valores") })
    }

    func testImplicitYearIsAcceptedOnlyWhenUnambiguous() throws {
        let result = try PDFStatementReader.parseText("Extrato 2025\n02/01 Padaria 12,00 D")
        XCTAssertEqual(result.rows[0].signedCents, -1200)
        XCTAssertEqual(StatementParser.dayKey(result.rows[0].date), "2025-1-2")
        XCTAssertThrowsError(try PDFStatementReader.parseText("Período 2024 a 2025\n02/01 Padaria 12,00 D"))
    }

    func testUnsupportedOrForeignPDFIsRejectedInsteadOfInventingMovements() {
        XCTAssertThrowsError(try PDFStatementReader.parseText("Texto sem linhas de movimentos"))
        XCTAssertThrowsError(try PDFStatementReader.parseText("Extrato USD\n02/01/2025 Pix 10,00"))
        XCTAssertThrowsError(try PDFStatementReader.parseText("Total da fatura\n02/01/2025 Compra 10,00"))
        XCTAssertThrowsError(try PDFStatementReader.read(Data("Not a PDF".utf8)))
    }

    func testIdenticalLegitimateRowsGetDistinctButStableKeys() throws {
        let text = "02/01/2025 Café 10,00 D\n02/01/2025 Café 10,00 D"
        let first = try PDFStatementReader.parseText(text)
        XCTAssertEqual(Set(first.rows.map(\.importKey)).count, 2)
        XCTAssertEqual(first.rows.map(\.importKey), try PDFStatementReader.parseText(text).rows.map(\.importKey))
    }

    @MainActor func testReadsAnActualPDFWithSelectableText() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
        let data = renderer.pdfData { context in
            context.beginPage()
            let text = "Extrato em reais 2025\n02/01/2025 Pix recebido 100,00 C\n03/01/2025 Compra 20,00 D"
            (text as NSString).draw(in: CGRect(x: 20, y: 20, width: 550, height: 300), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
        let result = try PDFStatementReader.read(data)
        XCTAssertEqual(result.rows.map(\.signedCents), [10000, -2000])
    }
}
