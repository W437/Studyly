import SwiftUI

// Today's cards below the sky hero (`TodaySkyHero`): the next exam, the other exams, Cap's note on a mix-up, ways to
// add material, and the header pieces. The day's one big action is the hero's button.

// MARK: - Exams

/// The next exam: its readiness ring, the date, this week's change.
struct TodayExamCard: View {
    let exam: TodayExam
    let onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        Button(action: onOpen) {
            layout {
                ReadinessRing(value: exam.readiness, size: 86, lineWidth: 10)
                VStack(alignment: .leading, spacing: 3) {
                    CLEyebrow(text: "Next exam")
                    Text(exam.title)
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(CLFormat.day(exam.date)) · \(CLFormat.daysLeft(exam.daysLeft))")
                        .clFont(.subheadline)
                        .foregroundStyle(CLColor.ink2)
                    deltaPill
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize { CLChevron() }
            }
            .clCard()
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next exam: \(exam.title), \(CLFormat.day(exam.date)), \(CLFormat.daysLeft(exam.daysLeft)) left")
        .accessibilityValue("\(CLFormat.percent(exam.readiness)) ready, \(deltaWords) this week")
    }

    private var deltaPill: some View {
        let points = Int((exam.delta * 100).rounded())
        return Group {
            if points > 0 {
                CLPill(text: "\(CLFormat.delta(exam.delta)) this week", tone: .mint, systemImage: "chart.line.uptrend.xyaxis")
            } else if points < 0 {
                CLPill(text: "\(CLFormat.delta(exam.delta)) this week", tone: .rose, systemImage: "chart.line.downtrend.xyaxis")
            } else {
                CLPill(text: "Steady this week", tone: .neutral, systemImage: "minus")
            }
        }
    }

    private var deltaWords: String {
        let points = Int((exam.delta * 100).rounded())
        return points == 0 ? "no change" : points > 0 ? "up \(points) points" : "down \(-points) points"
    }
}

/// The other upcoming exams, each with a small ring.
struct TodayOtherExams: View {
    let exams: [TodayExam]
    let onOpen: (UUID) -> Void

    var body: some View {
        CLList {
            ForEach(exams) { exam in
                Button { onOpen(exam.id) } label: {
                    HStack(spacing: 12) {
                        ReadinessRing(value: exam.readiness, size: 40, lineWidth: 5, showsLabel: false)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exam.title)
                                .clFont(.bodyEmphasis)
                                .foregroundStyle(CLColor.ink)
                            let soon = exam.daysLeft <= 3
                                ? Text(" · soon").fontWeight(.semibold).foregroundStyle(CLColor.roseInk) : Text("")
                            let line = Text("\(CLFormat.day(exam.date)) · \(CLFormat.percent(exam.readiness)) ready")
                                .foregroundStyle(CLColor.ink2)
                            Text("\(line)\(soon)")
                                .clFont(.footnote)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        CLChevron()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(minHeight: CLMetrics.rowMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Cap's note

/// "You keep mixing up anaphase and telophase. Missed 3 of the last 4 times. Want a 2-minute fix?"
struct TodayCapNote: View {
    let note: ConfusionNote
    let onFix: () -> Void
    let onLater: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CapFace(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Button(action: onOpen) {
                    Text(SessionCopy.mixUpLine(note.name))
                        .clFont(.headline)
                        .foregroundStyle(CLColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the mix-up")
                Text(SessionCopy.missLine(note))
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("Fix it now", action: onFix)
                        .buttonStyle(.cl(.dark, size: .medium, fullWidth: false))
                    Button("Later", action: onLater)
                        .buttonStyle(.cl(.ghost, size: .medium, fullWidth: false))
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard()
    }
}

// MARK: - Add material

struct TodayQuickAdd: View {
    let onScan: () -> Void
    let onPDF: () -> Void
    let onLecture: () -> Void
    let onPaste: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 10) {
            tile("Scan", symbol: "camera", tint: .tangerine, action: onScan)
            tile("PDF", symbol: "doc.richtext", tint: .sky, action: onPDF)
            tile("Lecture", symbol: "mic", tint: .rose, action: onLecture)
            tile("Paste", symbol: "doc.on.clipboard", tint: .mint, action: onPaste)
        }
    }

    private func tile(_ title: String, symbol: String, tint: CourseColor, action: @escaping () -> Void) -> some View {
        Button {
            CLHaptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint.ink)
                    .frame(width: 40, height: 40)
                    .background(tint.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 10, y: 6)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(accessibility(title))
    }

    private func accessibility(_ title: String) -> String {
        switch title {
        case "Scan": "Scan pages"
        case "PDF": "Add a PDF"
        case "Lecture": "Record a lecture"
        default: "Paste text"
        }
    }
}

// MARK: - Header pieces

/// The streak in a glass pill: the flame and the days. Hidden until there's a streak to show.
struct TodayStreakPill: View {
    let streak: StreakState
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 15, weight: .bold))
                Text("\(streak.current)")
                    .clFont(.number(17, .heavy))
                if streak.freezesAvailable > 0 {
                    Image(systemName: "snowflake")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CLColor.skyInk)
                        .padding(.leading, 3)
                }
            }
            .foregroundStyle(CLColor.tangerineInk)
            .padding(.horizontal, 13)
            .frame(minHeight: 38)
            .glassEffect(.regular.interactive(), in: Capsule())
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(streak.current)-day streak")
        .accessibilityValue(streak.freezesAvailable > 0
            ? "\(streak.freezesAvailable) streak freeze\(streak.freezesAvailable == 1 ? "" : "s") saved" : "")
        .accessibilityHint("Opens your streak")
    }
}

/// The person's initials on tangerine (Night ink: brand fills never take white); opens Settings.
struct TodayAvatar: View {
    let initials: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Circle().fill(CLColor.tangerine)
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text(initials)
                        .clFont(.number(15, .bold))
                }
            }
            .foregroundStyle(CLColor.onFill)
            .frame(width: 38, height: 38)
            .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
            .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Profile and settings")
    }
}
