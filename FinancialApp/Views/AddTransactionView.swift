import SwiftUI
import SwiftData

enum EntryMode: String, CaseIterable, Identifiable {
    case single = "À vista / avulsa"
    case installment = "Parcelado"
    case subscription = "Recorrente / assinatura"
    var id: String { rawValue }
}

struct AddTransactionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    var transaction: Transaction? = nil
    var subscription: Subscription? = nil
    var initialCard: CreditCard? = nil
    var initialMode: EntryMode = .single
    @State private var mode: EntryMode = .single
    @State private var title = ""
    @State private var amount = ""
    @State private var kind = TransactionKind.expense
    @State private var date = Date.now
    @State private var categoryID: UUID?
    @State private var cardID: UUID?
    @State private var installments = 2
    @State private var cycle = BillingCycle.monthly
    @State private var error: String?
    @State private var loaded = false

    private var isEditing: Bool { transaction != nil || subscription != nil }
    private var selectedCard: CreditCard? { cards.first { $0.id == cardID } }
    private var selectedCategory: Category? { categories.first { $0.id == categoryID } }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section("Tipo de lançamento") {
                        Picker("Modalidade", selection: $mode) {
                            ForEach(EntryMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
                Section("Detalhes") {
                    TextField("Título", text: $title).textInputAutocapitalization(.sentences)
                    TextField(mode == .installment ? "Valor total (R$): 1.200,00" : "Valor (R$): 120,00", text: $amount)
                        .keyboardType(.decimalPad)
                    Picker("Categoria", selection: $categoryID) {
                        Text("Sem categoria").tag(nil as UUID?)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
                        }
                    }
                    if mode == .single {
                        Picker("Natureza", selection: $kind) {
                            ForEach(TransactionKind.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    if mode == .subscription {
                        Picker("Periodicidade", selection: $cycle) {
                            ForEach(BillingCycle.allCases) { Text($0.title).tag($0) }
                        }
                        DatePicker("Próxima renovação", selection: $date,
                                   in: FinanceDate.day(.now)..., displayedComponents: .date)
                    } else {
                        DatePicker("Data", selection: $date, in: ...Date.now, displayedComponents: .date)
                    }
                }
                if transaction == nil && (mode != .single || kind == .expense) {
                    Section {
                        Picker("Cobrança", selection: $cardID) {
                            if mode != .installment { Text("Débito / conta").tag(nil as UUID?) }
                            if mode == .installment && cardID == nil { Text("Selecione um cartão").tag(nil as UUID?) }
                            ForEach(cards) { card in Text(card.name).tag(Optional(card.id)) }
                        }
                        if cards.isEmpty {
                            Text("Cadastre um cartão na aba Cartões para lançar compras a crédito.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let card = selectedCard {
                            MoneyRow(title: "Limite disponível", cents: card.availableLimitCents)
                        }
                        if mode == .installment {
                            Stepper("\(installments) parcelas", value: $installments, in: 2...120)
                            if let cents = Money.parse(amount),
                               let amounts = try? InvoiceEngine().installmentAmounts(totalCents: cents, count: installments) {
                                Text("\(installments)x de aproximadamente \(Money.format(amounts[0])). Centavos excedentes são distribuídos nas primeiras parcelas.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: { Text("Pagamento") } footer: {
                        Text(mode == .subscription
                             ? "Cobranças são lançadas ao abrir o app ou enquanto ele estiver ativo. Previsões futuras aparecem nas faturas."
                             : "No cartão, o limite é comprometido pelo valor total. Compras no dia do fechamento vão para a próxima fatura.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar lançamento" : "Novo lançamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).fontWeight(.semibold) }
            }
            .onAppear(perform: load)
            .onChange(of: mode) { _, newMode in
                if newMode == .installment { kind = .expense; cardID = cardID ?? cards.first?.id }
            }
            .financeError($error)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        mode = initialMode
        cardID = initialCard?.id
        if let transaction {
            title = transaction.title; amount = Money.input(transaction.amountCents)
            date = transaction.date; kind = transaction.kind; categoryID = transaction.category?.id
        }
        if let subscription {
            mode = .subscription; title = subscription.title; amount = Money.input(subscription.amountCents)
            date = max(subscription.nextRenewalDate, FinanceDate.day(.now))
            categoryID = subscription.category?.id; cardID = subscription.card?.id; cycle = subscription.cycle
        }
    }

    private func save() {
        do {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let cents = Money.parse(amount) else {
                throw FinanceError.invalid("Informe título e valor válido em reais, como 1.234,56.")
            }
            if mode == .subscription {
                try SubscriptionViewModel().save(context: context, subscription: subscription, title: title,
                                                  amountText: amount, cycle: cycle, renewalDate: date,
                                                  category: selectedCategory, card: selectedCard)
            } else if mode == .installment || (kind == .expense && selectedCard != nil && transaction == nil) {
                guard let card = selectedCard else { throw FinanceError.invalid("Selecione um cartão.") }
                try CreditCardViewModel().purchase(context: context, title: title, amountCents: cents,
                                                   date: date, installments: mode == .installment ? installments : 1,
                                                   card: card, category: selectedCategory)
            } else {
                try TransactionViewModel().saveCash(context: context, transaction: transaction,
                                                    title: title, amountText: amount, kind: kind,
                                                    date: date, category: selectedCategory)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
