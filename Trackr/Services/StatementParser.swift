import Foundation
import CryptoKit

enum StatementBank: String, CaseIterable, Identifiable, Sendable {
    case itau = "Itaú", caixa = "Caixa", bradesco = "Bradesco", bb = "Banco do Brasil"
    case mercadoPago = "Mercado Pago", inter = "Inter", other = "Outro banco"
    var id: String { rawValue }
}

struct StatementRow: Identifiable, Sendable {
    let id: String
    let importKey: String
    var date: Date
    var title: String
    var signedCents: Int64
    var categoryID: UUID?
    var selected = true
    var isDuplicate = false
    var importAsNew = false
    var requiresReview = false
    var kind: TransactionKind { signedCents < 0 ? .expense : .income }
    init(id importKey: String, date: Date, title: String, signedCents: Int64) {
        self.id = UUID().uuidString
        self.importKey = importKey
        self.date = date; self.title = title; self.signedCents = signedCents
    }
}

struct StatementColumnMapping: Equatable, Sendable {
    var date = -1
    var title = -1
    var amount = -1
    var debit = -1
    var credit = -1
    var direction = -1
    var identifier = -1
}

struct StatementCSV: Sendable {
    let headers: [String]
    let rows: [[String]]
    let mapping: StatementColumnMapping
}

struct StatementParseResult: Sendable {
    var rows: [StatementRow]
    var warnings: [String]
}

enum StatementParser {
    static let maximumBytes = 15_000_000

    static func text(from data: Data) throws -> String {
        guard data.count <= maximumBytes else { throw FinanceError.invalid("O extrato deve ter até 15 MB.") }
        let utf16 = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) ? String(data: data, encoding: .utf16) : nil
        guard let text = utf16 ?? String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(data: data, encoding: .isoLatin1) else {
            throw FinanceError.invalid("Não foi possível ler o texto do extrato.")
        }
        return text.replacingOccurrences(of: "\u{feff}", with: "")
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .filter { $0.isLetter || $0.isNumber }
    }

    static func fingerprint(source: String, identifier: String) -> String {
        let bytes = SHA256.hash(data: Data("\(source)|\(identifier)".utf8))
        return "statement:" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func dayKey(_ date: Date) -> String {
        let parts = FinanceDate.calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private static func dateFormatters() -> [DateFormatter] {
        ["dd/MM/yyyy", "yyyy-MM-dd", "dd/MM/yy", "dd-MM-yyyy", "yyyyMMdd", "dd.MM.yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.calendar = FinanceDate.calendar; formatter.timeZone = .current
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = format; formatter.isLenient = false
            return formatter
        }
    }

    static func date(_ text: String, using formatters: [DateFormatter]? = nil) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in formatters ?? dateFormatters() {
            let format = formatter.dateFormat ?? ""
            let length = format == "dd/MM/yy" || format == "yyyyMMdd" ? 8 : 10
            if let date = formatter.date(from: String(cleaned.prefix(length))),
               (1900...2200).contains(FinanceDate.calendar.component(.year, from: date)) { return FinanceDate.day(date) }
        }
        return nil
    }

    static func amount(_ text: String, decimalPoint: Bool = false) -> Int64? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let negative = text.hasPrefix("-") || text.hasSuffix("-") || (text.contains("(") && text.contains(")")) || text.hasSuffix("D")
        text = text.replacingOccurrences(of: "R$", with: "").replacingOccurrences(of: "\u{a0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        if text.hasSuffix("D") || text.hasSuffix("C") { text.removeLast() }
        text = text.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        if text.hasPrefix("-") || text.hasPrefix("+") { text.removeFirst() }
        if text.hasSuffix("-") || text.hasSuffix("+") { text.removeLast() }
        if !decimalPoint {
            if let comma = text.lastIndex(of: ","), let point = text.lastIndex(of: "."), point > comma {
                text = text.replacingOccurrences(of: ",", with: "")
            } else if text.contains(",") { text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else if let point = text.lastIndex(of: "."), text.distance(from: point, to: text.endIndex) == 4 {
                text = text.replacingOccurrences(of: ".", with: "")
            }
        }
        guard text.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              value <= Decimal(Money.maximumCents) / 100 else { return nil }
        let cents = NSDecimalNumber(decimal: value * 100).int64Value
        return negative ? -cents : cents
    }

    private static func tag(_ name: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: "<\(name)\\s*>\\s*([^<\\r\\n]*)", options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
    }

    static func ofx(_ text: String, bank: StatementBank) throws -> StatementParseResult {
        if text.localizedCaseInsensitiveContains("<CCSTMTRS>") {
            throw FinanceError.invalid("Este arquivo é uma fatura de cartão. Importe o extrato da conta para registrar entradas e saídas sem duplicar suas faturas.")
        }
        if let currency = tag("CURDEF", in: text), currency.uppercased() != "BRL" {
            throw FinanceError.invalid("Este extrato usa \(currency). O Trackr trabalha em reais.")
        }
        let accountExpression = try NSRegularExpression(pattern: "<BANKACCTFROM\\s*>", options: [.caseInsensitive])
        let accountTags = accountExpression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        guard accountTags <= 1 else { throw FinanceError.invalid("Exporte um arquivo para cada conta bancária.") }
        let source = "ofx:\(tag("BANKID", in: text) ?? bank.rawValue):\(tag("ACCTID", in: text) ?? "conta")"
        let expression = try NSRegularExpression(pattern: "<STMTTRN\\s*>([\\s\\S]*?)(?:</STMTTRN\\s*>|(?=<STMTTRN\\s*>|</BANKTRANLIST>))", options: [.caseInsensitive])
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { throw FinanceError.invalid("Não encontramos lançamentos OFX. Escolha um extrato OFX ou CSV da conta.") }
        var result: [StatementRow] = [], warnings: [String] = [], occurrences: [String: Int] = [:]
        let formatters = dateFormatters()
        for (index, match) in matches.enumerated() {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let block = String(text[range])
            guard let rawDate = tag("DTPOSTED", in: block), let date = date(String(rawDate.prefix(8)), using: formatters),
                  let rawAmount = tag("TRNAMT", in: block), let cents = amount(rawAmount, decimalPoint: true), cents != 0 else {
                warnings.append("Lançamento OFX \(index + 1): data ou valor inválido."); continue
            }
            let memo = tag("MEMO", in: block) ?? "", name = tag("NAME", in: block) ?? ""
            let title = !memo.isEmpty ? memo : (!name.isEmpty ? name : "Movimentação bancária")
            let fallback = "\(dayKey(date))|\(cents)|\(normalize(title))"
            let ordinal = occurrences[fallback, default: 0]; occurrences[fallback] = ordinal + 1
            let identifier = tag("FITID", in: block).flatMap { $0.isEmpty ? nil : $0 } ?? "\(fallback)|\(ordinal)"
            result.append(StatementRow(id: fingerprint(source: source, identifier: identifier), date: date, title: title, signedCents: cents))
        }
        return StatementParseResult(rows: result, warnings: warnings)
    }

    /// RFC 4180-style fields, including escaped quotes and line breaks inside quoted cells.
    static func csvRows(_ text: String, separator: Character) throws -> [[String]] {
        let characters = Array(text)
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if quoted && index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 }
                else if quoted || field.isEmpty { quoted.toggle() }
                else { field.append(character) }
            } else if character == separator && !quoted { row.append(field); field = "" }
            else if (character == "\n" || character == "\r" || character == "\r\n") && !quoted {
                row.append(field); field = ""
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
                if character == "\r" && index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
            } else { field.append(character) }
            index += 1
            guard rows.count <= 50_000 else { throw FinanceError.invalid("Importe extratos de até 50 mil linhas por vez.") }
        }
        guard !quoted else { throw FinanceError.invalid("Há aspas não fechadas no CSV. Exporte novamente o arquivo pelo banco.") }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    static func suggestMapping(headers: [String]) -> StatementColumnMapping {
        let normalized = headers.map(normalize)
        func find(_ aliases: [String]) -> Int { aliases.compactMap { normalized.firstIndex(of: $0) }.first ?? -1 }
        var mapping = StatementColumnMapping(
            date: find(["data", "datamovimento", "datalancamento", "datadomovimento", "datadolancamento", "date", "releasedate", "settlementdate", "transactiondate", "datalancto", "datatransacao", "datacontabil", "dtmov"]),
            title: find(["descricao", "historico", "lancamento", "description", "transactiontype", "detalhes", "estabelecimento", "nomedestinatario"]),
            amount: find(["settlementnetamount", "transactionnetamount", "netamount", "valor", "valorr", "valorrs", "valordolancamento", "amount", "transactionamount", "valorbrl"]),
            debit: find(["netdebitamount", "debito", "debitos", "debitor", "debitors", "valordebito"]),
            credit: find(["netcreditamount", "credito", "creditos", "creditor", "creditors", "valorcredito"]),
            direction: find(["tipo", "dc", "cd", "natureza", "tipomovimento", "tipotransacao", "tipolancamento"]),
            identifier: find(["id", "identificador", "referenceid", "transactionid", "documento", "numerodocumento"]))
        let hasNet = normalized.contains("settlementnetamount") || normalized.contains("transactionnetamount") || normalized.contains("netamount")
        if !hasNet && normalized.contains("netdebitamount") && normalized.contains("netcreditamount") { mapping.amount = -1 }
        return mapping
    }

    static func csvDocument(_ text: String) throws -> StatementCSV {
        var best: (score: Int, index: Int, rows: [[String]])?
        for separator in [Character(";"), Character(","), Character("\t")] {
            guard let rows = try? csvRows(text, separator: separator), !rows.isEmpty else { continue }
            for index in 0..<min(rows.count, 30) {
                let mapping = suggestMapping(headers: rows[index])
                let score = (mapping.date >= 0 ? 10 : 0) + (mapping.amount >= 0 || mapping.debit >= 0 || mapping.credit >= 0 ? 10 : 0) + (mapping.title >= 0 ? 5 : 0)
                if best == nil || score > best!.score { best = (score, index, rows) }
            }
        }
        guard let best, best.score >= 10 else { throw FinanceError.invalid("Cabeçalho não reconhecido. Use CSV com colunas Data, Descrição e Valor, ou exporte em OFX.") }
        let headers = best.rows[best.index]
        return StatementCSV(headers: headers, rows: Array(best.rows.dropFirst(best.index + 1)), mapping: suggestMapping(headers: headers))
    }

    static func csv(_ document: StatementCSV, mapping: StatementColumnMapping, bank: StatementBank, account: String) throws -> StatementParseResult {
        guard mapping.date >= 0, mapping.title >= 0, mapping.amount >= 0 || mapping.debit >= 0 || mapping.credit >= 0 else {
            throw FinanceError.invalid("Selecione as colunas de data, descrição e valor (ou débito/crédito).")
        }
        var result: [StatementRow] = [], warnings: [String] = [], occurrences: [String: Int] = [:]
        let currencyIndex = document.headers.map(normalize).firstIndex { ["currency", "moeda", "moneda"].contains($0) } ?? -1
        let formatters = dateFormatters()
        for (index, row) in document.rows.enumerated() {
            func field(_ column: Int) -> String { row.indices.contains(column) ? row[column].trimmingCharacters(in: .whitespacesAndNewlines) : "" }
            let title = field(mapping.title)
            let currency = field(currencyIndex).uppercased()
            guard ["", "BRL", "R$", "986"].contains(currency) else { throw FinanceError.invalid("O extrato contém valores em \(currency). Importe apenas movimentos em reais.") }
            // Summary/balance lines are not transactions.
            if title.isEmpty || normalize(title).hasPrefix("saldo") || normalize(title) == "total" { continue }
            guard let date = date(field(mapping.date), using: formatters) else { warnings.append("Linha \(index + 2): data não reconhecida."); continue }
            var cents: Int64?
            if mapping.amount >= 0 {
                cents = amount(field(mapping.amount))
                let direction = normalize(field(mapping.direction))
                if let value = cents, ["d", "debito", "despesa", "saida"].contains(direction) { cents = -abs(value) }
                if let value = cents, ["c", "credito", "receita", "entrada"].contains(direction) { cents = abs(value) }
            } else {
                let debit = mapping.debit >= 0 ? amount(field(mapping.debit)) : 0
                let credit = mapping.credit >= 0 ? amount(field(mapping.credit)) : 0
                if debit == nil && !field(mapping.debit).isEmpty || credit == nil && !field(mapping.credit).isEmpty {
                    warnings.append("Linha \(index + 2): débito/crédito inválido."); continue
                }
                cents = abs(credit ?? 0) - abs(debit ?? 0)
            }
            guard let cents, cents != 0 else {
                if cents == nil { warnings.append("Linha \(index + 2): valor não reconhecido.") }
                continue
            }
            let canonical = "\(dayKey(date))|\(cents)|\(normalize(title))"
            let ordinal = occurrences[canonical, default: 0]; occurrences[canonical] = ordinal + 1
            let suppliedID = field(mapping.identifier)
            let identifier = suppliedID.isEmpty ? "\(canonical)|\(ordinal)" : "\(suppliedID)|\(canonical)|\(ordinal)"
            let source = "csv:\(bank.rawValue):\(normalize(account))"
            result.append(StatementRow(id: fingerprint(source: source, identifier: identifier), date: date, title: title, signedCents: cents))
        }
        return StatementParseResult(rows: result, warnings: warnings)
    }
}
