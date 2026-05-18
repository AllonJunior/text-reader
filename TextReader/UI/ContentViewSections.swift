//
//  ContentViewSections.swift
//  TextReader
//
//  Summary: Implements the ContentView header section.
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

struct ContentViewHeader: View {
    let state: ContentViewScreenState
    let usesCompactLayout: Bool
    let onShowSettings: () -> Void

    var body: some View {
        Group {
            if usesCompactLayout {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("文本阅读器")
                                .font(.title2.weight(.semibold))
                            Text(state.backendDisplayName)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        VStack(spacing: 6) {
                            Button(action: onShowSettings) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 48, height: 30)
                            }
                            .buttonStyle(.plain)
#if canImport(UIKit)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemFill))
                            )
#endif

                            Text(state.compactPageCounterText)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }

                    if let playbackSourceDescription = state.playbackSourceDescription,
                       state.isPlaybackActive {
                        Text("当前句：\(playbackSourceDescription)")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 8)
            } else {
                HStack(alignment: .top) {
                    Spacer()

                    VStack(spacing: 6) {
                        Text("文本阅读器")
                            .font(.largeTitle)
                        Text(state.backendDisplayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let playbackSourceDescription = state.playbackSourceDescription,
                           state.isPlaybackActive {
                            Text("当前句：\(playbackSourceDescription)")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    VStack(spacing: 1) {
                        Button(action: onShowSettings) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)

#if canImport(AppKit)
                        Text(state.compactPageCounterText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
#endif
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }
}
