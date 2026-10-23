import SwiftUI
import SwiftData

struct TransactionsView: View {
    @State private var importingStatement = false
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \InvoicePayment.date, order: .reverse) private var payments: [InvoicePayment]
    @Query private var scheduled: [ScheduledPayment]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var cards: [CreditCard]
    @State private var viewingPurchase: CardPurchaseGroup?
    @State private var selectedMonth = FinanceDate.month(.now)
    @State private var kind: TransactionKind?
    @State private var categoryID: UUID?
    @State private var repeating: TrackrTransactionDraft?
    @State private var showAdd = false
    @State private var editing: Transaction?
    @State private var deleting: Transaction?
    @State private var viewing: Transaction?
    @Environment(TrackrRouter.self) private var router
    @State private var error: String?

    private var cash: [Transaction] {
        transactions.filter {
            $0.card == nil && FinanceDate.sameMonth($0.date, selectedMonth) && (kind == nil || $0.kind == kind)
                && (categoryID == nil || $0.category?.id == categoryID)
                && (router.searchTerm.isEmpty || $0.title.localizedCaseInsensitiveContains(router.searchTerm))
        }
    }
    private var hasFilters: Bool { kind != nil || categoryID != nil || !router.searchTerm.isEmpty }
    private var cardPurchases: [CardPurchaseGroup] {
        guard kind != .income else { return [] }
        return CardPurchaseService.groups(for: cards).filter {
            FinanceDate.sameMonth($0.date, selectedMonth) && (categoryID == nil || $0.category?.id == categoryID)
                && (router.searchTerm.isEmpty || $0.title.localizedCaseInsensitiveContains(router.searchTerm) || $0.card.name.localizedCaseInsensitiveContains(router.searchTerm))
        }
    }
    private var visiblePayments: [InvoicePayment] {
        payments.filter { FinanceDate.sameMonth($0.date, selectedMonth) && kind != .income && categoryID == nil
            && (router.searchTerm.isEmpty || ($0.card?.name ?? "").localizedCaseInsensitiveContains(router.searchTerm)) }
    }
    var body: some View {
        List {
            Section {
                HStack {
                    Button { selectedMonth = FinanceDate.monthOffset(-1, from: selectedMonth) } label: {
                        Image(systemName: "chevron.left").padding(.vertical, 8)
                    }.buttonStyle(.plain).accessibilityLabel("Mês anterior")
                    Spacer(minLength: 8)
                    Text(FinanceDate.monthTitle(selectedMonth))
                        .font(.headline).foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { selectedMonth = FinanceDate.monthOffset(1, from: selectedMonth) } label: {
                        Image(systemName: "chevron.right").padding(.vertical, 8)
                    }.buttonStyle(.plain).accessibilityLabel("Próximo mês")
                }
            } header: { Text("Mês do extrato") }
            Section {
                Picker("Natureza", selection: $kind) {
                    Text("Todos").tag(nil as TransactionKind?)
                    Text("Despesas").tag(Optional(TransactionKind.expense))
                    Text("Receitas").tag(Optional(TransactionKind.income))
                }.pickerStyle(.segmented)
                Picker("Categoria", selection: $categoryID) {
                    Text("Todas").tag(nil as UUID?)
                    ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                }
                if hasFilters { Button("Limpar filtros") { clearFilters() } }
            } header: { Text("Filtros") }
            Section("Lançamentos na conta") {
                if cash.isEmpty && cardPurchases.isEmpty && visiblePayments.isEmpty {
                    ContentUnavailableView(hasFilters ? "Nenhum resultado" : "Nenhuma transação", systemImage: hasFilters ? "line.3.horizontal.decrease.circle" : "banknote",
                                           description: Text(hasFilters ? "Tente outro mês, categoria ou termo de busca." : "Não há lançamentos neste mês. Escolha outro mês ou adicione receitas e despesas."))
                }
                ForEach(cash) { transaction in
                    let managed = transaction.isAutomaticRecurrence || scheduled.contains { $0.paidTransactionID == transaction.id }
                    Button { if managed { viewing = transaction } else { editing = transaction } } label: {
                        TrackrTransactionRow(transaction: transaction, managed: managed)
                    }.buttonStyle(.plain)
                    .contextMenu {
                        Button("Repetir lançamento", systemImage: "doc.on.doc") { repeating = TrackrTransactionDraft(transaction: transaction) }
                        if !managed {
                            Button("Editar", systemImage: "pencil") { editing = transaction }
                        }
                        Button("Excluir", systemImage: "trash", role: .destructive) { deleting = transaction }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Excluir", role: .destructive) { deleting = transaction }.tint(.red)
                        if !managed {
                            Button("Editar") { editing = transaction }.tint(.blue)
                        }
                    }
                }
            }
            if !cardPurchases.isEmpty {
                Section {
                    ForEach(cardPurchases) { purchase in
                        Button { viewingPurchase = purchase } label: { CardPurchaseRow(purchase: purchase) }.buttonStyle(.plain)
                    }
                } header: { Text("Compras nos cartões") } footer: {
                    Text("Total por data da compra. Toque para ver parcelas; o débito ocorre ao pagar a fatura.")
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
        .trackrListScreen("Extrato")
        .searchable(text: Binding(get: { router.searchTerm }, set: { router.searchTerm = $0 }), prompt: "Buscar no extrato")
        .toolbar {
            Menu {
                Button("Novo lançamento", systemImage: "plus") { showAdd = true }
                Button("Importar extrato", systemImage: "square.and.arrow.down") { importingStatement = true }
            } label: { Label("Ações do extrato", systemImage: "ellipsis.circle") }
        }
        .sheet(isPresented: $showAdd) { AddTransactionView() }
        .sheet(item: $editing) { AddTransactionView(transaction: $0) }
        .sheet(item: $viewing) { TrackrTransactionDetailView(transaction: $0) }
        .sheet(item: $repeating) { AddTransactionView(draft: $0) }
        .sheet(item: $viewingPurchase) { CardPurchaseDetailView(card: $0.card, purchaseID: $0.purchaseID) }
        .onAppear(perform: openRequestedTransaction)
        .onChange(of: router.selectedTab) { _, tab in
            if tab == .transactions { selectedMonth = FinanceDate.month(.now); openRequestedTransaction() }
        }
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
        } message: { Text(TransactionViewModel.deletionExplanation) }
        .statementImporter(isPresented: $importingStatement)
        .financeError($error)
    }

    private func openRequestedTransaction() {
        guard let id = router.selectedTransactionID else { return }
        viewing = transactions.first { $0.id == id }
        if let viewing { selectedMonth = FinanceDate.month(viewing.date) }
        router.selectedTransactionID = nil
    }
    private func clearFilters() { kind = nil; categoryID = nil; router.searchTerm = "" }
}

private struct TrackrTransactionRow: View {
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false
    let transaction: Transaction
    let managed: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolTile(symbol: transaction.category?.symbol ?? (transaction.kind == .income ? "arrow.down.left" : "arrow.up.right"),
                       tint: transaction.kind == .income ? TrackrTheme.income : (transaction.category?.color ?? TrackrTheme.expense))
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
                .foregroundStyle(transaction.kind == .income ? TrackrTheme.income : .primary)
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}

private struct TrackrTransactionDetailView: View {
    let transaction: Transaction
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var confirmingDelete = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TrackrSummaryHeader(eyebrow: transaction.kind.title, title: Money.format(transaction.amountCents),
                                        subtitle: transaction.title, symbol: transaction.kind == .income ? "arrow.down.left" : "arrow.up.right")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section {
                    CategoryLabel(category: transaction.category)
                    LabeledContent("Data", value: transaction.date.formatted(date: .long, time: .omitted))
                }
                Section {
                    Button("Excluir lançamento", role: .destructive) { confirmingDelete = true }.foregroundStyle(.red)
                }
            }.trackrListScreen("Lançamento", largeTitle: false)
                .toolbar { ToolbarItem(placement: .confirmationAction) { TrackrToolbarButton("Concluir", systemImage: "checkmark") { dismiss() } } }
                .confirmationDialog("Excluir este lançamento?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Excluir lançamento", role: .destructive) {
                        do { try TransactionViewModel().deleteCash(transaction, context: context); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                } message: { Text(TransactionViewModel.deletionExplanation) }
                .financeError($error)
        }
    }
}
