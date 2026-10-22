import SwiftUI
import SwiftData

struct CreditCardsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @State private var showAdd = false
    @State private var error: String?
    var body: some View {
        List {
            if cards.isEmpty {
                ContentUnavailableView("Seus cartões", systemImage: "creditcard",
                                       description: Text("Cadastre um cartão para acompanhar limites, parcelas e faturas."))
            }
            ForEach(cards) { card in
                NavigationLink { CreditCardDetailView(card: card) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(card.name, systemImage: "creditcard.fill").font(.headline)
                        Text("Disponível: \(Money.format(card.availableLimitCents))").font(.subheadline)
                        ProgressView(value: min(Double(card.usedLimitCents), Double(card.limitCents)),
                                     total: Double(max(1, card.limitCents)))
                            .accessibilityLabel("Limite utilizado")
                            .accessibilityValue(Money.format(card.usedLimitCents))
                        Text("Fecha dia \(card.closingDay) • Vence dia \(card.dueDay)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Excluir", role: .destructive) {
                        do { try CreditCardViewModel().delete(context: context, card: card) }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cartões")
        .toolbar { Button("Adicionar cartão", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { CardFormView() }
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
    var body: some View {
        NavigationStack {
            Form {
                Section("Cartão") {
                    TextField("Nome", text: $name)
                    TextField("Limite (R$): 5.000,00", text: $limit).keyboardType(.decimalPad)
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
            }
            .navigationTitle(card == nil ? "Novo cartão" : "Editar cartão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
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
        }
    }
}
