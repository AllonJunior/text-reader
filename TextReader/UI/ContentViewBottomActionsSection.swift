//
//  ContentViewBottomActionsSection.swift
//  TextReader
//
//  Summary: Implements file loading, override management, export, and stop actions.
//  Author: Ren, Ren
//  Modified: 2026/5/18
//

import SwiftUI

struct ContentViewBottomActionsSection: View {
    let state: ContentViewScreenState
    let usesCompactLayout: Bool
    let isExportingAudio: Bool
    let canClearOverride: Bool
    let onLoadFile: () -> Void
    let onLoadOverride: () -> Void
    let onClearOverride: () -> Void
    let onExport: () -> Void
    let onStop: () -> Void

    var body: some View {
        Group {
            if usesCompactLayout {
                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ContentViewBottomActionButton(title: "加载文件", action: onLoadFile)
                                .disabled(state.isPlaybackActive)

                            ContentViewBottomActionButton(title: "加载拼音 JSON", action: onLoadOverride)
                                .disabled(state.isPlaybackActive)

                            if canClearOverride {
                                ContentViewBottomActionButton(title: "清除拼音覆盖", action: onClearOverride)
                                    .disabled(state.isPlaybackActive)
                            }

                            ContentViewBottomActionButton(
                                title: isExportingAudio ? "导出中…" : "导出音频",
                                prominent: true,
                                action: onExport
                            )
                            .disabled(state.trimmedText.isEmpty || state.isPlaybackActive || isExportingAudio)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, ContentViewMetrics.compactBottomActionRowLeadingInset)
                    }

                    if state.isPlaybackActive {
                        Button("停止", action: onStop)
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Button("加载文件", action: onLoadFile)
                        .padding()
                        .disabled(state.isPlaybackActive)

                    Button("加载拼音 JSON", action: onLoadOverride)
                        .padding()
                        .disabled(state.isPlaybackActive)

                    if canClearOverride {
                        Button("清除拼音覆盖", action: onClearOverride)
                            .padding()
                            .disabled(state.isPlaybackActive)
                    }

                    Button(isExportingAudio ? "导出中…" : "导出音频", action: onExport)
                        .padding()
                        .disabled(state.trimmedText.isEmpty || state.isPlaybackActive || isExportingAudio)

                    if state.isPlaybackActive {
                        Button("停止", action: onStop)
                            .padding()
                    }
                }
            }
        }
    }
}

private struct ContentViewBottomActionButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Group {
#if canImport(UIKit)
            if prominent {
                Button(title, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button(title, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
#else
            Button(title, action: action)
#endif
        }
        .font(.footnote.weight(.medium))
        .frame(minHeight: ContentViewMetrics.compactBottomActionButtonHeight)
    }
}
