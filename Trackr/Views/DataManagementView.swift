import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TrackrExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DataManagementView: View {
    @State private var importingStatement = false
    @Environment(\.modelContext) private var context
    @State private var exporting = false
    @State private var importing = false
    @State private var document = TrackrExportDocument(data: Data())
    @State private var exportType = UTType.json
    @State private var pending: TrackrBackup?
    @State private var confirming = false
    @State private var message: String?
    @State private var error: String?
    @State private var confirmingReset = false
    @AppStorage("trackr.lastBackupExport") private var lastBackupExport = 0.0
    var body: some View {
        Form {
            Section {
                Label("Armazenamento neste iPhone", systemImage: "internaldrive")
                Text("Seus registros ficam no dispositivo. Crie um backup para recuperá-los em outra instalação, sem depender de sincronização.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Exportar backup completo", systemImage: "square.and.arrow.up") { exportBackup() }
                Button("Importar backup", systemImage: "square.and.arrow.down") { importing = true }
                LabeledContent("Último backup exportado", value: lastBackupExport > 0 ? Date(timeIntervalSince1970: lastBackupExport).formatted(date: .abbreviated, time: .shortened) : "Nenhum ainda")
            } header: { Text("Backup do Trackr") } footer: {
                Text("Inclui categorias, cartões, compras, parcelas, faturas pagas, recorrências e contas agendadas. Escolha uma pasta no app Arquivos. A restauração adiciona registros ausentes e mantém os existentes. Preferências do aparelho não são alteradas.")
            }
            Section {
                Button("Importar extrato bancário", systemImage: "building.columns") { importingStatement = true }
                Button("Exportar transações em CSV", systemImage: "tablecells") {
                    do { document = TrackrExportDocument(data: try BackupService.csv(context: context)); exportType = .commaSeparatedText; exporting = true }
                    catch { self.error = error.localizedDescription }
                }
            } header: { Text("Extratos e planilhas") } footer: {
                Text("CSV é destinado à análise em planilhas; para restaurar o app, use o backup completo em JSON.")
            }
            if let message { Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) } }
            Section {
                Button("Apagar todos os dados e redefinir", role: .destructive) { confirmingReset = true }
                    .foregroundStyle(.red)
            } header: { Text("Redefinir Trackr") } footer: {
                Text("Remove lançamentos, cartões, pagamentos, recorrências e categorias personalizadas, cancela os lembretes e restaura as preferências. Os arquivos de backup que você exportou não serão apagados.")
            }
        }
        .trackrFormScreen("Dados e backup")
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType,
                      defaultFilename: exportType == .json ? "Trackr-Backup" : "Trackr-Transacoes") { result in
            switch result {
            case .success:
                if exportType == .json { lastBackupExport = Date.now.timeIntervalSince1970 }
                message = "Arquivo exportado."
            case .failure(let issue): if (issue as NSError).code != NSUserCancelledError { error = issue.localizedDescription }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                pending = try BackupService.decode(Data(contentsOf: url))
                confirming = true
            } catch { if (error as NSError).code != NSUserCancelledError { self.error = error.localizedDescription } }
        }
        .confirmationDialog("Importar backup do Trackr?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Adicionar registros do backup") {
                guard let pending else { return }
                do { let count = try BackupService.restore(pending, context: context); message = "\(count) registros adicionados." }
                catch { self.error = error.localizedDescription }
                self.pending = nil
            }
        } message: {
            Text("O arquivo tem \(pending?.count ?? 0) registros. Os dados atuais serão mantidos. Cobranças de recorrências ativas serão atualizadas ao voltar ao app.")
        }
        .statementImporter(isPresented: $importingStatement)
        .alert("Apagar todos os dados?", isPresented: $confirmingReset) {
            Button("Cancelar", role: .cancel) { }
            Button("Apagar e redefinir", role: .destructive) {
                do { try AppResetService.reset(context: context); message = "Trackr restaurado aos padrões." }
                catch { self.error = error.localizedDescription }
            }
        } message: {
            Text("Esta ação não pode ser desfeita. Exporte um backup antes se quiser preservar seus registros. A permissão de notificações do iOS continua sendo controlada pelos Ajustes do sistema.")
        }
        .financeError($error)
    }
    private func exportBackup() {
        do {
            document = TrackrExportDocument(data: try BackupService.encode(BackupService.snapshot(context: context)))
            exportType = .json; exporting = true
        } catch { self.error = error.localizedDescription }
    }
}
