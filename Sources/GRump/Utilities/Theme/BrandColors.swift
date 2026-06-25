import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    // Primary purple palette — vivid violet
    static let brandPurple       = Color(red: 0.561, green: 0.337, blue: 1.000)   // #8F56FF
    static let brandPurpleDark   = Color(red: 0.404, green: 0.196, blue: 0.847)   // #6732D8

    static var brandPurpleLight: Color {
        #if os(macOS)
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.741, green: 0.612, blue: 1.000, alpha: 1)
                : NSColor(red: 0.404, green: 0.196, blue: 0.847, alpha: 1) // Use dark purple in light mode
        }))
        #else
        return Color(uiColor: UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.741, green: 0.612, blue: 1.000, alpha: 1)
                : UIColor(red: 0.404, green: 0.196, blue: 0.847, alpha: 1)
        })
        #endif
    }

    // Adaptive opacity for subtle purple
    static var brandPurpleSubtle: Color {
        Color.brandPurple.opacity(0.12)
    }

    // Background palette — crisp dark/light with clear hierarchy
    #if os(macOS)
    static let bgDark      = Color(nsColor: .windowBackgroundColor)
    static let bgCard     = Color(nsColor: .controlBackgroundColor)
    static let bgSidebar  = Color(nsColor: .windowBackgroundColor)
    static let bgInput    = Color(nsColor: .textBackgroundColor)
    static let bgElevated = Color(nsColor: .controlBackgroundColor)
    static let bgCrisp    = Color(nsColor: .controlBackgroundColor)
    #else
    static let bgDark      = Color(uiColor: .systemBackground)
    static let bgCard     = Color(uiColor: .secondarySystemBackground)
    static let bgSidebar  = Color(uiColor: .systemBackground)
    static let bgInput    = Color(uiColor: .tertiarySystemGroupedBackground)
    static let bgElevated = Color(uiColor: .secondarySystemBackground)
    static let bgCrisp    = Color(uiColor: .secondarySystemBackground)
    #endif

    // Highlight
    static var bgHighlight: Color {
        Color.brandPurple.opacity(0.08)
    }

    // Text colors - Adaptive
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static var textMuted: Color {
        Color.secondary.opacity(0.7)
    }

    // Accent / glow
    static var accentGlow: Color {
        Color.brandPurple.opacity(0.22)
    }
    static let accentGreen  = Color(red: 0.220, green: 0.875, blue: 0.604)   // #38DF9A
    static let accentOrange = Color(red: 1.000, green: 0.600, blue: 0.200)   // #FF9933

    // User bubble
    static let userBubble     = Color(red: 0.561, green: 0.337, blue: 1.000)
    static let userBubbleText = Color.white

    // Separator / borders — crisp 1pt lines
    #if os(macOS)
    static let borderSubtle = Color(nsColor: .separatorColor)
    static let borderCrisp  = Color(nsColor: .separatorColor).opacity(0.9)
    #else
    static let borderSubtle = Color(uiColor: .separator)
    static let borderCrisp  = Color(uiColor: .separator)
    #endif

    /// High-contrast border for focus/inputs (accent-tinted)
    static func borderFocus(_ accent: Color) -> Color {
        accent.opacity(0.5)
    }
}
