import SwiftUI
import SwiftData

struct TransactionsView: View {
    @State private var importingStatement = false
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \InvoicePayment.date, order: .reverse) private var payments: [InvoicePayment]
    @Query private var scheduled: [ScheduledPayment]
    @State private var showAdd = false
    @State private var editing: Transaction?
    @State private var deleting: Transaction?
    @State private var viewing: Transaction?
    @Environment(LedgerRouter.self) private var router
    @State private var error: String?

    private var cash: [Transaction] {
        transactions.filter { $0.card == nil && (router.searchTerm.isEmpty || $0.title.localizedCaseInsensitiveContains(router.searchTerm)) }
    }
    var body: some View {
        List {
            Section("Lançamentos na conta") {
                if cash.isEmpty {
                    ContentUnavailableView("Nenhuma transação", systemImage: "banknote",
                                           description: Text("Adicione receitas e despesas. Para saldo inicial, registre uma receita."))
                }
                ForEach(cash) { transaction in
                    let managed = transaction.isAutomaticRecurrence || scheduled.contains { $0.paidTransactionID == transaction.id }
                    Button { if managed { viewing = transaction } else { editing = transaction } } label: {
                        LedgerTransactionRow(transaction: transaction, managed: managed)
                    }.buttonStyle(.plain)
                    .swipeActions {
                        if !managed {
                            Button("Excluir", role: .destructive) { deleting = transaction }.tint(.red)
                            Button("Editar") { editing = transaction }.tint(.blue)
                        }
                    }
                }
            }
            if !payments.isEmpty {
                Section("Pagamentos de faturas") {
                    ForEach(payments.filter { router.searchTerm.isEmpty || ($0.card?.name ?? "").localizedCaseInsensitiveContains(router.searchTerm) }) { payment in
                        VStack(alignment: .leading, spacing: 4) {
                            MoneyRow(title: payment.card?.name ?? "Cartão", cents: payment.amountCents, symbol: "checkmark.circle")
                            Text("Pago em \(payment.date.formatted(date: .abbreviated, time: .omitted)) • Fatura \(FinanceDate.monthTitle(payment.invoiceDueDate))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Extrato")
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
}

private struct LedgerTransactionRow: View {
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    let transaction: Transaction
    let managed: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(symbol: transaction.category?.symbol ?? (transaction.kind == .income ? "arrow.down.left" : "arrow.up.right"),
                       tint: transaction.kind == .income ? LedgerTheme.accent : (transaction.category?.color ?? .orange))
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.title).font(.headline).foregroundStyle(.primary)
                Text("\(transaction.category?.name ?? "Sem categoria") • \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
                if managed { Label("Lançamento automático", systemImage: "checkmark.seal").font(.caption2).foregroundStyle(.secondary) }
                if transaction.isImportedStatement { Label("Extrato bancário", systemImage: "building.columns").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            Text(hideAmounts ? "••••" : "\(transaction.kind == .income ? "+" : "−") \(Money.format(transaction.amountCents))")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(transaction.kind == .income ? LedgerTheme.accent : .primary)
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
            }.listStyle(.insetGrouped)
                .navigationTitle("Lançamento").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
        }
    }
}
