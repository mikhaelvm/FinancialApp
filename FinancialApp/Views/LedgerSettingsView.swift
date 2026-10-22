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
                NavigationLink {
                    LedgerAccentSettingsView()
                } label: {
                    HStack {
                        Text("Cor de destaque")
                        Spacer()
                        Circle().fill(selectedAccent.color).frame(width: 18, height: 18)
                        Text(selectedAccent.title).foregroundStyle(.secondary)
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
                Text("Adicione o widget Ledger pela edição da Tela de Início para ver saldo, entradas, saídas e próximos pagamentos. Os valores respeitam a opção de ocultação. A atualização ocorre ao usar o app e conforme a disponibilidade do iOS.")
                    .font(.footnote).foregroundStyle(.secondary)
                Label("Central de Controle", systemImage: "switch.2")
                Text("No iOS 18 ou posterior, abra a Central de Controle, mantenha pressionado, toque em Adicionar um Controle e procure Ledger. Há controles para nova despesa, nova receita, resumo e Agenda.").font(.footnote).foregroundStyle(.secondary)
                if !LedgerWidgetStore.isAvailable {
                    Text("O compartilhamento com widgets não está disponível nesta instalação. A assinatura precisa autorizar o App Group do Ledger.").font(.footnote).foregroundStyle(.orange)
                }
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
        .tint(selectedAccent.color)
        .preferredColorScheme((LedgerAppearance(rawValue: appearance) ?? .system).colorScheme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
        .onAppear { notifications.refresh(context: context) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { notifications.refresh(context: context) } }
        .onChange(of: daysBefore) { _, _ in notifications.refresh(context: context) }
        .onChange(of: hour) { _, _ in notifications.refresh(context: context) }
        .onChange(of: minute) { _, _ in notifications.refresh(context: context) }
        .onChange(of: showAmounts) { _, _ in notifications.refresh(context: context) }
        .onChange(of: accent) { _, _ in LedgerThemeState.shared.refresh() }
        .onChange(of: hideAmounts) { _, _ in WidgetSnapshotService.refresh(context: context) }
    }
    private var selectedAccent: LedgerAccent { LedgerAccent(rawValue: accent) ?? .teal }
}

struct LedgerAccentSettingsView: View {
    @AppStorage("ledger.accent") private var accent = "teal"
    var body: some View {
        List(LedgerAccent.allCases) { value in
            Button {
                accent = value.rawValue
                LedgerThemeState.shared.refresh()
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(value.color).frame(width: 26, height: 26)
                    Text(value.title).foregroundStyle(.primary)
                    Spacer()
                    if accent == value.rawValue { Image(systemName: "checkmark").foregroundStyle(value.color) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(accent == value.rawValue ? .isSelected : [])
        }
        .navigationTitle("Cor de destaque")
        .navigationBarTitleDisplayMode(.inline)
        .tint((LedgerAccent(rawValue: accent) ?? .teal).color)
    }
}
