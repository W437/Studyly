import SwiftUI
import UIKit

// The brand palette and the semantic colour tokens. Shared by the app and the widget extension, so it depends
// on nothing but SwiftUI and UIKit. Every adaptive token is a light/dark pair; brand hues are fixed.
//
// Contrast rules (checked with WCAG 2 luminance, see docs/design.md):
// - Text on a brand fill (tangerine, mint, sun, rose, sky) is Night ink, never white: white on tangerine is 2.6:1.
// - Coloured text on a surface uses the `…Ink` variants (4.5:1 or better in both appearances).
// - `ink3` is for tertiary text and clears 4.3:1; anything smaller than footnote uses `ink2`.

extension Color {
    /// A fixed sRGB colour from 0xRRGGBB.
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// An adaptive colour: one value for light appearance, one for dark.
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: CGFloat(alpha))
    }
}

enum CLColor {
    // MARK: Brand (fixed in both appearances)
    static let night = Color(hex: 0x14213D)
    static let sky = Color(hex: 0x7CC8FF)
    static let tangerine = Color(hex: 0xFF7A1A)
    static let tangerinePressed = Color(hex: 0xE9690C)

    // The darker edge a pressable button stands on (it disappears as the face is pressed down onto it).
    static let tangerineEdge = Color(hex: 0xD45A04)
    static let mintEdge = Color(hex: 0x14966B)
    static let sunEdge = Color(hex: 0xD6A511)
    static let roseEdge = Color(hex: 0xD93659)
    static let inkEdge = Color(light: 0x03060C, dark: 0xB4BFD0)
    static let surfaceEdge = Color(light: 0xCBD5E2, dark: 0x111A2B)
    static let whiteEdge = Color(hex: 0xC5CEDB)
    static let sun = Color(hex: 0xFFCF3F)
    static let mint = Color(hex: 0x22C38E)
    static let rose = Color(hex: 0xFF5A78)
    static let capy = Color(hex: 0xE0884A)
    /// Paper is white whatever the appearance: it's paper.
    static let paper = Color(hex: 0xFFFFFF)

    // MARK: Surfaces and ink
    static let background = Color(light: 0xF1F5FA, dark: 0x0B1220)
    static let surface = Color(light: 0xFFFFFF, dark: 0x151E30)
    static let surface2 = Color(light: 0xF4F7FB, dark: 0x1B263B)
    static let surface3 = Color(light: 0xE8EEF6, dark: 0x25324B)
    static let ink = Color(light: 0x14213D, dark: 0xEEF3FA)
    static let ink2 = Color(light: 0x56627A, dark: 0xA9B4C8)
    static let ink3 = Color(light: 0x6B7489, dark: 0x8B97AD)
    /// Placeholders and disabled glyphs only; never body text.
    static let ink4 = Color(light: 0x8E98AB, dark: 0x6D7A92)
    static let hairline = Color(light: 0x14213D, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.08)
    /// Ink on a brand fill.
    static let onFill = night

    // MARK: Coloured text on surfaces
    static let mintInk = Color(light: 0x0B7F5A, dark: 0x4FE0AE)
    static let roseInk = Color(light: 0xC8213F, dark: 0xFF8199)
    static let sunInk = Color(light: 0x8A6200, dark: 0xFFD866)
    static let skyInk = Color(light: 0x1866AE, dark: 0x8FD0FF)
    static let tangerineInk = Color(light: 0xB84A00, dark: 0xFF9A4D)

    // MARK: Soft fills behind coloured ink
    static let mintSoft = Color(light: 0x22C38E, dark: 0x22C38E, lightAlpha: 0.14, darkAlpha: 0.20)
    static let roseSoft = Color(light: 0xFF5A78, dark: 0xFF5A78, lightAlpha: 0.12, darkAlpha: 0.20)
    static let sunSoft = Color(light: 0xFFCF3F, dark: 0xFFCF3F, lightAlpha: 0.22, darkAlpha: 0.20)
    static let skySoft = Color(light: 0x7CC8FF, dark: 0x7CC8FF, lightAlpha: 0.22, darkAlpha: 0.20)
    static let tangerineSoft = Color(light: 0xFF7A1A, dark: 0xFF7A1A, lightAlpha: 0.12, darkAlpha: 0.20)

    // MARK: Highlighter marks (grading reuses the semantic set)
    static let markHit = Color(light: 0x22C38E, dark: 0x22C38E, lightAlpha: 0.28, darkAlpha: 0.34)
    static let markMiss = Color(light: 0xFF5A78, dark: 0xFF5A78, lightAlpha: 0.20, darkAlpha: 0.28)
    static let markKey = Color(light: 0xFFCF3F, dark: 0xFFCF3F, lightAlpha: 0.55, darkAlpha: 0.36)
    static let markSky = Color(light: 0x7CC8FF, dark: 0x7CC8FF, lightAlpha: 0.38, darkAlpha: 0.30)

    static let scrim = Color(light: 0x0A1224, dark: 0x000000, lightAlpha: 0.38, darkAlpha: 0.55)

    /// Readiness and mastery colour: Mint "you know this" (80+), Sun "almost" (50–79), Rose "not yet".
    static func readiness(_ value: Double) -> Color {
        value >= 0.8 ? mint : value >= 0.5 ? sun : rose
    }

    /// The text-safe variant of `readiness(_:)`.
    static func readinessInk(_ value: Double) -> Color {
        value >= 0.8 ? mintInk : value >= 0.5 ? sunInk : roseInk
    }
}

/// A course colour's brand hues (the enum is in `Shared/Core/CourseColor.swift`).
extension CourseColor {
    var fill: Color {
        switch self {
        case .sky: CLColor.sky
        case .tangerine: CLColor.tangerine
        case .mint: CLColor.mint
        case .sun: CLColor.sun
        case .rose: CLColor.rose
        case .capy: CLColor.capy
        }
    }

    var soft: Color {
        switch self {
        case .sky: CLColor.skySoft
        case .tangerine: CLColor.tangerineSoft
        case .mint: CLColor.mintSoft
        case .sun: CLColor.sunSoft
        case .rose: CLColor.roseSoft
        case .capy: CLColor.tangerineSoft
        }
    }

    var ink: Color {
        switch self {
        case .sky: CLColor.skyInk
        case .tangerine, .capy: CLColor.tangerineInk
        case .mint: CLColor.mintInk
        case .sun: CLColor.sunInk
        case .rose: CLColor.roseInk
        }
    }
}
