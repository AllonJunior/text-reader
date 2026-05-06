import SwiftUI

#if canImport(UIKit)
import UIKit

/// A UITextView wrapper that can be toggled between editable and read-only,
/// while always allowing scrolling.
struct ReadOnlyTextView: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
    var backgroundColor: UIColor = .clear
    var lineSpacing: CGFloat = 6
    var highlightedRanges: [NSRange] = []
    var highlightBackgroundColor: UIColor = UIColor.systemRed.withAlphaComponent(0.18)
    var isFocused: Binding<Bool>? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = backgroundColor
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.showsVerticalScrollIndicator = true
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator

        tv.font = font
        tv.textColor = textColor
        tv.text = text

        // Keyboard behavior
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none

        // Initial state
        tv.isEditable = isEditable
        tv.isSelectable = true

        applyParagraphStyle(to: tv)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
            uiView.isSelectable = true

            // If transitioning to read-only, dismiss keyboard.
            if !isEditable, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }

        applyParagraphStyle(to: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var isFocused: Binding<Bool>?

        init(text: Binding<String>, isFocused: Binding<Bool>?) {
            _text = text
            self.isFocused = isFocused
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused?.wrappedValue = false
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }

    private func applyParagraphStyle(to textView: UITextView) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: para,
            .foregroundColor: textColor,
        ]

        // Preserve selection position as much as possible.
        let selected = textView.selectedRange
        let text = textView.text ?? ""
        let attributed = NSMutableAttributedString(string: text, attributes: attrs)
        for range in highlightedRanges {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: (text as NSString).length))
            guard clamped.length > 0 else { continue }
            attributed.addAttribute(.backgroundColor, value: highlightBackgroundColor, range: clamped)
        }
        textView.attributedText = attributed
        textView.selectedRange = selected
    }
}
#endif

#if canImport(AppKit)
import AppKit

/// A NSTextView wrapper that can be toggled between editable and read-only,
/// while always allowing scrolling.
struct ReadOnlyTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    var font: NSFont = .preferredFont(forTextStyle: .body)
    var textColor: NSColor = .labelColor
    var backgroundColor: NSColor = .clear
    var lineSpacing: CGFloat = 6
    var highlightedRanges: [NSRange] = []
    var highlightBackgroundColor: NSColor = NSColor.systemRed.withAlphaComponent(0.18)
    var isFocused: Binding<Bool>? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = FocusTextView()
        textView.delegate = context.coordinator
        textView.onMouseDown = {
            context.coordinator.isFocused?.wrappedValue = true
        }
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = backgroundColor
        textView.font = font
        textView.textColor = textColor
        textView.string = text
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0

        applyParagraphStyle(to: textView)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
        }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
            textView.isSelectable = true

            if !isEditable, let window = textView.window, window.firstResponder == textView {
                window.makeFirstResponder(nil)
            }
        }

        applyParagraphStyle(to: textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var isFocused: Binding<Bool>?

        init(text: Binding<String>, isFocused: Binding<Bool>?) {
            _text = text
            self.isFocused = isFocused
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused?.wrappedValue = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    private final class FocusTextView: NSTextView {
        var onMouseDown: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            onMouseDown?()
            super.mouseDown(with: event)
        }
    }

    private func applyParagraphStyle(to textView: NSTextView) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: para,
            .foregroundColor: textColor,
        ]

        let selected = textView.selectedRange()
        let text = textView.string
        let attributed = NSMutableAttributedString(string: text, attributes: attrs)
        for range in highlightedRanges {
            let clamped = NSIntersectionRange(range, NSRange(location: 0, length: (text as NSString).length))
            guard clamped.length > 0 else { continue }
            attributed.addAttribute(.backgroundColor, value: highlightBackgroundColor, range: clamped)
        }
        textView.textStorage?.setAttributedString(attributed)
        textView.setSelectedRange(selected)
    }
}
#endif
