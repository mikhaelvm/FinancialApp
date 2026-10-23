import SwiftUI
import SwiftData

struct InvoicePaymentRow: View {
    let payment: InvoicePayment
    @Environment(\.modelContext) private var context
    @State private var confirmingDelete = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                MoneyRow(title: payment.card?.name ?? "Cartão", cents: payment.amountCents, symbol: "checkmark.circle")
                Menu {
                    Button("Excluir pagamento", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Ações do pagamento de fatura")
            }
            Text("Pago em \(payment.date.formatted(date: .abbreviated, time: .omitted)) • Fatura \(FinanceDate.monthTitle(payment.invoiceDueDate))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .swipeActions(allowsFullSwipe: false) {
            Button("Excluir", role: .destructive) { confirmingDelete = true }.tint(.red)
        }
        .contextMenu {
            Button("Excluir pagamento", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        }
        .confirmationDialog("Excluir pagamento da fatura?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Excluir pagamento", role: .destructive) {
                do { try CreditCardViewModel().deletePayment(context: context, payment: payment) }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("Devolve o valor ao saldo e deixa a fatura pendente. As compras são mantidas.") }
        .financeError($error)
    }
}

struct InvoicePaymentForm: View {
    let card: CreditCard
    let dueDate: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var error: String?
    private var invoice: Invoice? {
        guard card.modelContext != nil else { return nil }
        return InvoiceEngine().invoices(for: card, through: dueDate).first { $0.dueDate == dueDate }
    }
    var body: some View {
        NavigationStack {
            Form {
                if let invoice, invoice.payableCents > 0, invoice.closingDate <= FinanceDate.day(.now) {
                    Section {
                        LabeledContent("Cartão", value: card.name)
                        LabeledContent("Fatura", value: FinanceDate.monthTitle(dueDate))
                        MoneyRow(title: "Valor a pagar", cents: invoice.payableCents, symbol: "checkmark.circle")
                        DatePicker("Data do pagamento", selection: $date, in: invoice.closingDate...Date.now, displayedComponents: .date)
                    } footer: { Text("Registra uma saída da conta na data escolhida.") }
                } else {
                    ContentUnavailableView("Nenhum valor a pagar", systemImage: "checkmark.circle")
                }
            }
            .trackrFormScreen("Pagar fatura")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { TrackrToolbarButton("Cancelar", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    TrackrToolbarButton("Registrar pagamento", systemImage: "checkmark") {
                        guard let invoice else { return }
                        do { try CreditCardViewModel().pay(context: context, card: card, invoice: invoice, date: date); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled((invoice?.payableCents ?? 0) == 0 || (invoice?.closingDate ?? .distantFuture) > FinanceDate.day(.now))
                }
            }
            .financeError($error)
        }
    }
}
