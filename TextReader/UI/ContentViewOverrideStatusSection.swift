//
//  ContentViewOverrideStatusSection.swift
//  TextReader
//
//  Summary: Displays pinyin override status and mismatch diagnostics.
//  Author: Ren, Ren
//  Modified: 2026/5/18
//

import SwiftUI

struct ContentViewOverrideStatusSection: View {
    let statusText: String
    let mismatch: TextMismatchDiagnostic?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let mismatch {
                VStack(alignment: .leading, spacing: 4) {
                    Text("不匹配定位：\(mismatch.summary)")
                        .foregroundStyle(.red)
                    Text("当前文本：\(mismatch.currentTextExcerpt)")
                    Text("JSON text：\(mismatch.overrideTextExcerpt)")
                }
                .font(.caption.monospaced())
                .padding(8)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
