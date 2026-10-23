import SwiftUI
import SwiftData

struct CardPurchaseEditView: View {
    let card: CreditCard
    let purchaseID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var title = ""
    @State private var amount = ""
    @State private var date = Date.now
    @State private var installments = 1
    @State private var categoryID: UUID?
    @State private var initialized = false
    @State private var error: String?
    @FocusState private var focused: Bool
    private var purchase: CardPurchaseGroup? {
        guard card.modelContext != nil else { return nil }
        return CardPurchaseService.groups(for: card).first { $0.purchaseID == purchaseID }
    }
    var body: some View {
        NavigationStack {
            Form {
                if let purchase {
                    Section("Compra") {
                        TextField("Título", text: $title).focused($focused).submitLabel(.done).onSubmit { focused = false }
                        HStack {
                            Text("R$").foregroundStyle(.secondary)
                            CurrencyTextField(text: $amount).accessibilityLabel("Valor total em reais")
                        }
                        DatePicker("Data da compra", selection: $date, in: ...Date.now, displayedComponents: .date)
                        if !purchase.isRecurring {
                            Picker("Parcelas", selection: $installments) {
                                ForEach(1...120, id: \.self) { Text("\($0)x").tag($0) }
                            }
                        }
                        Picker("Categoria", selection: $categoryID) {
                            Text("Sem categoria").tag(nil as UUID?)
                            ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                        }
                    } footer: {
                        Text(purchase.isRecurring ? "Edita somente esta cobrança; as próximas seguem a recorrência." : "Valor, data e parcelas recalculam as faturas. Pagamentos já feitos são mantidos.")
                    }
                } else { ContentUnavailableView("Compra removida", systemImage: "bag") }
            }
            .trackrFormScreen("Editar compra")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { TrackrToolbarButton("Cancelar", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    TrackrToolbarButton("Salvar", systemImage: "checkmark") {
                        do {
                            guard let cents = Money.parse(amount) else { throw FinanceError.invalid("Informe um valor positivo.") }
                            try CreditCardViewModel().editPurchase(context: context, card: card, purchaseID: purchaseID, title: title,
                                amountCents: cents, date: date, installments: installments, category: categories.first { $0.id == categoryID })
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.disabled(purchase == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard !initialized, let purchase else { return }
                title = purchase.title; amount = Money.input(purchase.amountCents); date = purchase.date
                installments = purchase.installments; categoryID = purchase.category?.id; initialized = true
            }
            .financeError($error)
        }
    }
}
