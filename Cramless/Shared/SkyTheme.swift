import SwiftUI

/// A sky's colours: what lies behind the stars and what the world stands on. The stars keep their course colours in every
/// sky; the theme is only the night around them. Six skies are drawn in code, one of them the default (`SkyTheme.night`,
/// the look Capling has always had) and five that a week of daily quests lights, one by one.
struct SkyPalette: Sendable, Equatable {
    /// A gradient's two ends, top then bottom.
    struct Pair: Sendable, Equatable {
        var top: Color
        var bottom: Color
    }

    /// The sky's background: darkest at the top, a little lighter towards the horizon.
    var top: Color
    var bottom: Color
    /// The dusk at the horizon, from high up down to where the hills begin.
    var glowHigh: Color
    var glowMid: Color
    var glowLow: Color
    /// The pale band of countless stars: its cool tint and its warm one.
    var haze: Color
    var hazeWarm: Color
    /// The faint background stars, cool and warm.
    var dustCool: Color
    var dustWarm: Color
    var farHills: Pair
    var midHills: Pair
    var water: Pair
    var ground: Pair
    /// The far ridge's lit edge (warm), and the cool light along it and the mist above it.
    var crestWarm: Color
    var crestCool: Color
    /// The arc of light a refresh sends up the sky.
    var arc: Color
}

enum SkyTheme: String, CaseIterable, Sendable, Identifiable, Codable {
    /// Deep blue, violet at the horizon: the default.
    case night
    /// Indigo and magenta, a long sunset.
    case dusk
    /// Green and teal over a dark lake, violet at the horizon.
    case aurora
    /// Embers: red-brown ground, orange and gold at the horizon.
    case ember
    /// A rosy dawn.
    case bloom
    /// Ice blue and white.
    case glacier

    var id: String { rawValue }

    /// The order the skies are lit in: one for each week of 12 quests. Night is always there.
    static let unlockOrder: [SkyTheme] = [.dusk, .aurora, .ember, .bloom, .glacier]

    /// The skies `weeks` lit weeks have unlocked: Night, then each lit sky in order.
    static func unlocked(weeks: Int) -> [SkyTheme] {
        [.night] + unlockOrder.prefix(max(0, weeks))
    }

    /// The sky the next lit week unlocks; nil when all are lit.
    static func next(afterWeeks weeks: Int) -> SkyTheme? {
        unlockOrder.indices.contains(weeks) ? unlockOrder[weeks] : nil
    }

    /// Which lit week unlocks it (0 for Night, which is always there).
    var weekToUnlock: Int { (Self.unlockOrder.firstIndex(of: self) ?? -1) + 1 }

    var palette: SkyPalette {
        switch self {
        case .night: .night
        case .dusk: .dusk
        case .aurora: .aurora
        case .ember: .ember
        case .bloom: .bloom
        case .glacier: .glacier
        }
    }
}

// MARK: - The six skies

/// A palette from plain hex numbers, so each sky below is a short list of literals (long chains of `Color` initialisers
/// make the compiler slow).
private func palette(sky: (UInt32, UInt32), glow: (UInt32, UInt32, UInt32), haze: (UInt32, UInt32),
                     dust: (UInt32, UInt32), far: (UInt32, UInt32), mid: (UInt32, UInt32), water: (UInt32, UInt32),
                     ground: (UInt32, UInt32), crest: (UInt32, UInt32), arc: UInt32) -> SkyPalette {
    func pair(_ p: (UInt32, UInt32)) -> SkyPalette.Pair {
        SkyPalette.Pair(top: Color(hex: p.0), bottom: Color(hex: p.1))
    }
    return SkyPalette(top: Color(hex: sky.0), bottom: Color(hex: sky.1),
                      glowHigh: Color(hex: glow.0), glowMid: Color(hex: glow.1), glowLow: Color(hex: glow.2),
                      haze: Color(hex: haze.0), hazeWarm: Color(hex: haze.1),
                      dustCool: Color(hex: dust.0), dustWarm: Color(hex: dust.1),
                      farHills: pair(far), midHills: pair(mid), water: pair(water), ground: pair(ground),
                      crestWarm: Color(hex: crest.0), crestCool: Color(hex: crest.1), arc: Color(hex: arc))
}

extension SkyPalette {
    static let night = palette(
        sky: (0x070D1B, 0x14213D), glow: (0x6C46A8, 0xE4708C, 0xFFB070), haze: (0xA9B8FF, 0xFFD9B0),
        dust: (0xC7DEFF, 0xFFE6C2), far: (0x333E78, 0x1A2350), mid: (0x212D5E, 0x121C3E),
        water: (0x24396E, 0x0C1432), ground: (0x131F3E, 0x080E22), crest: (0xFFE2C4, 0xB9C6FF), arc: 0xE6ECFF)

    static let dusk = palette(
        sky: (0x0F0A28, 0x2A1A5A), glow: (0x7A3FD0, 0xE0507E, 0xFFB070), haze: (0xC9B0FF, 0xFFC9A8),
        dust: (0xE4D4FF, 0xFFD9C2), far: (0x43307A, 0x261A52), mid: (0x30225A, 0x1B1240),
        water: (0x362A78, 0x140C36), ground: (0x1A1034, 0x0C0722), crest: (0xFFC9B0, 0xCDBDFF), arc: 0xF0E4FF)

    static let aurora = palette(
        sky: (0x04141A, 0x0B2E33), glow: (0x2BD9A0, 0x39B6C8, 0x7A5BE0), haze: (0x9BFFE0, 0xC9FFE8),
        dust: (0xC9FFEE, 0xE8FFD8), far: (0x1F5560, 0x10343C), mid: (0x153F48, 0x0B2830),
        water: (0x1B4F5C, 0x07222B), ground: (0x0C2A30, 0x041418), crest: (0xA5F5DC, 0x9FE3E8), arc: 0xDFFFF4)

    static let ember = palette(
        sky: (0x1A0A0A, 0x3A1A14), glow: (0x9E2A2B, 0xFF6A2A, 0xFFC24A), haze: (0xFFB89A, 0xFFD9A0),
        dust: (0xFFD2B8, 0xFFE2A8), far: (0x5A2A2A, 0x341616), mid: (0x421E1E, 0x240F0F),
        water: (0x4A2424, 0x1C0B0B), ground: (0x2A1212, 0x120606), crest: (0xFFC9A0, 0xFFB08A), arc: 0xFFE9D0)

    static let bloom = palette(
        sky: (0x1D1432, 0x4E3060), glow: (0xFF8FB8, 0xFFC4A0, 0xFFEBC8), haze: (0xFFD0E8, 0xFFE8D0),
        dust: (0xFFE0F2, 0xFFEAD8), far: (0x7A4E7A, 0x452C57), mid: (0x5C3A66, 0x34204A),
        water: (0x6B4A82, 0x2A1A48), ground: (0x35204F, 0x19102B), crest: (0xFFE6D4, 0xFFD0EC), arc: 0xFFF0F8)

    static let glacier = palette(
        sky: (0x06121F, 0x163552), glow: (0x5AB8E8, 0x9CE6FF, 0xE8F8FF), haze: (0xD0ECFF, 0xFFFFFF),
        dust: (0xE6F6FF, 0xFFFFFF), far: (0x3D6A8F, 0x1F3F5F), mid: (0x2A506F, 0x142D45),
        water: (0x2F6A94, 0x0C2238), ground: (0x153048, 0x08141F), crest: (0xE4F6FF, 0xBFE4FF), arc: 0xF0FAFF)
}

// MARK: - The environment

private struct SkyThemeKey: EnvironmentKey {
    static let defaultValue = SkyTheme.night
}

extension EnvironmentValues {
    /// The sky the person has chosen (Settings ▸ Appearance). The root view sets it from `AppSettings.skyTheme`.
    var skyTheme: SkyTheme {
        get { self[SkyThemeKey.self] }
        set { self[SkyThemeKey.self] = newValue }
    }
}
