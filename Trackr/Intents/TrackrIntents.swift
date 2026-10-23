import AppIntents
import Foundation
import SwiftData

enum TrackrIntentSupport {
    static func cents(from value: Double) throws -> Int64 {
        guard value.isFinite, value > 0, value <= Double(Money.maximumCents) / 100 else {
            throw FinanceError.invalid("Informe um valor positivo em reais.")
        }
        let cents = Int64((value * 100).rounded())
        guard cents > 0 else { throw FinanceError.invalid("O valor mínimo é um centavo.") }
        return cents
    }
    @MainActor static func context() throws -> ModelContext {
        try AppLockService.shared.requireUnlockedAccess()
        let context = try Persistence.sharedContainer().mainContext
        try Persistence.seed(context: context)
        try RecurrenceEngine().synchronize(context: context)
        NotificationService.shared.refresh(context: context)
        WidgetSnapshotService.refresh(context: context)
        return context
    }
    @MainActor static func record(title: String, amount: Double, date: Date?, kind: TransactionKind,
                                  category: TrackrCategoryEntity?) throws -> String {
        let context = try Self.context()
        let cents = try Self.cents(from: amount)
        let categories = try context.fetch(FetchDescriptor<Category>())
        try TransactionViewModel().saveCash(context: context, title: title, amountText: Money.input(cents), kind: kind,
                                            date: date ?? .now, category: categories.first { $0.id == category?.id })
        NotificationService.shared.refresh(context: context)
        WidgetSnapshotService.refresh(context: context)
        return "\(kind.title) de \(Money.format(cents)) registrada: \(title)."
    }
}

struct TrackrSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Consultar resumo financeiro"
    static var description = IntentDescription("Consulta o saldo e os compromissos do mês no Trackr.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = try TrackrIntentSupport.context()
        let snapshot = DashboardViewModel().snapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()),
                                                      cards: try context.fetch(FetchDescriptor<CreditCard>()),
                                                      subscriptions: try context.fetch(FetchDescriptor<Subscription>()),
                                                      payments: try context.fetch(FetchDescriptor<InvoicePayment>()), month: .now,
                                                      scheduled: try context.fetch(FetchDescriptor<ScheduledPayment>()))
        let message = "Seu saldo no Trackr é \(Money.format(snapshot.balance)). Após os compromissos do mês, a previsão é \(Money.format(snapshot.projectedBalance))."
        return .result(value: message, dialog: "\(message)")
    }
}

struct AddTrackrExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto"
    static var description = IntentDescription("Registra uma despesa já realizada na conta. Não efetua pagamentos bancários.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Descrição") var title: String
    @Parameter(title: "Valor em reais") var amount: Double
    @Parameter(title: "Categoria") var category: TrackrCategoryEntity?
    @Parameter(title: "Data (opcional)") var date: Date?
    static var parameterSummary: some ParameterSummary { Summary("Registrar \(\.$title) de R$ \(\.$amount)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try TrackrIntentSupport.record(title: title, amount: amount, date: date, kind: .expense, category: category)
        return .result(dialog: "\(message)")
    }
}

struct AddTrackrIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar receita"
    static var description = IntentDescription("Registra um valor recebido na conta do Trackr.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Descrição") var title: String
    @Parameter(title: "Valor em reais") var amount: Double
    @Parameter(title: "Categoria") var category: TrackrCategoryEntity?
    @Parameter(title: "Data (opcional)") var date: Date?
    static var parameterSummary: some ParameterSummary { Summary("Receber \(\.$title) de R$ \(\.$amount)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try TrackrIntentSupport.record(title: title, amount: amount, date: date, kind: .income, category: category)
        return .result(dialog: "\(message)")
    }
}

struct ScheduleTrackrPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "Agendar conta a pagar"
    static var description = IntentDescription("Adiciona uma conta à Agenda, sem descontar o saldo até o pagamento ser registrado.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Conta") var title: String
    @Parameter(title: "Valor em reais") var amount: Double
    @Parameter(title: "Vencimento") var dueDate: Date
    @Parameter(title: "Categoria") var category: TrackrCategoryEntity?
    static var parameterSummary: some ParameterSummary { Summary("Agendar \(\.$title) de R$ \(\.$amount) para \(\.$dueDate)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try TrackrIntentSupport.context()
        let cents = try TrackrIntentSupport.cents(from: amount)
        try ScheduledPaymentViewModel().save(context: context, title: title, amountText: Money.input(cents),
                                              dueDate: dueDate, notes: "", categoryID: category?.id)
        NotificationService.shared.refresh(context: context)
        TrackrRouter.shared.openPayments()
        return .result(dialog: "A conta \(title) foi agendada no Trackr.")
    }
}

struct OpenTrackrAgendaIntent: AppIntent {
    static var title: LocalizedStringResource = "Ver pagamentos"
    static var description = IntentDescription("Abre faturas, recorrências e contas a pagar no Trackr.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        TrackrRouter.shared.openPayments()
        return .result()
    }
}

struct SearchTrackrIntent: AppIntent {
    static var title: LocalizedStringResource = "Buscar no extrato"
    static var description = IntentDescription("Pesquisa lançamentos da conta no extrato do Trackr.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Buscar") var term: String
    static var parameterSummary: some ParameterSummary { Summary("Buscar \(\.$term) no Trackr") }
    @MainActor func perform() async throws -> some IntentResult {
        TrackrRouter.shared.search(term)
        return .result()
    }
}

struct OpenTrackrTransactionIntent: OpenIntent {
    static var title: LocalizedStringResource = "Abrir lançamento"
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Lançamento") var target: TrackrTransactionEntity
    @MainActor func perform() async throws -> some IntentResult {
        TrackrRouter.shared.search(target.title)
        TrackrRouter.shared.selectedTransactionID = target.id
        return .result()
    }
}

struct TrackrShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TrackrSummaryIntent(), phrases: ["Qual é meu saldo no \(.applicationName)", "Resumo financeiro no \(.applicationName)"],
                    shortTitle: "Meu saldo", systemImageName: "wallet.bifold")
        AppShortcut(intent: AddTrackrExpenseIntent(), phrases: ["Registrar gasto no \(.applicationName)"],
                    shortTitle: "Registrar gasto", systemImageName: "minus.circle")
        AppShortcut(intent: AddTrackrIncomeIntent(), phrases: ["Registrar receita no \(.applicationName)"],
                    shortTitle: "Registrar receita", systemImageName: "plus.circle")
        AppShortcut(intent: ScheduleTrackrPaymentIntent(), phrases: ["Agendar conta no \(.applicationName)"],
                    shortTitle: "Agendar conta", systemImageName: "calendar.badge.plus")
        AppShortcut(intent: OpenTrackrAgendaIntent(), phrases: ["Ver pagamentos no \(.applicationName)"],
                    shortTitle: "Ver pagamentos", systemImageName: "calendar")
        AppShortcut(intent: SearchTrackrIntent(), phrases: ["Buscar no \(.applicationName)"],
                    shortTitle: "Buscar no extrato", systemImageName: "magnifyingglass")
    }
}
