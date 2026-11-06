import SwiftUI

// The pieces of a tutor chat: Cap's Markdown, the two kinds of bubble, citation chips, the quick check, the
// "Cap is reading" bubble, the composer, Cap's style switch and the course chip. `ChatPane` puts them together.

// MARK: - Markdown

/// Cap's Markdown as views: paragraphs with bold and italic, bullet and numbered lists, small tables. At the
/// accessibility text sizes, and with the wide dyslexia-friendly font, a table becomes one card per row, so no word
/// is broken across a narrow column.
struct CapMarkdownView: View {
    let text: String
    /// Draws a caret after the last word while the answer is still arriving.
    var streaming = false

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.clDyslexicFont) private var dyslexic

    var body: some View {
        let blocks = CapMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, isLast: index == blocks.count - 1)
            }
            if streaming, !(blocks.last.map(Self.endsInText) ?? false) {
                StreamingCaret()
            }
        }
    }

    private static func endsInText(_ block: CapMarkdown.Block) -> Bool {
        if case .paragraph = block { return true }
        return false
    }

    @ViewBuilder
    private func blockView(_ block: CapMarkdown.Block, isLast: Bool) -> some View {
        switch block {
        case .paragraph(let line):
            if streaming && isLast {
                StreamingParagraph(text: line)
            } else {
                Text(CapMarkdown.inline(line))
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .heading(let line):
            Text(CapMarkdown.inline(line)).clFont(.headline).foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    listRow(marker: "\(i + 1).", text: item)
                }
            }
        case .table(let header, let rows):
            if typeSize.isAccessibilitySize || dyslexic {
                StackedTable(header: header, rows: rows)
            } else {
                CompactTable(header: header, rows: rows)
            }
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).clFont(.body).foregroundStyle(CLColor.ink3)
            Text(CapMarkdown.inline(text)).clFont(.body).foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A caret blinking after streamed text (still under Reduce Motion).
private struct StreamingCaret: View {
    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            RoundedRectangle(cornerRadius: 1.5)
                .fill(CLColor.tangerine)
                .frame(width: 3, height: 17)
                .opacity(on ? 1 : 0.15)
        }
        .accessibilityHidden(true)
    }
}

/// The paragraph being written, with the caret right after its last word.
private struct StreamingParagraph: View {
    let text: String
    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text(Self.withCaret(text, visible: on))
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func withCaret(_ text: String, visible: Bool) -> AttributedString {
        var out = CapMarkdown.inline(text)
        var caret = AttributedString(" \u{258D}")
        caret.foregroundColor = CLColor.tangerine.opacity(visible ? 1 : 0.15)
        out += caret
        return out
    }
}

/// A small table as a grid: the header in small caps-like semibold, hairlines between rows.
private struct CompactTable: View {
    let header: [String]?
    let rows: [[String]]

    var body: some View {
        let columns = max(header?.count ?? 0, rows.map(\.count).max() ?? 0)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
            if let header {
                GridRow {
                    ForEach(0..<columns, id: \.self) { i in
                        Text(CapMarkdown.inline(i < header.count ? header[i] : ""))
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(CLColor.ink2)
                            .padding(.vertical, 7)
                    }
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().overlay(CLColor.hairline)
                GridRow {
                    ForEach(0..<columns, id: \.self) { i in
                        let isRowLabel = i == 0 && header?.first?.isEmpty != false
                        Text(CapMarkdown.inline(i < row.count ? row[i] : ""))
                            .clFont(isRowLabel ? .subheadlineEmphasis : .subheadline)
                            .foregroundStyle(i == 0 ? CLColor.ink2 : CLColor.ink)
                            // A row's label keeps its words whole; the other columns wrap.
                            .fixedSize(horizontal: isRowLabel, vertical: true)
                            .padding(.vertical, 7)
                    }
                }
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(CapMarkdown.plain(tableMarkdown)))
    }

    private var tableMarkdown: String {
        var lines: [String] = []
        if let header { lines.append("| " + header.joined(separator: " | ") + " |"); lines.append("|---|") }
        lines += rows.map { "| " + $0.joined(separator: " | ") + " |" }
        return lines.joined(separator: "\n")
    }
}

/// A table at the accessibility sizes: a card per row, each cell under its column's name.
private struct StackedTable: View {
    let header: [String]?
    let rows: [[String]]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                        let name = header.flatMap { i < $0.count ? $0[i] : nil } ?? ""
                        if i == 0 && name.isEmpty {
                            Text(CapMarkdown.inline(cell)).clFont(.headline).foregroundStyle(CLColor.ink)
                        } else {
                            Text(CapMarkdown.inline(name.isEmpty ? cell : "**\(name)**: \(cell)"))
                                .clFont(.body).foregroundStyle(CLColor.ink)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

// MARK: - Bubbles

/// The person's message, on the right.
struct UserBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .clFont(.body)
            .foregroundStyle(CLColor.onFill)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text("You: \(text)"))
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(CLColor.tangerine, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22,
                                                                     bottomTrailingRadius: 8, topTrailingRadius: 22,
                                                                     style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 44)
    }
}

/// Cap's bubble shape and fill, on the left.
struct CapBubbleBackground: ViewModifier {
    var tint: Color = CLColor.surface

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(tint, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 8,
                                                         bottomTrailingRadius: 22, topTrailingRadius: 22,
                                                         style: .continuous))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 10, y: 6)
    }
}

extension View {
    func capBubble(tint: Color = CLColor.surface) -> some View { modifier(CapBubbleBackground(tint: tint)) }
}

/// "Cap is reading your notes": three dots while the answer hasn't started.
struct CapThinkingBubble: View {
    @Environment(\.clReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 0.18)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.18) % 6
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(CLColor.ink3)
                            .frame(width: 7, height: 7)
                            .offset(y: reduceMotion ? 0 : (step == i * 2 || step == i * 2 + 1 ? -3 : 0))
                            .opacity(reduceMotion ? 0.7 : (step / 2 == i ? 1 : 0.45))
                    }
                }
                .animation(CLMotion.snap, value: step)
            }
            Text("Reading your notes")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink3)
        }
        .capBubble()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cap is reading your notes"))
    }
}

// MARK: - Citations

/// A source chip, tappable: the page with the quote highlighted, or the lecture at that moment.
struct CitationChipButton: View {
    let group: CitationGroup
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CLSourceChip(label: group.label, systemImage: group.isLecture ? "mic" : "book.pages")
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text("Source: \(group.label)"))
        .accessibilityHint(Text(group.isLecture ? "Opens the lecture at this moment" : "Opens the page with the quote highlighted"))
    }
}

/// Citations that share a label ("Textbook p. 87" twice) as one chip, keeping every quote for the highlight.
struct CitationGroup: Identifiable, Hashable {
    var label: String
    var citations: [Citation]
    var id: String { label }
    var isLecture: Bool { citations.first?.start != nil && citations.first?.pageIndex == nil }

    static func groups(_ citations: [Citation]) -> [CitationGroup] {
        var out: [CitationGroup] = []
        for citation in citations {
            if let i = out.firstIndex(where: { $0.label == citation.label }) {
                out[i].citations.append(citation)
            } else {
                out.append(CitationGroup(label: citation.label, citations: [citation]))
            }
        }
        return out
    }
}

/// Who answered, when it wasn't the cloud: said plainly under the answer.
struct OriginNote: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label {
            Text(text).clFont(.caption).foregroundStyle(CLColor.ink3).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)).foregroundStyle(CLColor.ink3)
        }
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
    }

    /// The honest line for an answer's origin; nil for the cloud (the default) and for answers that quote nothing.
    static func line(origin: ItemOrigin?, note: String?, quotesNotes: Bool) -> (text: String, icon: String)? {
        if let note, !note.isEmpty { return (note, "info.circle") }
        switch origin {
        case .onDevice: return ("Answered on this iPhone", "iphone")
        case .rules: return quotesNotes ? ("From your notes, no AI", "text.book.closed") : nil
        default: return nil
        }
    }
}

// MARK: - Quick check

/// Cap's closing question, answerable in place: tap an option, or type an answer. Answering sends it to Cap.
struct QuickCheckCard: View {
    let check: QuickCheck
    /// Only the latest answer's quick check takes an answer; earlier ones show what was picked.
    let isActive: Bool
    /// The person's reply, once there is one.
    let answered: String?
    let onAnswer: (String) -> Void

    @State private var typed = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(check.isLabelled ? "Quick check" : "Your turn",
                  systemImage: check.isLabelled ? "checkmark.circle" : "lightbulb")
                .clFont(.eyebrow)
                .foregroundStyle(check.isLabelled ? CLColor.tangerineInk : CLColor.skyInk)
            Text(CapMarkdown.inline(check.question))
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !check.options.isEmpty {
                options
            } else if isActive && answered == nil {
                field
            }
        }
        .capBubble()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 28)
    }

    private var options: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { optionButtons }
            VStack(spacing: 8) { optionButtons }
        }
    }

    @ViewBuilder private var optionButtons: some View {
        ForEach(check.options, id: \.self) { option in
            let chosen = answered.map { Lexicon.normalizedAnswer($0) == Lexicon.normalizedAnswer(option) } ?? false
            Button {
                CLHaptics.select()
                onAnswer(option)
            } label: {
                Text(option)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(CLColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                    .background(chosen ? CLColor.surface : CLColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(chosen ? CLColor.ink : CLColor.surface3, lineWidth: 2))
            }
            .buttonStyle(.pressable)
            .disabled(!isActive || answered != nil)
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityHint(Text("Sends this answer to Cap"))
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField("Your answer", text: $typed)
                .clFont(.body)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submit)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CLColor.onFill)
                    .frame(width: 36, height: 36)
                    .background(CLColor.tangerine, in: Circle())
                    .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
            }
            .buttonStyle(.pressable)
            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            .accessibilityLabel("Send answer")
        }
    }

    private func submit() {
        let answer = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        typed = ""
        focused = false
        onAnswer(answer)
    }
}

// MARK: - A better path

/// The consent or paywall offer an answer carries ("Cap answered from your notes. Cloud AI can explain more").
struct AISuggestionCard: View {
    let suggestion: AISuggestion
    /// False where nothing is sold (a sheet opened from a session, Explain my mistake): a free limit is a line with no button and no
    /// link out. The consent offers keep their buttons.
    var allowsUpgrade = true
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CLIconBadge(systemImage: icon, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let title = Self.buttonTitle(for: suggestion, allowsUpgrade: allowsUpgrade) {
                    Button(title, action: action)
                        .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
                }
                if case .upgrade = suggestion, allowsUpgrade {
                    HelpLink()
                        .padding(.top, -6)
                }
            }
        }
        .clCard(padding: 14, radius: 22, flat: true)
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch suggestion {
        case .allowCloud, .allowPhotos: "sparkles"
        case .upgrade: "bolt.fill"
        }
    }

    private var tint: CourseColor {
        switch suggestion {
        case .allowCloud, .allowPhotos: .sky
        case .upgrade: .tangerine
        }
    }

    private var message: String {
        switch suggestion {
        case .allowCloud:
            "Cap answered from your notes on this iPhone. With Cloud AI, Cap can explain in its own words, still citing your notes."
        case .allowPhotos:
            "Cloud AI can read handwriting and diagrams if you let it see page photos."
        case .upgrade(_, let message):
            message
        }
    }

    /// The card's button; none for a free limit where nothing is sold.
    static func buttonTitle(for suggestion: AISuggestion, allowsUpgrade: Bool) -> LocalizedStringResource? {
        switch suggestion {
        case .allowCloud: "Turn on Cloud AI"
        case .allowPhotos: "Send page photos"
        case .upgrade: allowsUpgrade ? "See Pro" : nil
        }
    }
}

// MARK: - Composer

/// The ground under the composer: the screen's own colour with a hairline on top, down to the bottom edge, so the conversation
/// scrolls away under it instead of showing through the glass. (The pattern of Explain my mistake's bottom bar.)
struct AskDock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(alignment: .top) {
                CLColor.background
                    .overlay(alignment: .top) { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
                    .ignoresSafeArea(edges: .bottom)
            }
    }
}

/// The glass composer pinned above the keyboard. While Cap answers, send becomes stop. In Ask's chat it holds Cap's style (`showsMode`).
struct ChatComposer: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let isAnswering: Bool
    var placeholder: LocalizedStringKey = "Ask about your notes…"
    /// The chat, for Cap's style.
    var thread: ChatThread? = nil
    var showsMode = false
    /// The slot for a camera at the field's start: shown once there is something to do with it.
    var onCamera: (() -> Void)? = nil
    let onSend: () -> Void
    let onStop: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        // At the accessibility text sizes Cap's style has a line of its own, so the field keeps the width.
        VStack(alignment: .leading, spacing: 0) {
            if showsMode, typeSize.isAccessibilitySize {
                TutorModePill(thread: thread)
                    .padding(.leading, 12)
                    .padding(.top, 4)
            }
            row
        }
        .animation(CLMotion.snap, value: isAnswering)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private var row: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if let onCamera {
                Button(action: onCamera) {
                    Image(systemName: "camera")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CLColor.ink2)
                        .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .padding(.leading, 3)
                .padding(.bottom, 3)
                .accessibilityLabel("Snap a problem")
            }
            TextField(placeholder, text: $text, axis: .vertical)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .lineLimit(1...5)
                .focused(focused)
                .submitLabel(.send)
                // A field that grows to five lines takes Return as a new line; a typed Return sends instead (a
                // pasted passage keeps its line breaks).
                .onChange(of: text) { old, new in
                    guard new.count == old.count + 1, new.filter({ $0 == "\n" }).count == old.filter({ $0 == "\n" }).count + 1 else { return }
                    text = old
                    if canSend && !isAnswering { onSend() }
                }
                .padding(.leading, onCamera == nil ? 16 : 2)
                .padding(.vertical, 12)
                .accessibilityLabel("Question for Cap")
            if showsMode, !typeSize.isAccessibilitySize {
                TutorModePill(thread: thread)
                    .padding(.bottom, 3)
            }
            Group {
                if isAnswering {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CLColor.ink)
                            .frame(width: 38, height: 38)
                            .background(CLColor.surface3, in: Circle())
                    }
                    .accessibilityLabel("Stop Cap")
                    .accessibilityHint("Keeps what Cap has written so far")
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CLColor.onFill)
                            .frame(width: 38, height: 38)
                            .background(CLColor.tangerine.opacity(canSend ? 1 : 0.45), in: Circle())
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                    .accessibilityHint("Asks Cap, who answers from your notes")
                }
            }
            .buttonStyle(.pressable)
            .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
            .padding(.trailing, 3)
            .padding(.bottom, 3)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Cap's style

/// "Hints first" or "Just explain", in the composer: a tap opens the two with a line on each. Locked on hints first for under-18 accounts,
/// with the reason.
///
/// DEBUG: `CRAMLESS_ASK_MODE=open` opens it as the chat appears.
struct TutorModePill: View {
    let thread: ChatThread?

    @Environment(AppModel.self) private var app
    @State private var open = false

    var body: some View {
        let locked = app.settings.isMinor
        let mode = app.settings.effectiveTutorMode
        Button {
            CLHaptics.tap()
            open = true
        } label: {
            HStack(spacing: 4) {
                if locked { Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)) }
                Text(mode == .hints ? "Hints first" : "Just explain")
                    .clFont(.footnoteEmphasis)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(CLColor.ink2)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(CLColor.surface2, in: Capsule())
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cap's style")
        .accessibilityValue(mode == .hints ? Text("Hints first") : Text("Just explain"))
        .accessibilityHint(locked ? Text("Hints first stays on for accounts under 18.") : Text("Choose how Cap answers"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                row(.hints, title: "Hints first", detail: "Cap asks you a question back", selected: mode == .hints, locked: false)
                row(.explain, title: "Just explain", detail: "Straight to the answer", selected: mode == .explain, locked: locked)
                if locked {
                    Label("Hints first stays on for accounts under 18, so Cap helps you work it out.", systemImage: "lock.fill")
                        .clFont(.caption)
                        .foregroundStyle(CLColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
            .padding(8)
            .frame(width: 300)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .presentationCompactAdaptation(.popover)
        }
        #if DEBUG
        .task {
            if TestHarness.once("CRAMLESS_ASK_MODE") == "open" {
                try? await nap(600)
                open = true
            }
        }
        #endif
    }

    private func row(_ value: TutorMode, title: LocalizedStringResource, detail: LocalizedStringResource, selected: Bool, locked: Bool) -> some View {
        Button {
            choose(value)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).clFont(.bodyEmphasis).foregroundStyle(locked ? CLColor.ink4 : CLColor.ink)
                    Text(detail).clFont(.footnote).foregroundStyle(locked ? CLColor.ink4 : CLColor.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(CLColor.ink4)
                } else if selected {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(CLColor.tangerineInk)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ value: TutorMode) {
        open = false
        guard value != app.settings.effectiveTutorMode, !(app.settings.isMinor && value == .explain) else { return }
        CLHaptics.select()
        app.setTutorMode(value, in: thread)
    }
}

// MARK: - Course and material

/// The chat's title and, under it, "Bio 101 · 3 sources": which course's material Cap answers from. All of it is a menu to pick another
/// course or all of them.
struct AskTitleMenu: View {
    let title: String
    let courseID: UUID?
    let onPick: (UUID?) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        let _ = app.revision
        let courses = app.courses
        let count = app.readableSources(courseID: courseID).count
        let name = app.liveCourse(courseID)?.name ?? "All courses"
        let sources = count == 0 ? "no notes yet" : CLFormat.count(count, "source")
        Menu {
            Picker("Answer from", selection: Binding(get: { courseID }, set: { pick($0) })) {
                ForEach(courses) { course in
                    Label(course.name, systemImage: course.symbol).tag(Optional(course.id))
                }
                Label("All courses", systemImage: "square.stack.3d.up").tag(UUID?.none)
            }
        } label: {
            VStack(spacing: 1) {
                Text(verbatim: title)
                    .clFont(.headline)
                    .foregroundStyle(CLColor.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(name) · \(sources)")
                        .clFont(.caption)
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(CLColor.ink3)
            }
            .frame(minHeight: CLMetrics.minHitTarget)
            .contentShape(Rectangle())
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text("Answering from \(name), \(sources)"))
        .accessibilityHint(Text("Choose which course's material Cap answers from"))
    }

    private func pick(_ id: UUID?) {
        guard id != courseID else { return }
        CLHaptics.select()
        onPick(id)
    }
}

/// A suggestion under the chat: "Quiz me on this", "Explain with an analogy", "Make cards from this".
struct SuggestionChip: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CLChip(title: .verbatim(title), systemImage: systemImage)
                .frame(minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}
