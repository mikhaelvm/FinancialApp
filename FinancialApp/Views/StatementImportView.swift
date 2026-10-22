import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct StatementImportView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.name) private var categories: [Category]
    let fileURL: URL
    @State private var choosingFile = false
    @State private var filename = ""
    @State private var csv: StatementCSV?
    @State private var mapping = StatementColumnMapping()
    @State private var parsedRows: [StatementRow] = []
    @State private var rows: [StatementRow] = []
    @State private var warnings: [String] = []
    @State private var error: String?
    @State private var message: String?
    @State private var confirming = false
    @State private var isLoading = false

    private var selected: [StatementRow] { rows.filter(\.selected) }
    private var income: Int64 { selected.filter { $0.signedCents > 0 }.reduce(0) { $0 + $1.signedCents } }
    private var expenses: Int64 { selected.filter { $0.signedCents < 0 }.reduce(0) { $0 - $1.signedCents } }

    var body: some View {
        List {
            Section {
                Button(filename.isEmpty ? "Selecionar extrato OFX, CSV ou PDF" : "Escolher outro arquivo", systemImage: "doc.badge.plus") { choosingFile = true }.disabled(isLoading)
                if !filename.isEmpty { LabeledContent("Arquivo", value: filename).font(.caption) }
            } footer: {
                Text("Use o extrato da conta, não a fatura do cartão. A análise ocorre neste aparelho. PDF exige revisão individual; saldo inicial e saldo final não são importados como movimentos.")
            }
            if let csv {
                Section {
                    column("Data", value: $mapping.date, headers: csv.headers)
                    column("Descrição", value: $mapping.title, headers: csv.headers)
                    column("Valor com sinal", value: $mapping.amount, headers: csv.headers)
                    if mapping.amount < 0 {
                        column("Débito", value: $mapping.debit, headers: csv.headers)
                        column("Crédito", value: $mapping.credit, headers: csv.headers)
                    }
                    column("Tipo / D ou C", value: $mapping.direction, headers: csv.headers)
                    column("Identificador", value: $mapping.identifier, headers: csv.headers)
                    Button("Analisar colunas selecionadas") { Task { await analyzeCSV(csv) } }.disabled(isLoading)
                } header: { Text("Colunas do CSV") } footer: {
                    Text("Confirme as colunas antes de importar. Não use a coluna Saldo como valor. No Mercado Pago, prefira o impacto líquido na conta (SETTLEMENT_NET_AMOUNT). Para valores sem sinal, indique D/C ou use Débito e Crédito separados.")
                }
            }
            if !rows.isEmpty {
                Section("Revisão") {
                    MoneyRow(title: "Receitas selecionadas", cents: income, symbol: "plus.circle", tint: .green)
                    MoneyRow(title: "Despesas selecionadas", cents: expenses, symbol: "minus.circle")
                    LabeledContent("Selecionados", value: "\(selected.count) de \(rows.count)")
                    Button("Selecionar novos lançamentos") {
                        for index in rows.indices { rows[index].selected = !rows[index].isDuplicate && !rows[index].requiresReview && rows[index].date <= FinanceDate.day(.now) }
                    }
                    Button("Desmarcar todos") { for index in rows.indices { rows[index].selected = false } }
                }
                Section {
                    ForEach($rows) { $row in
                        StatementReviewRow(row: $row, categories: categories)
                    }
                } header: { Text("Lançamentos encontrados") } footer: {
                    Text("Revise descrições, valores, categorias e duplicados. Uma nova importação do mesmo extrato não repete registros com a mesma identificação. Movimentos manuais e pagamentos de faturas já registrados também podem aparecer como possíveis duplicados.")
                }
                Section { Button("Importar \(selected.count) lançamentos") { confirming = true }.disabled(selected.isEmpty) }
            }
            if !warnings.isEmpty {
                Section("Linhas que precisam de atenção") {
                    ForEach(Array(warnings.prefix(30).enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).foregroundStyle(.orange) }
                    if warnings.count > 30 { Text("E mais \(warnings.count - 30) linhas. Confira o arquivo original.").font(.caption) }
                }
            }
            if let message { Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) } }
        }
        .ledgerListScreen("Importar extrato", largeTitle: false)
        .disabled(isLoading)
        .overlay {
            if isLoading { ProgressView("Analisando extrato…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }
        .task(id: fileURL) { await load(fileURL) }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: StatementFilePicker.contentTypes) { result in
            do {
                let url = try result.get()
                Task { await load(url) }
            } catch { if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription } }
        }
        .confirmationDialog("Adicionar os lançamentos ao Ledger?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Confirmar importação") {
                do {
                    let count = try StatementImportService.commit(rows, context: context)
                    rows = try StatementImportService.prepare(parsedRows, context: context)
                    message = "\(count) lançamentos importados. Eles já aparecem no Extrato."
                } catch { self.error = error.localizedDescription }
            }
        } message: { Text("Receitas: \(Money.format(income)). Despesas: \(Money.format(expenses)). O saldo consolidado será atualizado.") }
        .financeError($error)
    }
    private func column(_ title: String, value: Binding<Int>, headers: [String]) -> some View {
        Picker(title, selection: Binding(get: { value.wrappedValue }, set: { newValue in
            value.wrappedValue = newValue
            rows = []; parsedRows = []; message = nil
        })) {
            Text("Não usar").tag(-1)
            ForEach(headers.indices, id: \.self) { index in Text("\(index + 1). \(headers[index])").tag(index) }
        }
    }
    private func analyzeCSV(_ document: StatementCSV) async {
        isLoading = true
        defer { isLoading = false }
        let configuration = mapping
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try StatementParser.csv(document, mapping: configuration, bank: .other, account: "")
            }.value
            parsedRows = result.rows; warnings = result.warnings
            rows = try StatementImportService.prepare(parsedRows, context: context)
            if rows.isEmpty && warnings.isEmpty { message = "Nenhum movimento financeiro encontrado nas colunas selecionadas." }
        } catch { self.error = error.localizedDescription }
    }

    private func load(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            guard ["ofx", "csv", "txt", "pdf"].contains(url.pathExtension.lowercased()) else {
                throw FinanceError.invalid("Escolha um extrato OFX, CSV ou PDF.")
            }
            filename = url.lastPathComponent; rows = []; parsedRows = []; warnings = []; csv = nil; message = nil
            let loaded = try await Task.detached(priority: .userInitiated) {
                if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > StatementParser.maximumBytes {
                    throw FinanceError.invalid("O extrato deve ter até 15 MB.")
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                if url.pathExtension.lowercased() == "pdf" { return LoadedStatement.ofx(try PDFStatementReader.read(data)) }
                let text = try StatementParser.text(from: data)
                if text.localizedCaseInsensitiveContains("<OFX") { return LoadedStatement.ofx(try StatementParser.ofx(text, bank: .other)) }
                return LoadedStatement.csv(try StatementParser.csvDocument(text))
            }.value
            switch loaded {
            case .ofx(let result):
                parsedRows = result.rows; warnings = result.warnings
                rows = try StatementImportService.prepare(parsedRows, context: context)
            case .csv(let document):
                csv = document; mapping = document.mapping
                if mapping.date >= 0 && mapping.title >= 0 && (mapping.amount >= 0 || mapping.debit >= 0 || mapping.credit >= 0) { await analyzeCSV(document) }
            }
        } catch { self.error = error.localizedDescription }
    }
}

private enum LoadedStatement: Sendable {
    case ofx(StatementParseResult)
    case csv(StatementCSV)
}


/// Opens Files immediately. The review sheet is presented only after a file is chosen.
private struct SelectedStatementFile: Identifiable { let url: URL; var id: URL { url } }
struct StatementFilePicker: ViewModifier {
    @Binding var isPresented: Bool
    @State private var selected: SelectedStatementFile?
    @State private var error: String?
    static var contentTypes: [UTType] { [.pdf, .commaSeparatedText, .plainText, UTType(filenameExtension: "ofx") ?? .data] }
    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: Self.contentTypes) { result in
                do { selected = SelectedStatementFile(url: try result.get()) }
                catch { if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription } }
            }
            .sheet(item: $selected) { file in
                NavigationStack {
                    StatementImportView(fileURL: file.url)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { LedgerToolbarButton("Concluir", systemImage: "checkmark") { selected = nil } } }
                }
            }
            .financeError($error)
    }
}
extension View {
    func statementImporter(isPresented: Binding<Bool>) -> some View { modifier(StatementFilePicker(isPresented: isPresented)) }
}


private struct StatementReviewRow: View {
    @Binding var row: StatementRow
    let categories: [Category]
    @State private var amountText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if row.requiresReview {
                Label("PDF: confira antes de selecionar", systemImage: "doc.text.viewfinder").font(.caption).foregroundStyle(.orange)
                TextField("Descrição", text: $row.title)
                DatePicker("Data", selection: $row.date, in: ...Date.now, displayedComponents: .date)
                TextField("Valor em reais", text: $amountText).keyboardType(.decimalPad)
                Picker("Natureza", selection: Binding(get: { row.kind }, set: { kind in
                    row.signedCents = kind == .expense ? -abs(row.signedCents) : abs(row.signedCents)
                })) {
                    Text("Despesa").tag(TransactionKind.expense)
                    Text("Receita").tag(TransactionKind.income)
                }.pickerStyle(.segmented)
            }
            Toggle(isOn: $row.selected) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title).font(.subheadline.weight(.medium))
                    Text("\(row.kind.title) • \(Money.format(abs(row.signedCents))) • \(row.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(row.kind == .income ? .green : .secondary)
                }
            }.disabled(!canSelect)
            if row.isDuplicate { Label("Possível duplicado • desmarcado por padrão", systemImage: "doc.on.doc").font(.caption).foregroundStyle(.orange) }
            if row.isDuplicate && row.date <= FinanceDate.day(.now) {
                Button(row.importAsNew ? "Cancelar inclusão como novo" : "É outro movimento: importar como novo") {
                    row.importAsNew.toggle(); row.selected = row.importAsNew && canSelect
                }.font(.caption)
            }
            if row.date > FinanceDate.day(.now) { Text("Lançamento futuro: não será importado como realizado.").font(.caption).foregroundStyle(.secondary) }
            if row.selected {
                if !row.requiresReview {
                Picker("Natureza", selection: Binding(get: { row.kind }, set: { kind in
                    row.signedCents = kind == .expense ? -abs(row.signedCents) : abs(row.signedCents)
                })) {
                    Text("Despesa").tag(TransactionKind.expense)
                    Text("Receita").tag(TransactionKind.income)
                }.font(.caption)
                }
                Picker("Categoria", selection: $row.categoryID) {
                    Text("Sem categoria").tag(nil as UUID?)
                    ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                }.font(.caption)
            }
        }.padding(.vertical, 4)
        .onAppear { amountText = Money.input(abs(row.signedCents)) }
        .onChange(of: amountText) { _, text in
            if let cents = Money.parse(text) { row.signedCents = row.kind == .expense ? -cents : cents }
            else if row.requiresReview { row.selected = false }
        }
        .onChange(of: row.signedCents) { _, cents in
            if Money.parse(amountText) != abs(cents) { amountText = Money.input(abs(cents)) }
        }
        .onChange(of: row.title) { _, title in
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { row.selected = false }
        }
    }
    private var canSelect: Bool {
        row.date <= FinanceDate.day(.now) && (!row.isDuplicate || row.importAsNew)
            && !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!row.requiresReview || Money.parse(amountText) != nil)
    }
}
