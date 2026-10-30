import SwiftUI
import WidgetKit

// Pieces the widgets and Live Activities share. The widget views live in Shared/ (not CramlessWidgets/) so the app's
// hosted tests can render them to PNGs (CramlessTests/WidgetRenderTests.swift); the extension only wraps them in
// configurations, timelines and container backgrounds.
//
// Type: the extension can't use `.clFont` (DesignSystem is app-only) or load the dyslexia-friendly font, so widgets
// use the faces `.clFont` resolves to: SF Pro text styles for words (they follow Dynamic Type; each widget caps the
// size it can hold with `.dynamicTypeSize(...)`) and SF Pro Rounded, tabular, for numerals.

enum WidgetFont {
    /// Rounded, tabular numerals: readiness, minutes, days, streaks.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static let eyebrow = Font.system(.caption2, weight: .semibold)
    static let title = Font.system(.subheadline, weight: .semibold)
    static let bodyEmphasis = Font.system(.footnote, weight: .semibold)
    static let caption = Font.system(.caption)
    static let captionEmphasis = Font.system(.caption, weight: .semibold)
}

/// "NEXT EXAM", "TODAY'S SESSION": small, tracked, uppercase.
struct WidgetEyebrow: View {
    var text: String
    var systemImage: String?
    var dot: CourseColor?
    var color: Color = CLColor.ink2

    var body: some View {
        HStack(spacing: 5) {
            if let dot {
                Circle().fill(dot.fill).frame(width: 7, height: 7).widgetAccentable()
            }
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(WidgetFont.eyebrow)
                .tracking(0.6)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .foregroundStyle(color)
    }
}

/// A round-capped ring over a track. Strokes stay inside the frame (unlike a plain `Circle().stroke`).
struct WidgetRing: View {
    /// 0…1.
    var value: Double
    var lineWidth: CGFloat
    var tint: Color
    var track: Color

    var body: some View {
        let clamped = max(0, min(1, value))
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if clamped > 0 {
                Circle()
                    .trim(from: 0, to: max(clamped, 0.015))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
        .padding(lineWidth / 2)
    }
}

/// The readiness ring with its percentage inside, for Home Screen widgets and Live Activities.
struct WidgetReadinessRing: View {
    var value: Double
    var size: CGFloat
    var lineWidth: CGFloat
    var track: Color = CLColor.surface3
    var labelColor: Color = CLColor.ink
    var showsLabel = true

    var body: some View {
        ZStack {
            WidgetRing(value: value, lineWidth: lineWidth, tint: CLColor.readiness(value), track: track)
            if showsLabel {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(WidgetCopy.percent(value))")
                        .font(WidgetFont.number(size * 0.3))
                    Text("%")
                        .font(WidgetFont.number(size * 0.15, .bold))
                }
                .foregroundStyle(labelColor)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, lineWidth + 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A thin progress bar.
struct WidgetBar: View {
    /// 0…1.
    var value: Double
    var tint: Color
    var track: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * max(0, min(1, value))))
                    .opacity(value > 0 ? 1 : 0)
                    .widgetAccentable()
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Cap's face in a rounded tile (the app's `CapFace`, which the extension can't see).
struct WidgetCapFace: View {
    var size: CGFloat

    var body: some View {
        Image("CapFace")
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .scaledToFill()
            .frame(width: size, height: size)
            .background(CLColor.sky)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The tangerine Start capsule. Widgets can't run buttons that open the app, so it's the label of a `Link`.
struct WidgetPrimaryLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(CLColor.onFill)
        .padding(.horizontal, 16)
        .frame(minHeight: 34)
        .background(CLColor.tangerine, in: Capsule())
        .widgetAccentable()
    }
}

/// "+5% this week" with an up arrow in mint, or a quiet "−3% this week" with a down arrow.
struct WidgetDelta: View {
    var delta: Double
    var font: Font = WidgetFont.captionEmphasis

    var body: some View {
        if let text = WidgetCopy.delta(delta) {
            HStack(spacing: 3) {
                Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text(text)
            }
            .font(font)
            .foregroundStyle(delta > 0 ? CLColor.mintInk : CLColor.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

/// A flame and the streak count.
struct WidgetStreakPill: View {
    var count: Int
    var studiedToday: Bool
    /// On the night card: a quiet white fill instead of the tangerine tint.
    var onNight = false

    var body: some View {
        HStack(spacing: 3) {
            StreakFlame(stage: StreakStage(days: count), size: 16)
            Text("\(count)")
                .font(WidgetFont.number(14, .bold))
                .foregroundStyle(onNight ? CLColor.ink : CLColor.tangerineInk)
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 24)
        .background(onNight ? Color.white.opacity(0.1) : CLColor.tangerineSoft, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(count)-day streak\(studiedToday ? ", studied today" : "")"))
    }
}

/// The surface a widget sits on, by look. The extension passes it to `.containerBackground(for: .widget)`; the
/// render tests draw it themselves (container backgrounds only exist inside WidgetKit).
enum WidgetBackground {
    case surface
    case night

    var color: Color {
        switch self {
        case .surface: CLColor.surface
        case .night: CLColor.night
        }
    }
}
