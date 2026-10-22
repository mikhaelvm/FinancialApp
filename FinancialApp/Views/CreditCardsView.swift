import SwiftUI
import SwiftData

struct CreditCardsView: View {
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false
    @Environment(\.modelContext) private var context
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @State private var showAdd = false
    @State private var deleting: CreditCard?
    @State private var error: String?
    var body: some View {
        List {
            if cards.isEmpty {
                ContentUnavailableView("Seus cartões", systemImage: "creditcard",
                                       description: Text("Cadastre um cartão para acompanhar limites, parcelas e faturas."))
            }
            ForEach(cards) { card in
                NavigationLink { CreditCardDetailView(card: card) } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label(card.name, systemImage: "creditcard.fill").font(.headline)
                            Spacer()
                            Image(systemName: "wave.3.right").accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Limite disponível").font(.caption).foregroundStyle(.secondary)
                            Text(hideAmounts ? "••••" : Money.format(card.availableLimitCents)).font(.title2.bold()).monospacedDigit()
                        }
                        ProgressView(value: min(Double(card.usedLimitCents), Double(card.limitCents)),
                                     total: Double(max(1, card.limitCents)))
                            .tint(card.availableLimitCents == 0 ? .orange : LedgerTheme.accent)
                            .opacity(hideAmounts ? 0 : 1)
                            .accessibilityLabel("Limite utilizado")
                            .accessibilityValue(hideAmounts ? "Valor oculto" : Money.format(card.usedLimitCents))
                        HStack(alignment: .top) {
                            Text("Limite total\n\(hideAmounts ? "••••" : Money.format(card.limitCents))")
                            Spacer()
                            Text("Fecha \(card.closingDay) • Vence \(card.dueDay)")
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Color.primary).padding(20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: LedgerTheme.cornerRadius))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 4))
                .swipeActions(allowsFullSwipe: false) {
                    Button("Excluir", role: .destructive) { deleting = card }.tint(.red)
                }
            }
        }
        .ledgerListScreen("Cartões")
        .navigationDestination(for: UUID.self) { id in
            if let card = cards.first(where: { $0.id == id }) {
                CreditCardDetailView(card: card)
            } else {
                ContentUnavailableView("Cartão não encontrado", systemImage: "creditcard")
            }
        }
        .toolbar { LedgerToolbarButton("Adicionar cartão", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { CardFormView() }
        .confirmationDialog("Excluir cartão?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Excluir cartão e compras", role: .destructive) {
                if let deleting {
                    do { try CreditCardViewModel().delete(context: context, card: deleting) }
                    catch { self.error = error.localizedDescription }
                }
                deleting = nil
            }
        } message: { Text(CreditCardViewModel.deletionExplanation) }
        .financeError($error)
    }
}

struct CardFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var card: CreditCard? = nil
    @State private var name = ""
    @State private var limit = ""
    @State private var closingDay = 25
    @State private var dueDay = 5
    @State private var error: String?
    @State private var confirmingDelete = false
    private enum Field: Hashable { case name, limit }
    @FocusState private var focusedField: Field?
    var body: some View {
        NavigationStack {
            Form {
                Section("Cartão") {
                    TextField("Nome", text: $name).focused($focusedField, equals: .name)
                        .submitLabel(.done).onSubmit { focusedField = nil }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Limite total").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("R$").foregroundStyle(.secondary)
                            TextField("0,00", text: $limit.bankCurrency).keyboardType(.numberPad)
                                .focused($focusedField, equals: .limit).monospacedDigit()
                                .accessibilityLabel("Limite total em reais")
                        }.font(.title2)
                    }.padding(.vertical, 6)
                    Picker("Dia de fechamento", selection: $closingDay) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Dia de vencimento", selection: $dueDay) {
                        ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                    }
                }
                Section {
                    Text("Em meses curtos, usamos o último dia disponível. Se o vencimento for anterior ou igual ao fechamento, ele ocorre no mês seguinte.")
                    if card != nil {
                        Text("Alterações de dias valem para novas compras e projeções de assinaturas. Parcelas já lançadas mantêm as datas originais.")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if card != nil {
                    Section {
                        Button("Excluir cartão", role: .destructive) { confirmingDelete = true }.foregroundStyle(.red)
                    } footer: { Text(CreditCardViewModel.deletionExplanation) }
                }
            }
            .ledgerFormScreen(card == nil ? "Novo cartão" : "Editar cartão")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    LedgerToolbarButton("Fechar teclado", systemImage: "checkmark") { focusedField = nil }
                }
                ToolbarItem(placement: .cancellationAction) { LedgerToolbarButton("Cancelar", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    LedgerToolbarButton("Salvar", systemImage: "checkmark") {
                        do {
                            try CreditCardViewModel().save(context: context, card: card, name: name,
                                                          limitText: limit, closingDay: closingDay, dueDay: dueDay)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .onAppear {
                if let card { name = card.name; limit = Money.input(card.limitCents); closingDay = card.closingDay; dueDay = card.dueDay }
            }
            .financeError($error)
            .confirmationDialog("Excluir cartão?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Excluir cartão e compras", role: .destructive) {
                    guard let card else { return }
                    do { try CreditCardViewModel().delete(context: context, card: card); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text(CreditCardViewModel.deletionExplanation) }
        }
    }
}
