import SwiftUI
import SwiftData

private enum AgendaFilter: String, CaseIterable, Identifiable {
    case upcoming = "A vencer", overdue = "Atrasados", paid = "Pagos", dismissed = "Dispensados"
    var id: String { rawValue }
}

struct PaymentAgendaView: View {
    @Environment(\.modelContext) private var context
    @Environment(TrackrRouter.self) private var router
    @Query private var cards: [CreditCard]
    @Query private var subscriptions: [Subscription]
    @Query(sort: \ScheduledPayment.dueDate) private var scheduled: [ScheduledPayment]
    @State private var filter: AgendaFilter = .upcoming
    @State private var showAdd = false
    @State private var showSettings = false
    @State private var editing: ScheduledPayment?
    @State private var confirming: ScheduledPayment?
    @State private var deleting: ScheduledPayment?
    @State private var dismissing: PaymentCommitment?
    @AppStorage("trackr.dismissedPayments") private var dismissedIDs = ""
    @State private var error: String?

    private var allCommitments: [PaymentCommitment] {
        let horizon = FinanceDate.calendar.date(byAdding: .day, value: 60, to: FinanceDate.day(.now))!
        return PaymentPlanner().commitments(cards: cards, subscriptions: subscriptions,
                                            scheduled: scheduled, through: horizon, includeDismissed: true)
    }
    private var dismissedSet: Set<String> { Set(dismissedIDs.split(separator: "\n").map(String.init)) }
    private var commitments: [PaymentCommitment] { allCommitments.filter { !dismissedSet.contains($0.id) } }
    private var filtered: [PaymentCommitment] {
        PaymentPlanner.agendaItems(commitments).filter { filter == .overdue ? $0.isOverdue() : !$0.isOverdue() }
    }
    private var dates: [Date] { Array(Set(filtered.map(\.dueDate))).sorted() }
    private var nextWeekCents: Int64 {
        let end = FinanceDate.calendar.date(byAdding: .day, value: 7, to: FinanceDate.day(.now))!
        return commitments.filter { !$0.isOverdue() && $0.dueDate <= end && $0.affectsCashFlow }
            .reduce(Int64(0)) { $0 + $1.amountCents }
    }

    var body: some View {
        TrackrAdaptiveSections(primaryFraction: 0.38) {
            PaymentsSectionPicker()
            Section {
                TrackrSummaryHeader(eyebrow: "Saídas previstas • próximos 7 dias", title: Money.format(nextWeekCents),
                                    subtitle: "Faturas, contas e recorrências.",
                                    symbol: "calendar.badge.clock")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section("Lembretes de vencimento") {
                Button("Configurar notificações e Siri") { showSettings = true }
            }
        } secondary: {
            Section {
                Picker("Exibir", selection: $filter) {
                    ForEach(AgendaFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            if filter == .dismissed {
                Section {
                    let items = allCommitments.filter { dismissedSet.contains($0.id) && PaymentDismissalStore.isVisible(dueDate: $0.dueDate) }
                    if items.isEmpty { Text("Nenhum compromisso dispensado.").foregroundStyle(.secondary) }
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            PaymentCommitmentRow(item: item)
                            Button("Voltar à Agenda", systemImage: "arrow.uturn.backward") {
                                PaymentDismissalStore.set(item.id, dismissed: false)
                            }
                        }
                    }
                }
            } else if filter == .paid {
                Section {
                    if !scheduled.contains(where: \.isPaid) {
                        ContentUnavailableView("Tudo em seu tempo", systemImage: "checkmark.circle",
                                               description: Text("Contas agendadas já pagas."))
                    }
                    ForEach(scheduled.filter(\.isPaid)) { payment in
                        HStack {
                            SymbolTile(symbol: "checkmark.circle.fill")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(payment.title).font(.headline)
                                Text("Pagamento registrado no extrato").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(payment.amountCents)).font(.subheadline.weight(.semibold))
                            Menu {
                                Button("Excluir pagamento", role: .destructive) { deleting = payment }
                            } label: { Image(systemName: "ellipsis.circle").padding(6) }
                                .accessibilityLabel("Ações do pagamento \(payment.title)")
                        }
                        .swipeActions {
                            Button("Excluir", role: .destructive) { deleting = payment }.tint(.red)
                        }
                        .contextMenu {
                            Button("Excluir pagamento", role: .destructive) { deleting = payment }
                        }
                    }
                }
            } else if filtered.isEmpty {
                ContentUnavailableView(filter == .overdue ? "Nenhum atraso" : "Agenda tranquila", systemImage: "calendar.badge.checkmark",
                                       description: Text(filter == .overdue ? "Seus compromissos estão em dia." : "Adicione contas ou recorrências para começar."))
            } else {
                ForEach(dates, id: \.self) { date in
                    Section(dateTitle(date)) {
                        ForEach(filtered.filter { $0.dueDate == date }) { item in
                            Button { open(item) } label: { PaymentCommitmentRow(item: item) }.buttonStyle(.plain)
                                .contextMenu {
                                    if item.kind != .subscription {
                                        Button("Dispensar", systemImage: "minus.circle") { dismissing = item }
                                    }
                                }
                                .swipeActions(allowsFullSwipe: false) {
                                    if item.kind != .subscription {
                                        Button("Dispensar", systemImage: "minus.circle") { dismissing = item }.tint(.gray)
                                    }
                                    if item.kind == .scheduled, let payment = scheduled.first(where: { $0.id == item.sourceID }) {
                                        Button("Pago", systemImage: "checkmark") { confirming = payment }.tint(TrackrTheme.accent)
                                        Button("Excluir", role: .destructive) { deleting = payment }.tint(.red)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .trackrListScreen("Pagamentos")
        .toolbar { TrackrToolbarButton("Agendar pagamento", systemImage: "plus") { showAdd = true } }
        .sheet(isPresented: $showAdd) { ScheduledPaymentForm() }
        .sheet(item: $editing) { ScheduledPaymentForm(payment: $0) }
        .sheet(isPresented: $showSettings) { NavigationStack { TrackrSettingsView() } }
        .confirmationDialog("Dispensar este compromisso?", isPresented: Binding(get: { dismissing != nil }, set: { if !$0 { dismissing = nil } }), titleVisibility: .visible) {
            Button("Dispensar sem registrar pagamento") {
                if let dismissing { PaymentDismissalStore.set(dismissing.id, dismissed: true) }
                dismissing = nil
            }
        } message: {
            Text("Retira da Agenda e dos alertas, sem débito. Compras e limite são mantidos. Reative em Dispensados.")
        }
        .confirmationDialog("Confirmar pagamento?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible) {
            Button("Registrar pagamento") {
                if let confirming { perform { try ScheduledPaymentViewModel().pay(confirming, context: context) } }
                confirming = nil
            }
        } message: { Text("Registra uma despesa hoje. Confirme se já pagou.") }
        .confirmationDialog("Excluir conta agendada?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(deleting?.isPaid == true ? "Excluir somente o agendamento" : "Excluir", role: .destructive) {
                if let deleting { perform { try ScheduledPaymentViewModel().delete(deleting, context: context) } }
                deleting = nil
            }
            if deleting?.isPaid == true {
                Button("Excluir também a despesa no extrato", role: .destructive) {
                    if let deleting { perform { try ScheduledPaymentViewModel().delete(deleting, context: context, removeRecordedExpense: true) } }
                    deleting = nil
                }
            }
        } message: {
            Text(deleting?.isPaid == true ? "Mantenha a despesa no Extrato ou exclua os dois registros." : "Remove esta conta e seus alertas.")
        }
        .financeError($error)
    }

    private func dateTitle(_ date: Date) -> String {
        if FinanceDate.calendar.isDateInToday(date) { return "Hoje" }
        if FinanceDate.calendar.isDateInTomorrow(date) { return "Amanhã" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(Locale(identifier: "pt_BR")))
    }
    private func open(_ item: PaymentCommitment) {
        if item.kind == .scheduled { editing = scheduled.first { $0.id == item.sourceID } }
        else { router.openReminder(kind: item.kind.rawValue, cardID: item.sourceID.uuidString) }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

struct ScheduledPaymentForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    var payment: ScheduledPayment? = nil
    @State private var title = ""
    @State private var amount = ""
    @State private var dueDate = Date.now
    @State private var notes = ""
    @State private var categoryID: UUID?
    @State private var error: String?
    @State private var confirmPayment = false
    @State private var confirmDelete = false
    private enum Field: Hashable { case title, amount, notes }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section("Sua conta") {
                    TextField("Ex.: Conta de energia", text: $title).focused($focusedField, equals: .title)
                        .submitLabel(.done).onSubmit { focusedField = nil }
                    HStack {
                        Text("R$").foregroundStyle(.secondary)
                        CurrencyTextField(text: $amount).accessibilityLabel("Valor em reais")
                    }
                    DatePicker("Vencimento", selection: $dueDate, displayedComponents: .date)
                    Picker("Categoria", selection: $categoryID) {
                        Text("Sem categoria").tag(nil as UUID?)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("Observações (opcional)", text: $notes, axis: .vertical).focused($focusedField, equals: .notes)
                }
                Section {
                    Label("Seu saldo só muda ao registrar o pagamento.", systemImage: "info.circle")
                    Text("Para contas que se repetem, crie uma recorrência.")
                }.font(.footnote).foregroundStyle(.secondary)
                if payment != nil {
                    Section { Button("Já paguei esta conta", systemImage: "checkmark.circle.fill") { confirmPayment = true } }
                    Section { Button("Excluir agendamento", role: .destructive) { confirmDelete = true }.foregroundStyle(.red) }
                }
            }
            .trackrFormScreen(payment == nil ? "Agendar conta" : "Editar conta")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    TrackrToolbarButton("Fechar teclado", systemImage: "checkmark") { focusedField = nil }
                }
                ToolbarItem(placement: .cancellationAction) { TrackrToolbarButton("Cancelar", systemImage: "xmark") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    TrackrToolbarButton("Salvar", systemImage: "checkmark") {
                        do {
                            try ScheduledPaymentViewModel().save(context: context, payment: payment, title: title,
                                                                 amountText: amount, dueDate: dueDate, notes: notes, categoryID: categoryID)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold)
                }
            }
            .onAppear {
                if let payment {
                    title = payment.title; amount = Money.input(payment.amountCents); dueDate = payment.dueDate
                    notes = payment.notes; categoryID = payment.categoryID
                }
            }
            .confirmationDialog("O pagamento já foi realizado?", isPresented: $confirmPayment, titleVisibility: .visible) {
                Button("Registrar como pago") {
                    guard let payment else { return }
                    do { try ScheduledPaymentViewModel().pay(payment, context: context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("Desconta o valor salvo. Salve alterações antes de pagar.") }
            .financeError($error)
            .confirmationDialog("Excluir agendamento?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    guard let payment else { return }
                    do { try ScheduledPaymentViewModel().delete(payment, context: context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }
}
