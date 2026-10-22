import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \InvoicePayment.date, order: .reverse) private var payments: [InvoicePayment]
    @State private var showAdd = false
    @State private var editing: Transaction?
    @State private var deleting: Transaction?
    @State private var search = ""
    @State private var error: String?

    private var cash: [Transaction] {
        transactions.filter { $0.card == nil && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        List {
            Section("Lançamentos na conta") {
                if cash.isEmpty {
                    ContentUnavailableView("Nenhuma transação", systemImage: "banknote",
                                           description: Text("Adicione receitas e despesas. Para saldo inicial, registre uma receita."))
                }
                ForEach(cash) { transaction in
                    Button { editing = transaction } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(transaction.title).foregroundStyle(.primary)
                                Spacer()
                                Text(Money.format(transaction.amountCents))
                                    .foregroundStyle(transaction.kind == .income ? .green : .primary)
                                    .monospacedDigit()
                            }
                            CategoryLabel(category: transaction.category).font(.caption)
                            Text("\(transaction.kind.title) • \(transaction.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                            if transaction.recurrenceKey != nil {
                                Label("Cobrança automática", systemImage: "repeat").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(transaction.recurrenceKey != nil)
                    .swipeActions {
                        if transaction.recurrenceKey == nil {
                            Button("Excluir", role: .destructive) { deleting = transaction }
                            Button("Editar") { editing = transaction }.tint(.blue)
                        }
                    }
                }
            }
            if !payments.isEmpty {
                Section("Pagamentos de faturas") {
                    ForEach(payments.filter { search.isEmpty || ($0.card?.name ?? "").localizedCaseInsensitiveContains(search) }) { payment in
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
        .navigationTitle("Transações")
        .searchable(text: $search, prompt: "Buscar título")
        .toolbar { Button("Adicionar", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { AddTransactionView() }
        .sheet(item: $editing) { AddTransactionView(transaction: $0) }
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
        .financeError($error)
    }
}
