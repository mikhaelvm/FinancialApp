import Foundation
import PDFKit
import Vision
import UIKit

/// On-device extraction only. PDF layouts are not a structured banking format:
/// every extracted movement must be reviewed before it can affect the balance.
enum PDFStatementReader {
    static func read(_ data: Data) throws -> StatementParseResult {
        guard data.count <= StatementParser.maximumBytes,
              let document = PDFDocument(data: data) else { throw FinanceError.invalid("Não foi possível abrir este PDF.") }
        guard !document.isLocked else { throw FinanceError.invalid("Este PDF está protegido por senha. Exporte uma cópia desbloqueada no banco.") }
        guard document.pageCount > 0, document.pageCount <= 50 else {
            throw FinanceError.invalid("Escolha um extrato PDF com até 50 páginas.")
        }
        var pages: [String] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let text = try autoreleasepool { () throws -> String in
                if let text = page.string, text.filter({ $0.isLetter || $0.isNumber }).count > 40 { return text }
                let bounds = page.bounds(for: .mediaBox)
                guard bounds.width > 0, bounds.height > 0 else { return "" }
                let ratio = min(2200 / bounds.width, 2200 / bounds.height)
                let image = page.thumbnail(of: CGSize(width: bounds.width * ratio, height: bounds.height * ratio), for: .mediaBox)
                guard let cgImage = image.cgImage else { return "" }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["pt-BR", "en-US"]
                request.usesLanguageCorrection = false
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                var lines: [[VNRecognizedTextObservation]] = []
                for observation in observations {
                    if let last = lines.last, let first = last.first,
                       abs(first.boundingBox.midY - observation.boundingBox.midY) < max(first.boundingBox.height, observation.boundingBox.height) * 0.5 {
                        lines[lines.count - 1].append(observation)
                    } else { lines.append([observation]) }
                }
                return lines.map { line in
                    line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                }.joined(separator: "\n")
            }
            pages.append(text)
        }
        return try parseText(pages.joined(separator: "\n"))
    }

    static func parseText(_ text: String) throws -> StatementParseResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.invalid("Não foi possível reconhecer o texto do PDF. Tente exportar OFX ou CSV no banco.")
        }
        guard text.range(of: #"(?i)\b(USD|EUR|GBP)\b|US\$|€|£"#, options: .regularExpression) == nil else {
            throw FinanceError.invalid("O Trackr importa apenas extratos em reais. Este PDF contém indicação de outra moeda.")
        }
        let normalizedDocument = StatementParser.normalize(text)
        if normalizedDocument.contains("totaldafatura") || normalizedDocument.contains("faturadocartao") {
            throw FinanceError.invalid("Este PDF parece uma fatura de cartão. Importe o extrato da conta para não duplicar compras e pagamentos de faturas.")
        }
        let yearExpression = try NSRegularExpression(pattern: #"\b(20\d{2}|19\d{2})\b"#)
        let years = Set(yearExpression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        })
        let implicitYear = years.count == 1 ? years.first : nil
        let dates = try NSRegularExpression(pattern: #"^\s*(\d{4}-\d{2}-\d{2}|\d{2}[/.]\d{2}(?:[/.](?:\d{4}|\d{2}))?)(?:\s+|$)"#)
        let amounts = try NSRegularExpression(pattern: #"(?:[-+−]\s*)?(?:R\$\s*)?\(?\d+(?:[.\s]\d{3})*[,\.]\d{2}\)?(?:\s*[DCdc]\b|[-+])?"#)
        var rows: [StatementRow] = [], warnings = ["PDF usa reconhecimento de texto e pode perder colunas ou sinais. Revise a data, a descrição, o valor e a natureza de cada movimento; todos começam desmarcados."]
        var ordinals: [String: Int] = [:]
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.replacingOccurrences(of: "−", with: "-")
            guard let match = dates.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let dateRange = Range(match.range(at: 1), in: line), let fullRange = Range(match.range, in: line) else { continue }
            var dateText = String(line[dateRange]).replacingOccurrences(of: ".", with: "/")
            if dateText.count == 5 {
                guard let implicitYear else { warnings.append("Linha \(index + 1): ano ausente ou ambíguo; movimento ignorado."); continue }
                dateText += "/" + implicitYear
            }
            guard let date = StatementParser.date(dateText) else { warnings.append("Linha \(index + 1): data não reconhecida."); continue }
            let body = String(line[fullRange.upperBound...])
            let normalized = StatementParser.normalize(body)
            if ["saldo", "total", "saldoinicial", "saldofinal", "saldoanterior"].contains(where: { normalized.hasPrefix($0) }) { continue }
            let matches = amounts.matches(in: body, range: NSRange(body.startIndex..., in: body))
            guard let amountMatch = matches.first, let amountRange = Range(amountMatch.range, in: body),
                  let cents = StatementParser.amount(String(body[amountRange])), cents != 0 else {
                warnings.append("Linha \(index + 1): valor não reconhecido. Confira no PDF original."); continue
            }
            let title = body[..<amountRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { warnings.append("Linha \(index + 1): descrição fora de ordem; movimento ignorado."); continue }
            let canonical = "\(StatementParser.dayKey(date))|\(cents)|\(StatementParser.normalize(title))"
            let ordinal = ordinals[canonical, default: 0]; ordinals[canonical] = ordinal + 1
            var row = StatementRow(id: StatementParser.fingerprint(source: "pdf", identifier: canonical + "|\(ordinal)"), date: date, title: title, signedCents: cents)
            row.requiresReview = true; row.selected = false
            rows.append(row)
            if matches.count > 1 { warnings.append("Linha \(index + 1): há vários valores. Foi sugerido o primeiro; confira se é o movimento e não o saldo.") }
        }
        guard !rows.isEmpty else {
            throw FinanceError.invalid("Não foi possível identificar movimentos com data completa, descrição e valor. Tente OFX/CSV; PDFs com colunas separadas ou layouts incompatíveis não podem ser importados com segurança.")
        }
        return StatementParseResult(rows: rows, warnings: warnings)
    }
}
