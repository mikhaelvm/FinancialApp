import SwiftUI
import SwiftData
import AppIntents

struct LedgerSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("reminders.enabled") private var enabled = false
    @AppStorage("reminders.daysBefore") private var daysBefore = 1
    @AppStorage("reminders.hour") private var hour = 9
    @AppStorage("reminders.minute") private var minute = 0
    @AppStorage("reminders.showAmounts") private var showAmounts = false
    @State private var notifications = NotificationService.shared
    @AppStorage("ledger.appearance") private var appearance = "system"
    @AppStorage("ledger.accent") private var accent = "teal"
    @AppStorage("ledger.hideAmounts") private var hideAmounts = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SymbolTile(symbol: "square.3.layers.3d")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ledger").font(.title2.bold())
                        Text("Finanças pessoais").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
            }
            Section("Personalização") {
                Picker("Aparência", selection: $appearance) {
                    ForEach(LedgerAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Cor de destaque", selection: $accent) {
                    ForEach(LedgerAccent.allCases) { value in
                        Label { Text(value.title) } icon: { Image(systemName: "circle.fill").foregroundStyle(value.color) }.tag(value.rawValue)
                    }
                }
                Toggle("Ocultar valores no resumo e listas", isOn: $hideAmounts)
            }
            Section("Organização e dados") {
                NavigationLink { BudgetSettingsView() } label: { Label("Orçamento e meta de reserva", systemImage: "target") }
                NavigationLink { CategoryManagementView() } label: { Label("Categorias", systemImage: "tag") }
                NavigationLink { ReportsView() } label: { Label("Relatórios", systemImage: "chart.bar.xaxis") }
                NavigationLink { DataManagementView() } label: { Label("Dados, backup e extratos", systemImage: "externaldrive") }
            }
            Section {
                Label("Acesso rápido na Tela de Início", systemImage: "square.grid.2x2")
                Text("Mantenha uma área vazia da Tela de Início pressionada, toque em Editar e adicione o widget Ledger. Também há controles para a Tela Bloqueada. Os widgets abrem receitas, despesas e Agenda, sem expor valores financeiros.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Widgets") }
            Section {
                Toggle("Lembretes de pagamento", isOn: Binding(get: { enabled }, set: { value in
                    if value { Task { await notifications.requestPermission(context: context) } }
                    else { enabled = false; notifications.refresh(context: context) }
                }))
                if enabled && notifications.canNotify {
                    Picker("Avisar antes", selection: $daysBefore) {
                        Text("Somente no dia").tag(0)
                        Text("1 dia antes e no dia").tag(1)
                        Text("3 dias antes e no dia").tag(3)
                        Text("7 dias antes e no dia").tag(7)
                    }
                    DatePicker("Horário", selection: Binding(get: {
                        FinanceDate.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
                    }, set: { value in
                        hour = FinanceDate.calendar.component(.hour, from: value)
                        minute = FinanceDate.calendar.component(.minute, from: value)
                    }), displayedComponents: .hourAndMinute)
                    Toggle("Mostrar valores nos alertas", isOn: $showAmounts)
                    LabeledContent("Lembretes agendados", value: "\(notifications.scheduledCount)")
                    if let date = notifications.coveredUntil {
                        LabeledContent("Último alerta da fila", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if notifications.authorization == .denied {
                    Label("Notificações desativadas no iOS", systemImage: "bell.slash")
                    Button("Abrir Ajustes do Ledger") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                if let error = notifications.lastError { Text(error).foregroundStyle(.orange).font(.footnote) }
            } header: { Text("Faturas, contas e recorrências") } footer: {
                Text("Os alertas são locais e funcionam com o app fechado depois de agendados. Mantemos os 60 lembretes mais próximos, dentro de 60 dias. Abra o Ledger periodicamente para renovar a fila. Foco e permissões do iOS podem silenciar alertas.")
            }
            Section {
                ShortcutsLink()
                SiriTipView(intent: LedgerSummaryIntent())
                Label("Qual é meu saldo no Ledger?", systemImage: "waveform")
                Label("Registrar gasto no Ledger", systemImage: "minus.circle")
                Label("Registrar receita no Ledger", systemImage: "plus.circle")
                Label("Ver pagamentos no Ledger", systemImage: "calendar")
                Label("Buscar no Ledger", systemImage: "magnifyingglass")
            } header: { Text("Atalhos e Siri") } footer: {
                Text("No app Atalhos, procure Ledger para combinar ações e criar automações. Valores são em reais. Registros por voz exigem o aparelho desbloqueado. No iOS 27, builds com SDK 27 também oferecem busca integrada à Siri AI; as ações financeiras usam App Shortcuts.")
            }
            Section("Sobre") {
                LabeledContent("Versão", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2")
                Text("Seus registros ficam neste dispositivo. Registrar um pagamento no Ledger não movimenta dinheiro no banco.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
        .onAppear { notifications.refresh(context: context) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { notifications.refresh(context: context) } }
        .onChange(of: daysBefore) { _, _ in notifications.refresh(context: context) }
        .onChange(of: hour) { _, _ in notifications.refresh(context: context) }
        .onChange(of: minute) { _, _ in notifications.refresh(context: context) }
        .onChange(of: showAmounts) { _, _ in notifications.refresh(context: context) }
        .onChange(of: accent) { _, _ in LedgerThemeState.shared.refresh() }
    }
}
