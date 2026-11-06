import SwiftUI

// Pieces the Library, course, source and exam screens share. Values come in ready-made (from the engine through
// AppModel); these views only draw them.

/// What a course card shows, read once per render of the Library.
struct LibraryCourseModel: Identifiable, Equatable {
    var id: UUID
    var name: String
    var color: CourseColor
    var symbol: String
    var examLine: String
    /// Readiness for the course's next exam (`AppModel.courseReadiness`), 0…1: the course's one number. Nil with no exam to come.
    var readiness: Double?
    /// That exam's title, for VoiceOver ("53 percent ready for the Midterm").
    var examTitle: String?
    var sources: Int
    var questions: Int

    @MainActor
    init(course: Course, app: AppModel) {
        id = course.id
        name = course.name
        color = course.color
        symbol = course.symbol
        let next = app.courseReadiness(course)
        examLine = LibraryFormat.examLine(title: next?.exam.title, courseName: course.name, date: next?.exam.date, now: app.now,
                                          calendar: app.calendar)
        readiness = next?.value
        examTitle = next?.exam.title
        sources = course.liveSources.count
        questions = course.activeItems.count
    }

    /// "53 percent ready for the Midterm" / "No exam date yet".
    var readinessAccessibility: String {
        guard let readiness, let examTitle else { return String(localized: "No exam date yet") }
        return LibraryFormat.ringAccessibility(value: readiness, examTitle: examTitle, courseName: name)
    }
}

/// A course on the Library: its badge, name, next exam and counts, with that exam's readiness ring. A course with no exam to come
/// keeps the ring's place for "Add a date": the card reserves it (`LibraryAddDateSlot`) and the Library lays the real button over
/// it, outside the card's link, so the two taps stay apart.
struct LibraryCourseCard: View {
    let model: LibraryCourseModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        CLIconBadge(systemImage: model.symbol, tint: model.color, size: 44)
                        Spacer()
                        trailing
                    }
                    Text(model.name).clFont(.headline).foregroundStyle(CLColor.ink)
                    Text(model.examLine).clFont(.subheadline).foregroundStyle(CLColor.ink2)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    CLIconBadge(systemImage: model.symbol, tint: model.color, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name).clFont(.headline).foregroundStyle(CLColor.ink)
                        Text(model.examLine).clFont(.subheadline).foregroundStyle(CLColor.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing
                }
            }
            Text(LibraryFormat.courseCounts(sources: model.sources, questions: model.questions))
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink3)
                .padding(.top, 10)
        }
        .clCard(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.name))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var trailing: some View {
        if let readiness = model.readiness {
            // Bigger at the accessibility text sizes, where the number inside it would otherwise stay small.
            ReadinessRing(value: readiness, size: typeSize.isAccessibilitySize ? 80 : 52, lineWidth: typeSize.isAccessibilitySize ? 8 : 6)
                .accessibilityHidden(true)
        } else {
            LibraryAddDateSlot()
        }
    }

    private var accessibilityValue: String {
        [model.examLine, model.readinessAccessibility, LibraryFormat.courseCounts(sources: model.sources, questions: model.questions)]
            .joined(separator: ", ")
    }
}

/// "Add a date": the button a course with no exam to come shows where its ring would be. It opens the exam editor for that course.
struct LibraryAddDateButton: View {
    let courseName: String
    var action: () -> Void

    var body: some View {
        Button {
            CLHaptics.tap()
            action()
        } label: {
            LibraryAddDateLabel()
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Add an exam date for \(courseName)"))
    }
}

private struct LibraryAddDateLabel: View {
    var body: some View {
        // An HStack rather than a Label: inside a List row a Label can lose its title to the row's label style.
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus").accessibilityHidden(true)
            Text("Add a date")
        }
            .clFont(.footnoteEmphasis)
            .foregroundStyle(CLColor.skyInk)
            .padding(.horizontal, 12)
            .frame(minHeight: CLMetrics.minHitTarget)
            .background(CLColor.skySoft, in: Capsule())
            .fixedSize()
    }
}

/// The place an "Add a date" button takes in a card: the label, hidden, with its bounds handed up (`LibraryAddDateAnchor`) so the
/// screen can put the real button exactly there, outside the card's own tap.
struct LibraryAddDateSlot: View {
    var body: some View {
        LibraryAddDateLabel()
            .hidden()
            .accessibilityHidden(true)
            .anchorPreference(key: LibraryAddDateAnchor.self, value: .bounds) { $0 }
    }
}

struct LibraryAddDateAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

extension View {
    /// Lays the "Add a date" button over the slot a card reserved for it (`LibraryAddDateSlot`), when it reserved one.
    func addDateOverlay(courseName: String, action: @escaping () -> Void) -> some View {
        overlayPreferenceValue(LibraryAddDateAnchor.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor]
                    LibraryAddDateButton(courseName: courseName, action: action)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }
}

/// A topic on the course page: its readiness for the next exam with a meter, a coverage gap with "Add material", or (not on that exam, or
/// no exam to come) just its questions. Only the first shows a number.
struct LibraryTopicRow: View {
    let name: String
    let state: LibraryFormat.TopicLine.State
    var questionCount: Int = 0
    var onAdd: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                switch state {
                case .value(let value):
                    Text(questionCount > 0 && value < 0.005 ? "New" : CLFormat.percent(value))
                        .clFont(.number(15, .bold))
                        .foregroundStyle(questionCount > 0 && value < 0.005 ? CLColor.ink3 : CLColor.ink)
                case .gap:
                    CLPill(text: "No material yet", tone: .rose)
                case .notOnExam, .noExam:
                    Text("\(questionCount) questions").clFont(.footnote).foregroundStyle(CLColor.ink3)
                }
            }
            if case .value(let value) = state {
                CLBar(value: value).accessibilityHidden(true)
            } else if case .gap = state, let onAdd {
                Button(action: onAdd) {
                    Label("Add material", systemImage: "plus")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                        .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        switch state {
        case .value(let value):
            if questionCount > 0 && value < 0.005 { return String(localized: "Not studied yet") }
            return String(localized: "\(Int((value * 100).rounded())) percent ready")
        case .gap: return String(localized: "No material yet")
        case .notOnExam(let exam): return String(localized: "Not on the \(exam)")
        case .noExam: return String(localized: "\(questionCount) questions")
        }
    }
}

/// One question in a list: its format, the prompt, and where it sits.
struct LibraryItemRow: View {
    let kind: ItemKind
    let prompt: String
    let detail: String
    var tint: CourseColor = .sky
    var suspended = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(alignment: .top, spacing: 12) {
            if !large {
                CLIconBadge(systemImage: kind.libraryIcon, tint: tint, size: 34)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(prompt)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(suspended ? CLColor.ink3 : CLColor.ink)
                    .lineLimit(large ? nil : 3)
                ReflowStack(spacing: 6) {
                    if suspended {
                        ReflowPill(text: "Suspended", tone: .neutral, systemImage: "pause.fill")
                    }
                    Text(detail).clFont(.footnote).foregroundStyle(CLColor.ink2).lineLimit(large ? nil : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the question to edit"))
    }
}

/// One source in a list: its kind's glyph, title and what's in it.
struct LibrarySourceRow: View {
    let kind: SourceKind
    let title: String
    let meta: String
    var tint: CourseColor = .sky
    /// Off inside a List, which draws its own.
    var showsChevron = true

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 12) {
            CLIconBadge(systemImage: kind.systemImage, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                Text(meta).clFont(.footnote).foregroundStyle(CLColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron { CLChevron() }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A section title inside a List (the app's section header, without the list's own header styling).
struct LibrarySectionTitle: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).clFont(.title3).foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .clFont(.subheadlineEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
                    .frame(minHeight: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
            }
        }
        .textCase(nil)
        .padding(.top, 8)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
    }
}

/// Marks `match` (character offsets) in `text` with the highlighter's key colour, for search rows.
func searchMarkedText(_ text: String, match: Range<Int>?) -> AttributedString {
    var result = AttributedString(text)
    guard let match, match.lowerBound >= 0, match.upperBound <= text.count, !match.isEmpty,
          let start = result.characters.index(result.startIndex, offsetBy: match.lowerBound, limitedBy: result.endIndex),
          let end = result.characters.index(result.startIndex, offsetBy: match.upperBound, limitedBy: result.endIndex)
    else { return result }
    result[start..<end].backgroundColor = CLColor.markKey
    return result
}

/// Lays children out side by side, or stacked when the text is at an accessibility size.
struct ReflowStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content }
    }
}

/// `CLPill`, except that when it doesn't fit on one line (a long name, large text) it wraps instead of truncating.
struct ReflowPill: View {
    let text: LocalizedStringResource
    var tone: CLPill.Tone = .neutral
    var systemImage: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            CLPill(text: text, tone: tone, systemImage: systemImage)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(.caption, weight: .bold)) }
                Text(text).font(.system(.caption, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(ink)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var ink: Color {
        switch tone {
        case .mint: CLColor.mintInk
        case .rose: CLColor.roseInk
        case .sun: CLColor.sunInk
        case .sky: CLColor.skyInk
        case .tangerine: CLColor.tangerineInk
        case .neutral: CLColor.ink2
        }
    }

    private var fill: Color {
        switch tone {
        case .mint: CLColor.mintSoft
        case .rose: CLColor.roseSoft
        case .sun: CLColor.sunSoft
        case .sky: CLColor.skySoft
        case .tangerine: CLColor.tangerineSoft
        case .neutral: CLColor.surface3
        }
    }
}

/// A button label: the first of `titles` that fits on one line with its glyph (the full title first, then shorter ones); when none does,
/// the shortest words alone, which the button style wraps.
struct FittingLabel: View {
    let titles: [String]
    let systemImage: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(titles, id: \.self) { title in
                Label(title, systemImage: systemImage).lineLimit(1)
            }
            // None fits on one line: the shortest words, wrapped as the button allows.
            Text(titles.last ?? "")
        }
    }
}

/// Short parts joined by a dot on one line when they fit ("2 days to go · Multiple choice"), otherwise one part to a line: a line never
/// ends on a hanging dot. Styled by whoever uses it (`.clFont`, `.foregroundStyle`).
struct DotLine: View {
    let parts: [String]
    var spacing: CGFloat = 2

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(verbatim: parts.joined(separator: " · ")).lineLimit(1)
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Text(verbatim: part).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
