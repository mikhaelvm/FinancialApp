import SwiftUI
import SwiftData

struct GoogleDriveBackupView: View {
    @Environment(\.modelContext) private var context
    @State private var service = GoogleDriveBackupService.shared
    @AppStorage("trackr.drive.automatic") private var automatic = false
    @AppStorage("trackr.drive.lastBackup") private var lastBackup = 0.0
    @AppStorage("trackr.drive.syncEnabled") private var syncEnabled = true
    @AppStorage("trackr.drive.lastSync") private var lastSync = 0.0
    @State private var pending: TrackrBackup?
    @State private var confirmingRestore = false
    @State private var confirmingDisconnect = false
    @State private var restoreMessage: String?
    var body: some View {
        List {
            if !GoogleDriveBackupService.isConfigured {
                Section {
                    Label("Configuração do Google pendente", systemImage: "gear.badge")
                    Text("Esta versão precisa do Client ID do Google Cloud. Veja docs/GOOGLE_DRIVE.md no projeto.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                if let email = service.email {
                    LabeledContent("Conta", value: email)
                    Button("Desconectar", role: .destructive) { confirmingDisconnect = true }
                } else {
                    Button { Task { await service.connect() } } label: {
                        Label("Conectar Google Drive", systemImage: "person.crop.circle.badge.checkmark")
                    }.disabled(!GoogleDriveBackupService.isConfigured)
                }
            } footer: { Text("Ao conectar, combina os registros locais com os da conta. Usa somente a área privada do Trackr no Drive.") }
            if service.isConnected {
                Section {
                    Toggle("Sincronizar entre aparelhos", isOn: Binding(get: { syncEnabled }, set: { service.synchronization = $0 }))
                    Button("Sincronizar agora", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await service.synchronizeNow(context: context) }
                    }.disabled(!syncEnabled)
                    LabeledContent("Última sincronização", value: lastSync > 0
                        ? Date(timeIntervalSince1970: lastSync).formatted(date: .abbreviated, time: .shortened) : "Nenhuma")
                } header: { Text("iPhone e iPad") } footer: {
                    Text("Conecte a mesma conta nos dois aparelhos. Inclui edições e exclusões; atualiza ao abrir o app e durante o uso. Sem internet, envia ao reconectar.")
                }
                Section {
                    Button("Fazer backup agora", systemImage: "icloud.and.arrow.up") {
                        Task { await service.backup(context: context) }
                    }
                    Toggle("Backup automático", isOn: Binding(get: { automatic }, set: { service.automatic = $0 }))
                    LabeledContent("Último backup", value: lastBackup > 0
                        ? Date(timeIntervalSince1970: lastBackup).formatted(date: .abbreviated, time: .shortened) : "Nenhum")
                } footer: {
                    Text("Envia alterações durante o uso. Em segundo plano, depende do iOS. Com bloqueio de acesso, só envia com o app aberto e desbloqueado. Mantém 5 versões.")
                }
                Section {
                    Button("Buscar backups", systemImage: "arrow.clockwise") { Task { await service.listBackups() } }
                    ForEach(service.files) { file in
                        Button {
                            Task {
                                if let backup = await service.download(file) { pending = backup; confirmingRestore = true }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(file.date?.formatted(date: .abbreviated, time: .shortened) ?? file.name).foregroundStyle(Color.primary)
                                Text("Restaurar esta versão").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Restaurar") } footer: { Text("Adiciona registros ausentes. Dados atuais são mantidos. O backup contém seus registros financeiros em JSON.") }
            }
            if let message = restoreMessage ?? service.message {
                Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) }
            }
        }
        .trackrListScreen("Google Drive", largeTitle: false)
        .disabled(service.isBusy)
        .overlay { if service.isBusy { ProgressView("Aguarde…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .task { await service.foreground() }
        .confirmationDialog("Restaurar este backup?", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("Adicionar registros") {
                guard let pending else { return }
                do {
                    let count = try BackupService.restore(pending, context: context)
                    restoreMessage = "\(count) registros adicionados."
                } catch { service.error = error.localizedDescription }
                self.pending = nil
            }
            Button("Cancelar", role: .cancel) { pending = nil }
        } message: { Text("\(pending?.count ?? 0) registros no arquivo. Seus dados atuais serão mantidos.") }
        .confirmationDialog("Desconectar Google Drive?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { pending = nil; service.disconnect() }
        } message: { Text("Interrompe a sincronização e os backups. Dados locais e arquivos no Drive são mantidos.") }
        .financeError($service.error)
    }
}
