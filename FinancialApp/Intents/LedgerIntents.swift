import AppIntents
import Foundation
import SwiftData

enum LedgerIntentSupport {
    static func cents(from value: Double) throws -> Int64 {
        guard value.isFinite, value > 0, value <= Double(Money.maximumCents) / 100 else {
            throw FinanceError.invalid("Informe um valor positivo em reais.")
        }
        let cents = Int64((value * 100).rounded())
        guard cents > 0 else { throw FinanceError.invalid("O valor mínimo é um centavo.") }
        return cents
    }
    @MainActor static func context() throws -> ModelContext {
        let context = try Persistence.sharedContainer().mainContext
        try Persistence.seed(context: context)
        try RecurrenceEngine().synchronize(context: context)
        NotificationService.shared.refresh(context: context)
        WidgetSnapshotService.refresh(context: context)
        return context
    }
    @MainActor static func record(title: String, amount: Double, date: Date?, kind: TransactionKind,
                                  category: LedgerCategoryEntity?) throws -> String {
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

struct LedgerSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Consultar resumo financeiro"
    static var description = IntentDescription("Consulta o saldo e os compromissos do mês no Ledger.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = try LedgerIntentSupport.context()
        let snapshot = DashboardViewModel().snapshot(transactions: try context.fetch(FetchDescriptor<Transaction>()),
                                                      cards: try context.fetch(FetchDescriptor<CreditCard>()),
                                                      subscriptions: try context.fetch(FetchDescriptor<Subscription>()),
                                                      payments: try context.fetch(FetchDescriptor<InvoicePayment>()), month: .now,
                                                      scheduled: try context.fetch(FetchDescriptor<ScheduledPayment>()))
        let message = "Seu saldo no Ledger é \(Money.format(snapshot.balance)). Após os compromissos do mês, a previsão é \(Money.format(snapshot.projectedBalance))."
        return .result(value: message, dialog: "\(message)")
    }
}

struct AddLedgerExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto"
    static var description = IntentDescription("Registra uma despesa já realizada na conta. Não efetua pagamentos bancários.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Descrição") var title: String
    @Parameter(title: "Valor em reais") var amount: Double
    @Parameter(title: "Categoria") var category: LedgerCategoryEntity?
    @Parameter(title: "Data (opcional)") var date: Date?
    static var parameterSummary: some ParameterSummary { Summary("Registrar \(\.$title) de R$ \(\.$amount)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try LedgerIntentSupport.record(title: title, amount: amount, date: date, kind: .expense, category: category)
        return .result(dialog: "\(message)")
    }
}

struct AddLedgerIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar receita"
    static var description = IntentDescription("Registra um valor recebido na conta do Ledger.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Descrição") var title: String
    @Parameter(title: "Valor em reais") var amount: Double
    @Parameter(title: "Categoria") var category: LedgerCategoryEntity?
    @Parameter(title: "Data (opcional)") var date: Date?
    static var parameterSummary: some ParameterSummary { Summary("Receber \(\.$title) de R$ \(\.$amount)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try LedgerIntentSupport.record(title: title, amount: amount, date: date, kind: .income, category: category)
        return .result(dialog: "\(message)")
    }
}

struct ScheduleLedgerPaymentIntent: AppIntent {
    static var title: LocalizedStringResource = "Agendar conta a pagar"
    static var description = IntentDescription("Adiciona uma conta à Agenda, sem descontar o saldo até o pagamento ser registrado.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Conta") var title: String
    @Parameter(title: "Valor em reais") var amount: Double
    @Parameter(title: "Vencimento") var dueDate: Date
    @Parameter(title: "Categoria") var category: LedgerCategoryEntity?
    static var parameterSummary: some ParameterSummary { Summary("Agendar \(\.$title) de R$ \(\.$amount) para \(\.$dueDate)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try LedgerIntentSupport.context()
        let cents = try LedgerIntentSupport.cents(from: amount)
        try ScheduledPaymentViewModel().save(context: context, title: title, amountText: Money.input(cents),
                                              dueDate: dueDate, notes: "", categoryID: category?.id)
        NotificationService.shared.refresh(context: context)
        LedgerRouter.shared.selectedTab = .agenda
        return .result(dialog: "A conta \(title) foi agendada no Ledger.")
    }
}

struct OpenLedgerAgendaIntent: AppIntent {
    static var title: LocalizedStringResource = "Ver pagamentos"
    static var description = IntentDescription("Abre faturas, recorrências e contas a pagar no Ledger.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        LedgerRouter.shared.selectedTab = .agenda
        return .result()
    }
}

struct SearchLedgerIntent: AppIntent {
    static var title: LocalizedStringResource = "Buscar no extrato"
    static var description = IntentDescription("Pesquisa lançamentos da conta no extrato do Ledger.")
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Buscar") var term: String
    static var parameterSummary: some ParameterSummary { Summary("Buscar \(\.$term) no Ledger") }
    @MainActor func perform() async throws -> some IntentResult {
        LedgerRouter.shared.search(term)
        return .result()
    }
}

struct OpenLedgerTransactionIntent: OpenIntent {
    static var title: LocalizedStringResource = "Abrir lançamento"
    static var openAppWhenRun = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    @Parameter(title: "Lançamento") var target: LedgerTransactionEntity
    @MainActor func perform() async throws -> some IntentResult {
        LedgerRouter.shared.search(target.title)
        LedgerRouter.shared.selectedTransactionID = target.id
        return .result()
    }
}

struct LedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LedgerSummaryIntent(), phrases: ["Qual é meu saldo no \(.applicationName)", "Resumo financeiro no \(.applicationName)"],
                    shortTitle: "Meu saldo", systemImageName: "wallet.bifold")
        AppShortcut(intent: AddLedgerExpenseIntent(), phrases: ["Registrar gasto no \(.applicationName)"],
                    shortTitle: "Registrar gasto", systemImageName: "minus.circle")
        AppShortcut(intent: AddLedgerIncomeIntent(), phrases: ["Registrar receita no \(.applicationName)"],
                    shortTitle: "Registrar receita", systemImageName: "plus.circle")
        AppShortcut(intent: ScheduleLedgerPaymentIntent(), phrases: ["Agendar conta no \(.applicationName)"],
                    shortTitle: "Agendar conta", systemImageName: "calendar.badge.plus")
        AppShortcut(intent: OpenLedgerAgendaIntent(), phrases: ["Ver pagamentos no \(.applicationName)"],
                    shortTitle: "Ver pagamentos", systemImageName: "calendar")
        AppShortcut(intent: SearchLedgerIntent(), phrases: ["Buscar no \(.applicationName)"],
                    shortTitle: "Buscar no extrato", systemImageName: "magnifyingglass")
    }
}
