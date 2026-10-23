import XCTest
@testable import Trackr

final class StatementFileAccessTests: XCTestCase {
    func testReviewUsesIndependentCopyWithOriginalName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("extrato.CSV")
        let data = Data("Data;Descricao;Valor\n22/10/2026;Teste;-10,00".utf8)
        try data.write(to: source)
        let copy = try StatementFileAccess.copyForReview(source)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        XCTAssertNotEqual(copy, source)
        XCTAssertEqual(copy.lastPathComponent, "extrato.CSV")
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: copy), data)
    }
    func testUnsupportedAndMissingFilesProduceErrors() {
        XCTAssertThrowsError(try StatementFileAccess.copyForReview(URL(fileURLWithPath: "/missing/image.jpg")))
        XCTAssertThrowsError(try StatementFileAccess.copyForReview(URL(fileURLWithPath: "/missing/extrato.pdf")))
    }
}
