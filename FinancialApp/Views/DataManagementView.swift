import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LedgerExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var context
    @State private var exporting = false
    @State private var importing = false
    @State private var document = LedgerExportDocument(data: Data())
    @State private var exportType = UTType.json
    @State private var pending: LedgerBackup?
    @State private var confirming = false
    @State private var message: String?
    @State private var error: String?
    @AppStorage("ledger.lastBackupExport") private var lastBackupExport = 0.0
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
            } header: { Text("Backup do Ledger") } footer: {
                Text("Inclui categorias, cartões, compras, parcelas, faturas pagas, recorrências e contas agendadas. Escolha uma pasta no app Arquivos. A restauração adiciona registros ausentes e mantém os existentes. Preferências do aparelho não são alteradas.")
            }
            Section {
                NavigationLink { StatementImportView() } label: { Label("Importar extrato bancário", systemImage: "building.columns") }
                Button("Exportar transações em CSV", systemImage: "tablecells") {
                    do { document = LedgerExportDocument(data: try BackupService.csv(context: context)); exportType = .commaSeparatedText; exporting = true }
                    catch { self.error = error.localizedDescription }
                }
            } header: { Text("Extratos e planilhas") } footer: {
                Text("CSV é destinado à análise em planilhas; para restaurar o app, use o backup completo em JSON.")
            }
            if let message { Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.green) } }
        }
        .navigationTitle("Dados e backup").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: document, contentType: exportType,
                      defaultFilename: exportType == .json ? "Ledger-Backup" : "Ledger-Transacoes") { result in
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
        .confirmationDialog("Importar backup do Ledger?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Adicionar registros do backup") {
                guard let pending else { return }
                do { let count = try BackupService.restore(pending, context: context); message = "\(count) registros adicionados." }
                catch { self.error = error.localizedDescription }
                self.pending = nil
            }
        } message: {
            Text("O arquivo tem \(pending?.count ?? 0) registros. Os dados atuais serão mantidos. Cobranças de recorrências ativas serão atualizadas ao voltar ao app.")
        }
        .financeError($error)
    }
    private func exportBackup() {
        do {
            document = LedgerExportDocument(data: try BackupService.encode(BackupService.snapshot(context: context)))
            exportType = .json; exporting = true
        } catch { self.error = error.localizedDescription }
    }
}
