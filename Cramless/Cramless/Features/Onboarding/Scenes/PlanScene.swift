#if DEBUG
import SwiftUI

/// Scene 4, "A plan that bends": Wednesday is missed, Thursday and Friday absorb its minutes, the plan says so
/// kindly, and the evening reminder lands.
struct PlanScene: View {
    let active: Bool
    /// The reminder time the person has ("7:00 PM"), so the demo notification matches their own.
    let reminderTime: String

    @Environment(\.colorScheme) private var scheme
    @State private var missed = false
    @State private var absorbed = 0
    @State private var bump: Int?
    @State private var message = false
    @State private var notified = false

    private static let days: [(letter: String, minutes: Int)] =
        [("M", 15), ("T", 15), ("W", 15), ("T", 15), ("F", 10), ("S", 0), ("S", 20)]

    private enum PillStyle { case on, today, rest, missed }

    var body: some View {
        GeometryReader { geo in
            // A tall card reflows: the week sits centred, the message rises under it, and the reminder drops in
            // from the top and nudges everything down. A short card (iPhone SE) lets the reminder slide over.
            let roomy = geo.size.height >= 360
            VStack(alignment: .leading, spacing: 12) {
                if roomy && notified {
                    notification
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                HStack {
                    Text("This week").clFont(.headline).foregroundStyle(CLColor.ink)
                    Spacer(minLength: 6)
                    CLPill(text: "Midterm in 23 days", tone: .tangerine)
                }
                HStack(spacing: 6) {
                    ForEach(Self.days.indices, id: \.self) { i in
                        VStack(spacing: 7) {
                            Text(Self.days[i].letter)
                                .clFont(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(CLColor.ink3)
                            pill(i)
                        }
                    }
                }
                if message {
                    Text("Missed Wednesday? No problem. Thursday and Friday absorbed it.")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CLColor.sunSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .transition(.opacity.combined(with: .offset(y: 14)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, roomy ? 14 : 16)
            .padding(.top, roomy ? 12 : 0)
            .padding(.bottom, roomy ? 12 : 16)
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .top) {
                if !roomy {
                    notification
                        .padding(12)
                        .offset(y: notified ? 0 : -150)
                        .opacity(notified ? 1 : 0)
                }
            }
        }
        .sceneLifecycle(active: active, reset: reset, settle: settle, script: play)
    }

    private var notification: some View {
        HStack(spacing: 11) {
            CapFace(size: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Capling").clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                    Spacer(minLength: 4)
                    Text(reminderTime).clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                Text("22 minutes tonight and you're done. Your streak is safe.")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .glassEffect(.regular.tint(CLColor.surface.opacity(scheme == .dark ? 0.35 : 0.55)),
                     in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.14), radius: 16, y: 8)
    }

    private func pill(_ i: Int) -> some View {
        let (text, style) = state(i)
        return Text(text)
            .clFont(.number(12, .bold))
            .strikethrough(style == .missed)
            .foregroundStyle(foreground(style))
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(background(style), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(bump == i ? 1.12 : 1)
    }

    private func state(_ i: Int) -> (String, PillStyle) {
        let minutes = Self.days[i].minutes
        switch i {
        case 2: return ("\(minutes)m", missed ? .missed : .today)
        case 3: return absorbed >= 1 ? ("22m", .today) : ("\(minutes)m", .on)
        case 4: return absorbed >= 2 ? ("18m", .on) : ("\(minutes)m", .on)
        default: return minutes == 0 ? ("rest", .rest) : ("\(minutes)m", .on)
        }
    }

    private func foreground(_ style: PillStyle) -> Color {
        switch style {
        case .on: CLColor.tangerineInk
        case .today: CLColor.onFill
        case .rest, .missed: CLColor.ink3
        }
    }

    private func background(_ style: PillStyle) -> Color {
        switch style {
        case .on: CLColor.tangerineSoft
        case .today: CLColor.tangerine
        case .rest: .clear
        case .missed: CLColor.surface2
        }
    }

    // MARK: Script

    private func reset() {
        missed = false; absorbed = 0; bump = nil; message = false; notified = false
    }

    private func settle() {
        missed = true; absorbed = 2; bump = nil; message = true; notified = true
    }

    private func play() async throws {
        try await nap(900)
        withAnimation(CLMotion.snap) { missed = true }
        try await nap(700)
        for step in 1...2 {
            withAnimation(CLMotion.pop) { absorbed = step; bump = step + 2 }
            try await nap(220)
            withAnimation(CLMotion.settle) { bump = nil }
            try await nap(80)
        }
        try await nap(300)
        withAnimation(CLMotion.settle) { message = true }
        try await nap(700)
        withAnimation(CLMotion.settle) { notified = true }
        try await nap(2800)
    }
}
#endif
