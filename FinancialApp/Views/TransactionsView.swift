import SwiftUI
import SwiftData

struct TransactionsView: View {
    @State private var importingStatement = false
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \InvoicePayment.date, order: .reverse) private var payments: [InvoicePayment]
    @Query private var scheduled: [ScheduledPayment]
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var period = LedgerTransactionPeriod.all
    @State private var kind: TransactionKind?
    @State private var categoryID: UUID?
    @State private var repeating: LedgerTransactionDraft?
    @State private var showAdd = false
    @State private var editing: Transaction?
    @State private var deleting: Transaction?
    @State private var viewing: Transaction?
    @Environment(LedgerRouter.self) private var router
    @State private var error: String?

    private var cash: [Transaction] {
        transactions.filter {
            $0.card == nil && period.includes($0.date) && (kind == nil || $0.kind == kind)
                && (categoryID == nil || $0.category?.id == categoryID)
                && (router.searchTerm.isEmpty || $0.title.localizedCaseInsensitiveContains(router.searchTerm))
        }
    }
    private var hasFilters: Bool { period != .all || kind != nil || categoryID != nil || !router.searchTerm.isEmpty }
    private var visiblePayments: [InvoicePayment] {
        payments.filter { period.includes($0.date) && kind != .income && categoryID == nil
            && (router.searchTerm.isEmpty || ($0.card?.name ?? "").localizedCaseInsensitiveContains(router.searchTerm)) }
    }
    var body: some View {
        List {
            Section {
                Picker("Natureza", selection: $kind) {
                    Text("Todos").tag(nil as TransactionKind?)
                    Text("Despesas").tag(Optional(TransactionKind.expense))
                    Text("Receitas").tag(Optional(TransactionKind.income))
                }.pickerStyle(.segmented)
                Picker("Período", selection: $period) { ForEach(LedgerTransactionPeriod.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Categoria", selection: $categoryID) {
                    Text("Todas").tag(nil as UUID?)
                    ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                }
                if hasFilters { Button("Limpar filtros") { clearFilters() } }
            } header: { Text("Filtrar extrato") }
            Section("Lançamentos na conta") {
                if cash.isEmpty {
                    ContentUnavailableView(hasFilters ? "Nenhum resultado" : "Nenhuma transação", systemImage: hasFilters ? "line.3.horizontal.decrease.circle" : "banknote",
                                           description: Text(hasFilters ? "Tente outro período, categoria ou termo de busca." : "Adicione receitas e despesas. Para saldo inicial, registre uma receita."))
                }
                ForEach(cash) { transaction in
                    let managed = transaction.isAutomaticRecurrence || scheduled.contains { $0.paidTransactionID == transaction.id }
                    Button { if managed { viewing = transaction } else { editing = transaction } } label: {
                        LedgerTransactionRow(transaction: transaction, managed: managed)
                    }.buttonStyle(.plain)
                    .contextMenu {
                        Button("Repetir lançamento", systemImage: "doc.on.doc") { repeating = LedgerTransactionDraft(transaction: transaction) }
                        if !managed {
                            Button("Editar", systemImage: "pencil") { editing = transaction }
                            Button("Excluir", systemImage: "trash", role: .destructive) { deleting = transaction }
                        }
                    }
                    .swipeActions {
                        if !managed {
                            Button("Excluir", role: .destructive) { deleting = transaction }.tint(.red)
                            Button("Editar") { editing = transaction }.tint(.blue)
                        }
                    }
                }
            }
            if !visiblePayments.isEmpty {
                Section("Pagamentos de faturas") {
                    ForEach(visiblePayments) { payment in
                        VStack(alignment: .leading, spacing: 4) {
                            MoneyRow(title: payment.card?.name ?? "Cartão", cents: payment.amountCents, symbol: "checkmark.circle")
                            Text("Pago em \(payment.date.formatted(date: .abbreviated, time: .omitted)) • Fatura \(FinanceDate.monthTitle(payment.invoiceDueDate))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .ledgerListScreen("Extrato")
        .searchable(text: Binding(get: { router.searchTerm }, set: { router.searchTerm = $0 }), prompt: "Buscar no extrato")
        .toolbar {
            Menu {
                Button("Novo lançamento", systemImage: "plus") { showAdd = true }
                Button("Importar extrato", systemImage: "square.and.arrow.down") { importingStatement = true }
            } label: { Label("Ações do extrato", systemImage: "ellipsis.circle") }
        }
        .sheet(isPresented: $showAdd) { AddTransactionView() }
        .sheet(item: $editing) { AddTransactionView(transaction: $0) }
        .sheet(item: $viewing) { LedgerTransactionDetailView(transaction: $0) }
        .sheet(item: $repeating) { AddTransactionView(draft: $0) }
        .onAppear(perform: openRequestedTransaction)
        .onChange(of: router.selectedTransactionID) { _, _ in openRequestedTransaction() }
        .confirmationDialog("Excluir esta transação?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                guard let deleting else { return }
                do { try TransactionViewModel().deleteCash(deleting, context: context) }
                catch { self.error = error.localizedDescription }
                self.deleting = nil
            }
        }
        .statementImporter(isPresented: $importingStatement)
        .financeError($error)
    }

    private func openRequestedTransaction() {
        guard let id = router.selectedTransactionID else { return }
        viewing = transactions.first { $0.id == id }
        router.selectedTransactionID = nil
    }
    private func clearFilters() { period = .all; kind = nil; categoryID = nil; router.searchTerm = "" }
}

private struct LedgerTransactionRow: View {
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    let transaction: Transaction
    let managed: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(symbol: transaction.category?.symbol ?? (transaction.kind == .income ? "arrow.down.left" : "arrow.up.right"),
                       tint: transaction.kind == .income ? LedgerTheme.income : (transaction.category?.color ?? LedgerTheme.expense))
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.title).font(.headline).foregroundStyle(Color.primary)
                Text("\(transaction.category?.name ?? "Sem categoria") • \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                if managed { Label("Lançamento automático", systemImage: "checkmark.seal").font(.caption2).foregroundStyle(.secondary) }
                if transaction.isImportedStatement { Label("Extrato bancário", systemImage: "building.columns").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            Text(hideAmounts ? "••••" : "\(transaction.kind == .income ? "+" : "−") \(Money.format(transaction.amountCents))")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(transaction.kind == .income ? LedgerTheme.income : .primary)
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}

private struct LedgerTransactionDetailView: View {
    let transaction: Transaction
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LedgerSummaryHeader(eyebrow: transaction.kind.title, title: Money.format(transaction.amountCents),
                                        subtitle: transaction.title, symbol: transaction.kind == .income ? "arrow.down.left" : "arrow.up.right")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    CategoryLabel(category: transaction.category)
                    LabeledContent("Data", value: transaction.date.formatted(date: .long, time: .omitted))
                }
            }.ledgerListScreen("Lançamento", largeTitle: false)
                .toolbar { ToolbarItem(placement: .confirmationAction) { LedgerToolbarButton("Concluir", systemImage: "checkmark") { dismiss() } } }
        }
    }
}
