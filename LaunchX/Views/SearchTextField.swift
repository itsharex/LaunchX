import AppKit
import SwiftUI

/// A high-performance NSTextField wrapper that doesn't block on input
/// Key difference from SwiftUI TextField: text changes are handled synchronously
/// without triggering SwiftUI's view update cycle
struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onTextChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 26, weight: .light)
        textField.cell?.sendsActionOnEndEditing = false

        // Make it first responder on next run loop
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update if text is different (avoid feedback loop)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            let newText = textField.stringValue

            // Update binding
            parent.text = newText

            // Call change handler immediately (synchronous, no debounce)
            parent.onTextChange?(newText)
        }

        func control(
            _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit?()
                return true
            }
            return false
        }
    }
}

/// Focus management for SearchTextField
struct SearchTextFieldFocusModifier: ViewModifier {
    @Binding var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                isFocused = true
            }
    }
}
