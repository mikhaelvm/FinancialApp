import SwiftUI
import SwiftData
import AppIntents

struct TrackrSettingsView: View {
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
    @State private var appLock = AppLockService.shared
    @AppStorage("trackr.appearance") private var appearance = "system"
    @AppStorage("trackr.accent") private var accent = "blue"
    @AppStorage("trackr.hideAmounts") private var hideAmounts = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { appLock.isEnabled }, set: { enabled in
                    Task { await appLock.setEnabled(enabled) }
                })) {
                    Label("Bloquear com \(appLock.methodName)", systemImage: appLock.symbol)
                }.disabled(appLock.isAuthenticating)
                if appLock.isAuthenticating { ProgressView("Confirmando identidade…") }
                if let message = appLock.errorMessage { Text(message).font(.footnote).foregroundStyle(.orange) }
            } header: { Text("Privacidade e segurança") } footer: {
                Text("Exige autenticação ao abrir o Trackr e ao retornar do segundo plano. O código do aparelho é uma alternativa do iOS. Com a proteção ativa, widgets e notificações usam informações discretas. A prévia no seletor de apps é ocultada.")
            }
            Section("Personalização") {
                Picker("Aparência", selection: $appearance) {
                    ForEach(TrackrAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                NavigationLink {
                    TrackrAccentSettingsView()
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
                    Toggle("Mostrar valores nos alertas", isOn: Binding(get: { showAmounts && !appLock.isEnabled }, set: { showAmounts = $0 }))
                        .disabled(appLock.isEnabled)
                    if appLock.isEnabled { Label("Conteúdo protegido pelo bloqueio", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary) }
                    LabeledContent("Lembretes agendados", value: "\(notifications.scheduledCount)")
                    if let date = notifications.coveredUntil {
                        LabeledContent("Último alerta da fila", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if notifications.authorization == .denied {
                    Label("Notificações desativadas no iOS", systemImage: "bell.slash")
                    Button("Abrir Ajustes do Trackr") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                if let error = notifications.lastError { Text(error).foregroundStyle(.orange).font(.footnote) }
            } header: { Text("Faturas, contas e recorrências") } footer: {
                Text("Os alertas são locais e funcionam com o app fechado depois de agendados. Mantemos os 60 lembretes mais próximos, dentro de 60 dias. Abra o Trackr periodicamente para renovar a fila. Foco e permissões do iOS podem silenciar alertas.")
            }
            Section {
                ShortcutsLink()
                SiriTipView(intent: TrackrSummaryIntent())
            } header: { Text("Atalhos e Siri") } footer: {
                Text("No app Atalhos, procure Trackr para combinar ações e criar automações. Valores são em reais. Registros por voz exigem o aparelho desbloqueado. No iOS 27, também é possível utilizar a busca integrada à Siri AI.")
            }
            Section("Sobre") {
                LabeledContent("Versão", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4")
            }
        }
        .trackrFormScreen("Ajustes")
        .tint(selectedAccent.color)
        .preferredColorScheme((TrackrAppearance(rawValue: appearance) ?? .system).colorScheme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { TrackrToolbarButton("Concluir", systemImage: "checkmark") { dismiss() } } }
        .onAppear { notifications.refresh(context: context) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { notifications.refresh(context: context) } }
        .onChange(of: daysBefore) { _, _ in notifications.refresh(context: context) }
        .onChange(of: hour) { _, _ in notifications.refresh(context: context) }
        .onChange(of: minute) { _, _ in notifications.refresh(context: context) }
        .onChange(of: showAmounts) { _, _ in notifications.refresh(context: context) }
        .onChange(of: accent) { _, _ in TrackrThemeState.shared.refresh() }
        .onChange(of: hideAmounts) { _, _ in WidgetSnapshotService.refresh(context: context) }
        .onChange(of: appLock.isEnabled) { _, _ in
            WidgetSnapshotService.refresh(context: context)
            notifications.reset(context: context)
        }
    }
    private var selectedAccent: TrackrAccent { TrackrAccent(rawValue: accent) ?? .blue }
}

struct TrackrAccentSettingsView: View {
    @AppStorage("trackr.accent") private var accent = "blue"
    var body: some View {
        List(TrackrAccent.allCases) { value in
            Button {
                accent = value.rawValue
                TrackrThemeState.shared.refresh()
            } label: {
                HStack(spacing: 12) {
                    Circle().fill(value.color).frame(width: 26, height: 26)
                    Text(value.title).foregroundStyle(.primary)
                    Spacer()
                    if accent == value.rawValue { Image(systemName: "checkmark").foregroundStyle(value.color) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(accent == value.rawValue ? .isSelected : [])
        }
        .trackrListScreen("Cor de destaque", largeTitle: false)
        .tint((TrackrAccent(rawValue: accent) ?? .blue).color)
    }
}
