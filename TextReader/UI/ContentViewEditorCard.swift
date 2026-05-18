//
//  ContentViewEditorCard.swift
//  TextReader
//
//  Summary: Implements the editor card section with placeholder, focus, and highlight handling.
//  Author: Ren, Ren
//  Modified: 2026/5/18
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ContentViewEditorCard: View {
    let state: ContentViewScreenState
    let text: Binding<String>
    @Binding var isEditorFocused: Bool
    let usesCompactLayout: Bool
    let placeholderText: String
    let scrollResetToken: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            if state.trimmedText.isEmpty && !isEditorFocused {
                Text(placeholderText)
                    .font(ContentViewMetrics.editorFont)
                    .foregroundStyle(.secondary)
                    .lineSpacing(ContentViewMetrics.editorLineSpacing)
                    .padding(.top, 18)
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
            }

#if canImport(UIKit)
            ReadOnlyTextView(
                text: text,
                isEditable: !state.isPlaybackActive,
                font: UIFont.preferredFont(forTextStyle: .body),
                textColor: UIColor.label,
                backgroundColor: .clear,
                lineSpacing: ContentViewMetrics.editorLineSpacing,
                highlightedRanges: state.editorHighlightedRanges,
                isFocused: $isEditorFocused,
                scrollResetToken: scrollResetToken
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
#elseif canImport(AppKit)
            ReadOnlyTextView(
                text: text,
                isEditable: !state.isPlaybackActive,
                font: NSFont.preferredFont(forTextStyle: .body),
                textColor: NSColor.labelColor,
                backgroundColor: .clear,
                lineSpacing: ContentViewMetrics.editorLineSpacing,
                highlightedRanges: state.editorHighlightedRanges,
                isFocused: $isEditorFocused,
                scrollResetToken: scrollResetToken
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
#else
            TextEditor(text: text)
                .font(ContentViewMetrics.editorFont)
                .lineSpacing(ContentViewMetrics.editorLineSpacing)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
#endif
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !state.isPlaybackActive {
                isEditorFocused = true
            }
        }
        .frame(minHeight: 220, maxHeight: 360)
        .background(editorBackgroundColor)
        .clipShape(
            RoundedRectangle(
                cornerRadius: usesCompactLayout ? ContentViewMetrics.compactCardCornerRadius : 12,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: usesCompactLayout ? ContentViewMetrics.compactCardCornerRadius : 12,
                style: .continuous
            )
            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(usesCompactLayout ? 0.04 : 0.06), radius: usesCompactLayout ? 6 : 8, x: 0, y: 2)
        .padding(.top, usesCompactLayout ? 2 : 5)
    }

    private var editorBackgroundColor: Color {
#if canImport(UIKit)
        return Color(UIColor.secondarySystemBackground)
#elseif canImport(AppKit)
        return Color(NSColor.textBackgroundColor)
#else
        return Color.secondary.opacity(0.08)
#endif
    }
}
