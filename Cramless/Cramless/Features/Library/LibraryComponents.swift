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
    /// Mean current recall over studied questions, 0…1; nil before anything is studied.
    var mastery: Double?
    var sources: Int
    var questions: Int

    @MainActor
    init(course: Course, app: AppModel) {
        id = course.id
        name = course.name
        color = course.color
        symbol = course.symbol
        let startOfToday = app.calendar.startOfDay(for: app.now)
        let next = course.liveExams.first { $0.date >= startOfToday }
        examLine = LibraryFormat.examLine(title: next?.title, courseName: course.name, date: next?.date, now: app.now,
                                          calendar: app.calendar)
        let active = course.activeItems
        let studied = active.contains { $0.stateRaw != CardState.new.rawValue && $0.lastReview != nil }
        mastery = studied ? app.mastery(of: course) : nil
        sources = course.liveSources.count
        questions = active.count
    }
}

/// A course on the Library: its badge, name, next exam, mastery and counts.
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
                        masteryText
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
                    masteryText
                }
            }
            CLBar(value: model.mastery ?? 0)
                .padding(.top, 14)
                .accessibilityHidden(true)
            Text(LibraryFormat.courseCounts(sources: model.sources, questions: model.questions))
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink3)
                .padding(.top, 8)
        }
        .clCard(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(model.name))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var masteryText: some View {
        if let mastery = model.mastery {
            Text(CLFormat.percent(mastery)).clFont(.number(19)).foregroundStyle(CLColor.ink)
        } else {
            Text(model.questions == 0 ? "Empty" : "New").clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink3)
        }
    }

    private var accessibilityValue: String {
        var parts = [model.examLine]
        if let mastery = model.mastery { parts.append("\(CLFormat.percent(mastery)) mastery") } else { parts.append("Not studied yet") }
        parts.append(LibraryFormat.courseCounts(sources: model.sources, questions: model.questions))
        return parts.joined(separator: ", ")
    }
}

/// A mastery value with its bar: "Cell cycle ……… 92%" over a thin meter, or a coverage gap.
struct LibraryTopicRow: View {
    let name: String
    /// nil: a topic with no material yet.
    let value: Double?
    var itemCount: Int = 0
    var onAdd: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(itemCount > 0 && value == 0 ? "New" : CLFormat.percent(value))
                        .clFont(.number(15, .bold))
                        .foregroundStyle(itemCount > 0 && value == 0 ? CLColor.ink3 : CLColor.ink)
                } else {
                    CLPill(text: "No material yet", tone: .rose)
                }
            }
            if let value {
                CLBar(value: value).accessibilityHidden(true)
            } else if let onAdd {
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
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        guard let value else { return "No material yet" }
        if itemCount > 0 && value == 0 { return "Not studied yet" }
        return "\(CLFormat.percent(value)) mastery"
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

    var body: some View {
        HStack(spacing: 12) {
            CLIconBadge(systemImage: kind.systemImage, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink).lineLimit(2)
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

/// `CLPill`, except that at accessibility text sizes it wraps onto more lines instead of truncating.
struct ReflowPill: View {
    let text: LocalizedStringResource
    var tone: CLPill.Tone = .neutral
    var systemImage: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.system(.caption, weight: .bold)) }
                Text(text).font(.system(.caption, design: .rounded, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(ink)
            .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            CLPill(text: text, tone: tone, systemImage: systemImage)
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

/// A button label: the title with its glyph, or at accessibility text sizes the words alone (the button style wraps
/// them there), so the words keep the room. `titles` lists the full title first; shorter ones are kept for callers
/// that need a compact form.
struct FittingLabel: View {
    let titles: [String]
    let systemImage: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            Text(titles.first ?? "")
        } else {
            Label(titles.first ?? "", systemImage: systemImage)
        }
    }
}
