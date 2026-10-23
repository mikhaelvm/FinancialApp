import SwiftUI
import SwiftData

struct CreditCardsView: View {
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false
    @Environment(\.modelContext) private var context
    @Environment(TrackrRouter.self) private var router
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showAdd = false
    @State private var deleting: CreditCard?
    @State private var error: String?
    var body: some View {
        GeometryReader { geometry in
            if UIDevice.current.userInterfaceIdiom == .pad,
               geometry.size.width >= 950, geometry.size.width > geometry.size.height,
               !typeSize.isAccessibilitySize {
                List {
                    if cards.isEmpty { emptyState.listRowBackground(Color.clear) }
                    ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { index in
                        HStack(alignment: .top, spacing: 24) {
                            gridCard(cards[index])
                            if index + 1 < cards.count { gridCard(cards[index + 1]) }
                            else { Color.clear.frame(maxWidth: .infinity) }
                        }
                        .listRowInsets(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 24))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain).frame(maxWidth: 1400).frame(maxWidth: .infinity)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                List {
                    if cards.isEmpty { emptyState }
                    ForEach(cards) { card in
                        Section {
                            cardButton(card)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20))
                                .swipeActions(allowsFullSwipe: false) {
                                    Button("Excluir", role: .destructive) { deleting = card }.tint(.red)
                                }
                        }
                    }
                }
            }
        }
        .trackrListScreen("Cartões")
        .listSectionSpacing(16)
        .navigationDestination(for: UUID.self) { id in
            if let card = cards.first(where: { $0.id == id }) {
                CreditCardDetailView(card: card)
            } else {
                ContentUnavailableView("Cartão não encontrado", systemImage: "creditcard")
            }
        }
        .toolbar { TrackrToolbarButton("Adicionar cartão", systemImage: "plus") { showAdd = true } }
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
    private func gridCard(_ card: CreditCard) -> some View {
        cardButton(card).padding(20).frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: TrackrTheme.cornerRadius))
            .contextMenu { Button("Excluir cartão", systemImage: "trash", role: .destructive) { deleting = card } }
    }

    private var emptyState: some View {
        ContentUnavailableView("Seus cartões", systemImage: "creditcard",
                               description: Text("Cadastre um cartão para acompanhar limites, parcelas e faturas."))
    }

    private func cardButton(_ card: CreditCard) -> some View {
        Button { router.cardPath.append(card.id) } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(card.name, systemImage: "creditcard.fill").font(.headline)
                    Spacer()
                    Image(systemName: "wave.3.right").accessibilityHidden(true)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Limite disponível").font(.caption).foregroundStyle(.secondary)
                        Text(hideAmounts ? "••••" : Money.format(card.availableLimitCents)).font(.title2.bold()).monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                ProgressView(value: min(Double(card.usedLimitCents), Double(card.limitCents)),
                             total: Double(max(1, card.limitCents)))
                    .tint(card.availableLimitCents == 0 ? .orange : TrackrTheme.accent)
                    .opacity(hideAmounts ? 0 : 1)
                    .accessibilityLabel("Limite utilizado")
                    .accessibilityValue(hideAmounts ? "Valor oculto" : Money.format(card.usedLimitCents))
                HStack(alignment: .top) {
                    Text("Limite total\n\(hideAmounts ? "••••" : Money.format(card.limitCents))")
                    Spacer()
                    Text("Fecha \(card.closingDay) • Vence \(card.dueDay)")
                }.font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abrir compras e faturas do cartão")
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
                            CurrencyTextField(text: $limit, textStyle: .title2)
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
                    Text("Meses curtos usam o último dia; fins de semana passam para segunda, sem feriados. Faturas existentes mantêm as datas.")
                    if card != nil {
                        Text("Novos dias valem para compras e previsões futuras.")
                    }
                }.font(.caption).foregroundStyle(.secondary)
                if card != nil {
                    Section {
                        Button("Excluir cartão", role: .destructive) { confirmingDelete = true }.foregroundStyle(.red)
                    } footer: { Text(CreditCardViewModel.deletionExplanation) }
                }
            }
            .trackrFormScreen(card == nil ? "Novo cartão" : "Editar cartão")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    TrackrToolbarButton("Fechar teclado", systemImage: "checkmark") { focusedField = nil }
                }
                ToolbarItem(placement: .cancellationAction) { TrackrToolbarButton("Cancelar", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    TrackrToolbarButton("Salvar", systemImage: "checkmark") {
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
