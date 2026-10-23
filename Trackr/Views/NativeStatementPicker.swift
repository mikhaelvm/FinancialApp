import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Imports a copy, so review never relies on a file provider's temporary access grant.
struct NativeStatementPicker: UIViewControllerRepresentable {
    let onSelection: (Result<URL, Error>) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NativeStatementPicker
        init(_ parent: NativeStatementPicker) { self.parent = parent }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.onCancel() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { parent.onCancel(); return }
            do { parent.onSelection(.success(try StatementFileAccess.copyForReview(url))) }
            catch { parent.onSelection(.failure(error)) }
        }
    }
}
