import SwiftUI

// Typography, spacing and radius tokens. Colours live in Shared/BrandPalette.swift (the widget needs them too).
//
// Type: Bricolage Grotesque (bundled as three static cuts) for the wordmark and display headlines, SF Pro for
// everything else, SF Pro Rounded for numbers. Every style scales with Dynamic Type. When the person turns on
// the dyslexia-friendly font (Settings ▸ Accessibility), reading text switches to OpenDyslexic; display
// headlines and numbers keep their faces because they are short and large.
//
// Use `.clFont(_:)` instead of `.font(_:)` for text the person reads, so the dyslexia switch reaches it.

enum CLTextStyle: Sendable {
    /// The wordmark and onboarding hero titles (Bricolage ExtraBold).
    case display(CGFloat)
    /// Onboarding page titles, the paywall headline, big feedback words (Bricolage Bold).
    case brandTitle(CGFloat)
    /// Short brand headings (Bricolage SemiBold).
    case brandHeading(CGFloat)
    case largeTitle      // 34 bold, tab roots
    case title           // 28 bold
    case title2          // 22 bold
    case title3          // 20 semibold, section headers
    case headline        // 17 semibold
    case body            // 17 regular
    case bodyEmphasis    // 17 semibold
    case callout         // 16 regular
    case subheadline     // 15 regular
    case subheadlineEmphasis
    case footnote        // 13 regular
    case footnoteEmphasis
    case caption         // 12 regular
    case eyebrow         // 12 semibold, uppercase, tracked
    /// Rounded numerals (readiness, streaks, timers). Tabular.
    case number(CGFloat, Font.Weight = .heavy)
}

enum CLFontName {
    static let display = "BricolageGrotesque-Display"
    static let title = "BricolageGrotesque-Title"
    static let heading = "BricolageGrotesque-Heading"
    static let dyslexic = "OpenDyslexic-Regular"
    static let dyslexicBold = "OpenDyslexic-Bold"
}

private struct DyslexicFontKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when the person chose the dyslexia-friendly font. Set once at the root from settings.
    var clDyslexicFont: Bool {
        get { self[DyslexicFontKey.self] }
        set { self[DyslexicFontKey.self] = newValue }
    }
}

extension CLTextStyle {
    /// `numberScale` grows rounded numerals with Dynamic Type (system sizes don't scale on their own).
    func font(dyslexic: Bool, numberScale: CGFloat = 1) -> Font {
        switch self {
        case .display(let size): return .custom(CLFontName.display, size: size, relativeTo: .largeTitle)
        case .brandTitle(let size): return .custom(CLFontName.title, size: size, relativeTo: .title)
        case .brandHeading(let size): return .custom(CLFontName.heading, size: size, relativeTo: .title3)
        case .number(let size, let weight):
            return .system(size: size * numberScale, weight: weight, design: .rounded).monospacedDigit()
        default: break
        }
        if dyslexic { return dyslexicFont }
        switch self {
        case .largeTitle: return .system(.largeTitle, weight: .bold)
        case .title: return .system(.title, weight: .bold)
        case .title2: return .system(.title2, weight: .bold)
        case .title3: return .system(.title3, weight: .semibold)
        case .headline: return .system(.headline)
        case .body: return .system(.body)
        case .bodyEmphasis: return .system(.body, weight: .semibold)
        case .callout: return .system(.callout)
        case .subheadline: return .system(.subheadline)
        case .subheadlineEmphasis: return .system(.subheadline, weight: .semibold)
        case .footnote: return .system(.footnote)
        case .footnoteEmphasis: return .system(.footnote, weight: .semibold)
        case .caption: return .system(.caption)
        case .eyebrow: return .system(.caption, weight: .semibold)
        case .display, .brandTitle, .brandHeading, .number: return .body
        }
    }

    private var dyslexicFont: Font {
        let bold: Bool
        let size: CGFloat
        let relative: Font.TextStyle
        switch self {
        case .largeTitle: (bold, size, relative) = (true, 30, .largeTitle)
        case .title: (bold, size, relative) = (true, 25, .title)
        case .title2: (bold, size, relative) = (true, 20, .title2)
        case .title3: (bold, size, relative) = (true, 18, .title3)
        case .headline, .bodyEmphasis: (bold, size, relative) = (true, 16, .headline)
        case .body: (bold, size, relative) = (false, 16, .body)
        case .callout: (bold, size, relative) = (false, 15, .callout)
        case .subheadline: (bold, size, relative) = (false, 14, .subheadline)
        case .subheadlineEmphasis: (bold, size, relative) = (true, 14, .subheadline)
        case .footnote: (bold, size, relative) = (false, 12, .footnote)
        case .footnoteEmphasis: (bold, size, relative) = (true, 12, .footnote)
        case .caption, .eyebrow: (bold, size, relative) = (false, 11, .caption)
        case .display, .brandTitle, .brandHeading, .number: (bold, size, relative) = (false, 16, .body)
        }
        return .custom(bold ? CLFontName.dyslexicBold : CLFontName.dyslexic, size: size, relativeTo: relative)
    }

    /// How much rounded numerals grow at each Dynamic Type size; capped so a number inside a ring still fits.
    static func numberScale(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 0.85
        case .small: 0.9
        case .medium: 0.95
        case .large: 1
        case .xLarge: 1.08
        case .xxLarge: 1.15
        case .xxxLarge: 1.22
        case .accessibility1: 1.3
        case .accessibility2: 1.35
        default: 1.4
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: -0.9
        case .brandTitle: -0.6
        case .brandHeading: -0.3
        case .largeTitle: -0.6
        case .title, .title2: -0.35
        case .eyebrow: 0.7
        case .number: -0.5
        default: 0
        }
    }

    var isUppercased: Bool {
        if case .eyebrow = self { return true }
        return false
    }
}

private struct CLFontModifier: ViewModifier {
    let style: CLTextStyle
    @Environment(\.clDyslexicFont) private var dyslexic
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .font(style.font(dyslexic: dyslexic, numberScale: CLTextStyle.numberScale(typeSize)))
            .tracking(dyslexic ? 0 : style.tracking)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

extension View {
    /// Applies a Capling text style. Use it for every piece of text the person reads.
    func clFont(_ style: CLTextStyle) -> some View {
        modifier(CLFontModifier(style: style))
    }
}

enum CLSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 26
    static let xxxl: CGFloat = 36
    /// The page gutter.
    static let gutter: CGFloat = 20
}

enum CLRadius {
    static let card: CGFloat = 28
    static let list: CGFloat = 26
    static let option: CGFloat = 20
    static let tile: CGFloat = 18
    static let badge: CGFloat = 10
    static let field: CGFloat = 14
}

enum CLMetrics {
    static let buttonHeight: CGFloat = 54
    static let buttonHeightMedium: CGFloat = 46
    static let buttonHeightSmall: CGFloat = 38
    static let rowMinHeight: CGFloat = 56
    static let minHitTarget: CGFloat = 44
    /// Reading width on big screens.
    static let readableWidth: CGFloat = 560
}
