import SwiftUI
import UIKit

/// Applies the mask directly to the native editor, including while it is first responder.
struct CurrencyTextField: UIViewRepresentable {
    var placeholder = "0,00"
    @Binding var text: String
    var textStyle: UIFont.TextStyle = .body

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.placeholder = placeholder
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let done = UIBarButtonItem(image: UIImage(systemName: "checkmark"), primaryAction: UIAction { [weak field] _ in
            field?.resignFirstResponder()
        })
        done.accessibilityLabel = "Fechar teclado"
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        field.inputAccessoryView = toolbar
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let formatted = Money.bankInput(text, previous: text)
        if field.text != formatted { field.text = formatted }
        field.placeholder = placeholder
        field.font = UIFont.preferredFont(forTextStyle: textStyle)
        field.textColor = .label
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: uiView.intrinsicContentSize.height)
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CurrencyTextField
        init(_ parent: CurrencyTextField) { self.parent = parent }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = field.text ?? ""
            guard let range = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: range, with: string)
            let formatted = Money.bankInput(proposed, previous: current)
            // Returning false prevents UIKit from retaining an unformatted editing buffer.
            field.text = formatted
            let end = field.endOfDocument
            field.selectedTextRange = field.textRange(from: end, to: end)
            parent.text = formatted
            return false
        }
    }
}
