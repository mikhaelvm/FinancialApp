import Foundation

enum StatementFileAccess {
    static func copyForReview(_ url: URL) throws -> URL {
        guard ["ofx", "csv", "txt", "pdf"].contains(url.pathExtension.lowercased()) else {
            throw FinanceError.invalid("Escolha um arquivo OFX, CSV ou PDF exportado pelo banco.")
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Trackr-Statement-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        do {
            var coordinationError: NSError?
            var readError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                do {
                    if let size = try readable.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > StatementParser.maximumBytes {
                        throw FinanceError.invalid("O extrato deve ter até 15 MB.")
                    }
                    try FileManager.default.copyItem(at: readable, to: target)
                } catch { readError = error }
            }
            if let issue = coordinationError { throw issue }
            if let issue = readError { throw issue }
            return target
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
