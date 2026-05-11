import SwiftUI

struct ReaderSettingsView: View {
    @ObservedObject var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let contentWidth: CGFloat = 560

    private var usesCompactLayout: Bool {
#if canImport(UIKit)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsCard(
                        title: "语音引擎",
                        subtitle: "选择当前朗读使用的语音后端。",
                        isCompact: usesCompactLayout
                    ) {
                        SettingsLabeledRow(title: "当前引擎", isCompact: usesCompactLayout) {
                            Picker("当前引擎", selection: $settings.backend) {
                                ForEach(ReaderSettings.BackendOption.allCases) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    SettingsCard(
                        title: "通用朗读参数",
                        subtitle: "这些参数会影响当前朗读体验；切换后会自动保存。",
                        isCompact: usesCompactLayout
                    ) {
                        SettingsSliderRow(
                            title: "语速",
                            valueText: String(format: "%.2fx", settings.rate),
                            value: $settings.rate,
                            range: 0.7...1.3,
                            step: 0.05,
                            isCompact: usesCompactLayout
                        )

                        SettingsSliderRow(
                            title: "音调",
                            valueText: String(format: "%.2fx", settings.pitch),
                            value: $settings.pitch,
                            range: 0.8...1.2,
                            step: 0.05,
                            isCompact: usesCompactLayout
                        )

                        SettingsSliderRow(
                            title: "音量",
                            valueText: "\(Int(settings.volume * 100))%",
                            value: $settings.volume,
                            range: 0.0...1.0,
                            step: 0.05,
                            isCompact: usesCompactLayout,
                            showsDivider: false
                        )
                    }

                    SettingsCard(
                        title: "Piper 专属参数",
                        subtitle: "仅在使用 Piper 本地语音时生效。",
                        accent: settings.backend == .piper ? .accentColor : .secondary,
                        isCompact: usesCompactLayout
                    ) {
                        SettingsSliderRow(
                            title: "Piper 节奏",
                            valueText: String(format: "%.2fx", settings.piperLengthScale),
                            value: $settings.piperLengthScale,
                            range: 0.8...1.6,
                            step: 0.05,
                            isCompact: usesCompactLayout,
                            helperText: "仅影响 Piper 的合成时长；数值越大，整体越慢，适合和官方样本做对比。"
                        )

                        SettingsPickerBlock(
                            title: "中文拼音拆分",
                            helperText: settings.piperPinyinMode.detailText,
                            isCompact: usesCompactLayout,
                            showsDivider: false
                        ) {
                            Picker("中文拼音拆分", selection: $settings.piperPinyinMode) {
                                ForEach(PiperPinyinMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .opacity(settings.backend == .piper ? 1 : 0.65)

                    SettingsCard(
                        title: "操作",
                        subtitle: "如果想从头重新调参，可以一键恢复默认设置。",
                        isCompact: usesCompactLayout
                    ) {
                        Group {
                            if usesCompactLayout {
                                VStack(alignment: .leading, spacing: 10) {
                                    Button("恢复默认设置") {
                                        settings.reset()
                                    }

                                    Text("会保留当前文本内容，仅重置朗读相关配置。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                HStack {
                                    Button("恢复默认设置") {
                                        settings.reset()
                                    }
                                    .keyboardShortcut("r", modifiers: [.command, .shift])

                                    Spacer()

                                    Text("会保留当前文本内容，仅重置朗读相关配置。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(usesCompactLayout ? 16 : 24)
                .frame(maxWidth: usesCompactLayout ? .infinity : contentWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("朗读设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .frame(
            minWidth: usesCompactLayout ? nil : 620,
            idealWidth: usesCompactLayout ? nil : 680,
            minHeight: usesCompactLayout ? nil : 560,
            idealHeight: usesCompactLayout ? nil : 620
        )
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    var accent: Color = .accentColor
    var isCompact: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(isCompact ? 16 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

private struct SettingsLabeledRow<Content: View>: View {
    let title: String
    var isCompact: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .fontWeight(.medium)

                    content
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Text(title)
                        .fontWeight(.medium)
                        .frame(width: 96, alignment: .leading)

                    content
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var isCompact: Bool = false
    var helperText: String? = nil
    var showsDivider: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCompact {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .fontWeight(.medium)

                    Spacer(minLength: 12)

                    Text(valueText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(value: $value, in: range, step: step)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .fontWeight(.medium)
                        .frame(width: 96, alignment: .leading)

                    Slider(value: $value, in: range, step: step)

                    Text(valueText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, isCompact ? 0 : 108)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsDivider {
                Divider()
            }
        }
    }
}

private struct SettingsPickerBlock<Content: View>: View {
    let title: String
    let helperText: String?
    var isCompact: Bool = false
    var showsDivider: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isCompact {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .fontWeight(.medium)

                    content
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Text(title)
                        .fontWeight(.medium)
                        .frame(width: 96, alignment: .leading)

                    content
                }
            }

            if let helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, isCompact ? 0 : 108)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsDivider {
                Divider()
            }
        }
    }
}

#Preview {
    ReaderSettingsView(settings: ReaderSettings())
}
