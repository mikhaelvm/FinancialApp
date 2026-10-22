import SwiftUI
import SwiftData

enum EntryMode: String, CaseIterable, Identifiable {
    case single = "Gasto ou receita"
    case installment = "Compra parcelada"
    case subscription = "Conta recorrente / assinatura"
    case scheduled = "Conta a pagar"
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
    var initialKind: TransactionKind = .expense
    var draft: LedgerTransactionDraft? = nil
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
    private enum Field: Hashable { case amount, title }
    @FocusState private var focusedField: Field?

    private var isEditing: Bool { transaction != nil || subscription != nil }
    private var selectedCard: CreditCard? { cards.first { $0.id == cardID } }
    private var selectedCategory: Category? { categories.first { $0.id == categoryID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if draft != nil { Label("Revise a cópia antes de registrar o novo lançamento.", systemImage: "doc.on.doc").font(.footnote).foregroundStyle(.secondary) }
                    if subscription == nil {
                        Picker("Tipo de lançamento", selection: $kind) {
                            Label("Despesa", systemImage: "minus.circle.fill").tag(TransactionKind.expense)
                            Label("Receita", systemImage: "plus.circle.fill").tag(TransactionKind.income)
                        }.pickerStyle(.segmented)
                            .accessibilityHint("Escolha se o dinheiro sai ou entra na sua conta")
                    } else {
                        Label("Despesa recorrente", systemImage: "repeat")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("R$").font(.title2).foregroundStyle(.secondary)
                        CurrencyTextField(text: $amount, textStyle: .largeTitle)
                            .accessibilityLabel(mode == .installment ? "Valor total da compra" : "Valor em reais")
                    }.padding(.vertical, 8)
                    Text(kind == .income ? "Dinheiro que você recebeu." : (mode == .installment ? "Informe o valor total da compra, antes de parcelar." : "Dinheiro que você gastou ou vai pagar."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !isEditing && kind == .expense {
                    Section("Tipo de lançamento") {
                        Picker("Modalidade", selection: $mode) {
                            ForEach(EntryMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                }
                Section("Detalhes") {
                    TextField(kind == .income ? "Ex.: Salário, reembolso" : "Ex.: Mercado, almoço", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                    Picker("Categoria", selection: $categoryID) {
                        Text("Sem categoria").tag(nil as UUID?)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
                        }
                    }
                    if mode == .scheduled {
                        DatePicker("Vencimento", selection: $date, displayedComponents: .date)
                        Label("O saldo será descontado quando você marcar como pago na Agenda.", systemImage: "calendar.badge.clock")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if mode == .subscription {
                        Picker("Periodicidade", selection: $cycle) {
                            ForEach(BillingCycle.allCases) { Text($0.title).tag($0) }
                        }
                        DatePicker("Próxima renovação", selection: $date,
                                   in: FinanceDate.day(.now)..., displayedComponents: .date)
                    } else {
                        DatePicker("Data", selection: $date, in: ...Date.now, displayedComponents: .date)
                    }
                }
                if transaction == nil && mode != .scheduled && (mode != .single || kind == .expense) {
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
            .ledgerFormScreen(isEditing ? "Editar lançamento" : (kind == .income ? "Nova receita" : "Nova despesa"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { LedgerToolbarButton("Cancelar", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    LedgerToolbarButton(isEditing ? "Salvar" : "Adicionar", systemImage: "checkmark", action: save).fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Money.parse(amount) == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    LedgerToolbarButton("Fechar teclado", systemImage: "checkmark") { focusedField = nil }
                }
            }
            .onAppear(perform: load)
            .onChange(of: mode) { _, newMode in
                if newMode != .single { kind = .expense }
                if newMode == .single && date > .now { date = .now }
                if newMode == .installment { kind = .expense; cardID = cardID ?? cards.first?.id }
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .income { mode = .single; cardID = nil; if date > .now { date = .now } }
            }
            .financeError($error)
        }
        .presentationDragIndicator(.visible)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        mode = initialMode
        kind = initialKind
        cardID = initialCard?.id
        if let draft {
            title = draft.title; amount = Money.input(draft.amountCents); kind = draft.kind; categoryID = draft.categoryID
            date = .now; mode = .single; cardID = nil
        }
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
            if mode == .scheduled {
                try ScheduledPaymentViewModel().save(context: context, title: title, amountText: amount,
                                                      dueDate: date, notes: "", categoryID: categoryID)
            } else if mode == .subscription {
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
