//
//  ContentViewMetrics.swift
//  TextReader
//
//  Summary: Defines shared layout metrics used by ContentView-related views.
//  Author: Ren, Ren
//  Modified: 2026/5/18
//

import SwiftUI

enum ContentViewMetrics {
    static let editorFont: Font = .system(.body, design: .default)
    static let editorLineSpacing: CGFloat = 6
    static let compactSectionSpacing: CGFloat = 14
    static let compactCardCornerRadius: CGFloat = 16
    static let compactButtonHeight: CGFloat = 36
    static let compactShortButtonWidth: CGFloat = 64
    static let compactLongButtonWidth: CGFloat = 70
    static let compactJumpControlHeight: CGFloat = 30
    static let compactPageFieldWidth: CGFloat = 48
    static let regularPageFieldWidth: CGFloat = 40
    static let regularPageJumpControlsWidth: CGFloat = 190
    static let compactJumpRowLeadingInset: CGFloat = 6
    static let compactBottomActionButtonHeight: CGFloat = 30
    static let compactBottomActionRowLeadingInset: CGFloat = 10
}
