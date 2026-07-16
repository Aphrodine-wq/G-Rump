import SwiftUI

// MARK: - Typography Scale

enum Typography {
    // Display — use .largeTitle / .title for Dynamic Type scaling
    static let displayLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let displayMedium = Font.system(.title, design: .rounded, weight: .bold)

    // Headings — use .title2 / .title3 / .headline for scaling
    static let heading1 = Font.system(.title2, weight: .bold)
    static let heading2 = Font.system(.title3, weight: .bold)
    static let heading3 = Font.system(.headline, weight: .semibold)

    // Body — use .body / .callout / .subheadline for scaling
    static let bodyLarge = Font.system(.body)
    static let body = Font.system(.subheadline)
    static let bodyMedium = Font.system(.subheadline, weight: .medium)
    static let bodySemibold = Font.system(.subheadline, weight: .semibold)
    static let bodySmall = Font.system(.footnote)
    static let bodySmallMedium = Font.system(.footnote, weight: .medium)
    static let bodySmallSemibold = Font.system(.footnote, weight: .semibold)

    // Caption / Metadata — use .caption / .caption2 for scaling
    static let caption = Font.system(.caption)
    static let captionSemibold = Font.system(.caption, weight: .semibold)
    static let captionSmall = Font.system(.caption2)
    static let captionSmallMedium = Font.system(.caption2, weight: .medium)
    static let captionSmallSemibold = Font.system(.caption2, weight: .semibold)
    static let micro = Font.system(size: 10)
    static let microSemibold = Font.system(size: 10, weight: .semibold)

    // Sidebar title
    static let sidebarTitle = Font.system(.body, design: .rounded, weight: .bold)

    // Code — monospaced with relative sizing so they scale with Dynamic Type
    static let codeLarge = Font.system(.footnote, design: .monospaced)
    static let code = Font.system(.caption, design: .monospaced)
    static let codeSmall = Font.system(.caption2, design: .monospaced)
    static let codeMicro = Font.system(size: 10, design: .monospaced)

    // Special — fixed sizes for decorative elements (these don't need Dynamic Type)
    static let splashTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let splashSubtitle = Font.system(size: 14, weight: .medium, design: .rounded)
    static let sparkleIcon = Font.system(size: 9, weight: .bold)
    static let sparkleSubtitle = Font.system(.footnote)
    static let emptyStateIcon = Font.system(size: 48, weight: .medium)
    static let onboardingIcon = Font.system(size: 54, weight: .semibold)

    // Content-size scaled (for user preference: Small / Medium / Large)
    static func bodyScaled(scale: CGFloat) -> Font { .system(size: 14 * scale) }
    static func bodySmallScaled(scale: CGFloat) -> Font { .system(size: 13 * scale) }
    static func codeScaled(scale: CGFloat) -> Font { resolveCodeFont(size: 12 * scale) }
    static func codeLargeScaled(scale: CGFloat) -> Font { resolveCodeFont(size: 13 * scale) }
    static func codeSmallScaled(scale: CGFloat) -> Font { resolveCodeFont(size: 11 * scale) }
    static func captionSmallScaled(scale: CGFloat) -> Font { .system(size: 11 * scale, weight: .medium) }

    /// User-configurable line spacing (stored via @AppStorage("LineSpacing"))
    static var userLineSpacing: CGFloat {
        CGFloat(UserDefaults.standard.double(forKey: "LineSpacing")).clamped(to: 0...10, default: 3.0)
    }

    /// Fixed row height for code block lines (gutter + code stay aligned).
    /// Scales with the content-size preference so larger code text never clips.
    static func codeRowHeight(scale: CGFloat) -> CGFloat {
        ceil(14 * scale) + userLineSpacing
    }

    /// Resolve code font from user preference, falling back to system monospace
    private static func resolveCodeFont(size: CGFloat) -> Font {
        let fontName = UserDefaults.standard.string(forKey: "CodeFont") ?? ""
        if fontName.isEmpty || fontName == "System Mono" {
            return .system(size: size, design: .monospaced)
        }
        #if os(macOS)
        if NSFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size)
        }
        #endif
        return .system(size: size, design: .monospaced)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>, default fallback: CGFloat) -> CGFloat {
        if self == 0 { return fallback }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Spacing Scale (4pt base)

enum Spacing {
    static let xxs: CGFloat = 1
    static let xs: CGFloat = 3
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 10
    static let xxl: CGFloat = 12
    static let xxxl: CGFloat = 14
    static let huge: CGFloat = 16
    static let massive: CGFloat = 20
    static let giant: CGFloat = 28
    static let colossal: CGFloat = 32
}

// MARK: - Corner Radii (crisp: slightly tighter for clarity)

enum Radius {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let standard: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 14
    static let bubble: CGFloat = 14
    static let pill: CGFloat = 20
}

// MARK: - Border (crisp 1pt)

enum Border {
    static let hairline: CGFloat = 0.5
    static let thin: CGFloat = 1
    static let medium: CGFloat = 1.5
}

// MARK: - Animation Durations
// Prefer instant/quick for micro-interactions to keep the UI feeling 250fps-ready.

enum Anim {
    static let instant: Double = 0.12
    static let quick: Double = 0.15
    static let standard: Double = 0.18
    static let smooth: Double = 0.25
    static let gentle: Double = 0.28
    static let slow: Double = 0.4
    static let splash: Double = 0.5
    /// Stagger delay for sequential item animations (e.g. message list).
    static let stagger: Double = 0.05
    /// Bounce / spring-like micro-interaction.
    static let bounce: Double = 0.35

    // MARK: Standard Spring Animations

    /// Default spring for UI transitions (panels, sheets, cards).
    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// Snappy spring for button presses and toggles.
    static let springSnap = Animation.spring(response: 0.25, dampingFraction: 0.75)
    /// Gentle spring for modal presentations and large movements.
    static let springGentle = Animation.spring(response: 0.45, dampingFraction: 0.9)
    /// Bouncy spring for playful interactions (splash, onboarding).
    static let springBounce = Animation.spring(response: 0.4, dampingFraction: 0.65)
}
