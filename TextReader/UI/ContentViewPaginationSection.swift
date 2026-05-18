//
//  ContentViewPaginationSection.swift
//  TextReader
//
//  Summary: Implements page navigation controls and page jump UI.
//  Author: Ren, Ren
//  Modified: 2026/5/18
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentViewPaginationSection: View {
    let state: ContentViewScreenState
    let usesCompactLayout: Bool
    @Binding var pageJumpText: String
    let onFirst: () -> Void
    let onPrevious: () -> Void
    let onPrimary: () -> Void
    let onNext: () -> Void
    let onLast: () -> Void
    let onJump: () -> Void

    var body: some View {
        Group {
            if usesCompactLayout {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 2) {
                        HStack(spacing: 8) {
                            ContentViewCompactButton(title: "首页", minWidth: ContentViewMetrics.compactShortButtonWidth, action: onFirst)
                                .disabled(!state.canGoToPreviousPage)
                                .keyboardShortcut(.leftArrow, modifiers: [.command])

                            ContentViewCompactButton(title: "上一页", minWidth: ContentViewMetrics.compactLongButtonWidth, action: onPrevious)
                                .disabled(!state.canGoToPreviousPage)
                                .keyboardShortcut(.leftArrow, modifiers: [.option])
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ContentViewCompactButton(title: state.primaryButtonTitle, isPrimary: true, action: onPrimary)
                            .disabled(state.speechState == .idle && state.trimmedCurrentPageText.isEmpty)
                            .layoutPriority(1)

                        HStack(spacing: 8) {
                            ContentViewCompactButton(title: "下一页", minWidth: ContentViewMetrics.compactLongButtonWidth, action: onNext)
                                .disabled(!state.canGoToNextPage)
                                .keyboardShortcut(.rightArrow, modifiers: [.option])

                            ContentViewCompactButton(title: "末页", action: onLast)
                                .disabled(!state.canGoToNextPage)
                                .keyboardShortcut(.rightArrow, modifiers: [.command])
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    HStack(alignment: .center, spacing: 9) {
                        TextField("页码", text: $pageJumpText)
                            .textFieldStyle(.plain)
                            .frame(width: ContentViewMetrics.compactPageFieldWidth, height: ContentViewMetrics.compactJumpControlHeight)
                            .font(.callout.monospacedDigit())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 4)
                            .background(compactFieldBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                            )
                            .onSubmit(onJump)

                        ContentViewCompactJumpButton(action: onJump)
                            .disabled(!state.canJumpToEnteredPage)

                        Spacer(minLength: 8)

                        if let pageCharacterCountText = state.currentPageCharacterCountText {
                            Text(pageCharacterCountText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding(.leading, ContentViewMetrics.compactJumpRowLeadingInset)
                }
            } else {
                HStack(spacing: 10) {
                    Button("首页", action: onFirst)
                        .disabled(!state.canGoToPreviousPage)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])

                    Button("上一页", action: onPrevious)
                        .disabled(!state.canGoToPreviousPage)
                        .keyboardShortcut(.leftArrow, modifiers: [.option])

                    Button(state.primaryButtonTitle, action: onPrimary)
                        .disabled(state.speechState == .idle && state.trimmedCurrentPageText.isEmpty)

                    Button("下一页", action: onNext)
                        .disabled(!state.canGoToNextPage)
                        .keyboardShortcut(.rightArrow, modifiers: [.option])

                    HStack(spacing: 8) {
                        TextField("页码", text: $pageJumpText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: ContentViewMetrics.regularPageFieldWidth)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(onJump)

                        Button("跳转", action: onJump)
                            .disabled(!state.canJumpToEnteredPage)
                            .frame(width: ContentViewMetrics.compactLongButtonWidth)

                        if let pageCharacterCountText = state.currentPageCharacterCountText {
                            Text(pageCharacterCountText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .frame(width: ContentViewMetrics.regularPageJumpControlsWidth, alignment: .trailing)

                    Button("末页", action: onLast)
                        .disabled(!state.canGoToNextPage)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var compactFieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
#if canImport(UIKit)
            .fill(Color(UIColor.secondarySystemBackground))
#else
            .fill(Color.secondary.opacity(0.08))
#endif
    }
}

private struct ContentViewCompactButton: View {
    let title: String
    var isPrimary = false
    var minWidth: CGFloat?
    let action: () -> Void

    var body: some View {
        let resolvedMinWidth = minWidth ?? (isPrimary ? 72 : 64)

        Group {
#if canImport(UIKit)
            if isPrimary {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            } else {
                Button(title, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
#else
            Button(title, action: action)
#endif
        }
        .font(.callout.weight(isPrimary ? .semibold : .medium))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: resolvedMinWidth, minHeight: ContentViewMetrics.compactButtonHeight)
    }
}

private struct ContentViewCompactJumpButton: View {
    let action: () -> Void

    var body: some View {
        Button("跳转", action: action)
            .font(.callout.weight(.medium))
            .frame(width: ContentViewMetrics.compactLongButtonWidth, height: ContentViewMetrics.compactJumpControlHeight)
#if canImport(UIKit)
            .buttonStyle(.bordered)
            .controlSize(.small)
#endif
    }
}
