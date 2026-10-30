import SwiftUI

/// Flashcards or questions Cap is writing, or has written: a row for each, appearing as it is written, then checked against
/// the student's notes one at a time. Before the student adds anything they can untick a row or change its words.
///
/// What each row says about itself, because Cap's word is not enough:
///  - **From your notes**: the quote Cap gave is really in the notes; the row names the page.
///  - **Cap's own words**: nothing in the notes backs it. It is kept (the student asked, or Cap had to) and marked, never
///    passed off as checked.
struct DraftsStepView: View {
    let step: AssistantStep
    let actions: AssistantStepActions
    var animated = false

    @State private var editing: UUID?
    @State private var showAll = false
    @State private var editFront = ""
    @State private var editBack = ""

    /// One draft, whichever kind.
    struct Row: Identifiable {
        var id: UUID
        var title: String
        var detail: String
        var kindLabel: String?
        var options: [String]
        var correct: Int?
        var basis: DraftBasis
        var kept: Bool
        var isDuplicate: Bool
    }

    private var rows: [Row] {
        switch step.payload {
        case .cards(let cards):
            return cards.map { Row(id: $0.id, title: $0.front, detail: $0.back, kindLabel: nil, options: [], correct: nil, basis: $0.basis,
                                   kept: $0.kept, isDuplicate: $0.isDuplicate) }
        case .questions(let questions):
            return questions.map { q in
                let answer = q.kind == .fillBlank ? q.prompt.replacingOccurrences(of: #"\{\{([^}]*)\}\}"#, with: "▢", options: .regularExpression) : q.prompt
                return Row(id: q.id, title: answer, detail: q.kind == .multipleChoice ? "" : q.answer, kindLabel: q.kind.title, options: q.choices,
                           correct: q.correctIndex, basis: q.basis, kept: q.kept, isDuplicate: q.isDuplicate)
            }
        default:
            return []
        }
    }

    private var noun: String { step.tool == .createFlashcards ? "flashcard" : "question" }
    private var working: Bool { step.status == .working }
    private var checked: Int { rows.filter { $0.basis != .checking }.count }
    private var kept: Int { rows.filter(\.kept).count }
    private var open: Bool { step.status == .proposed && !actions.isLive }

    var body: some View {
        let all = rows
        // While the model writes, the newest four are shown (the list rolls up); once the checks begin, and after, the first four, so
        // the card keeps one shape from the first check to the proposal.
        let writing = working && step.checking != true
        let limit = working ? 4 : (showAll || editing != nil ? all.count : 4)
        let visible = writing ? Array(all.suffix(limit)) : Array(all.prefix(limit))
        StepCard(step: step, actions: actions,
                 addTitle: kept == 0 ? "Pick one to add" : "Add \(CLFormat.count(kept, noun))",
                 addEnabled: kept > 0,
                 subtitle: subtitle(all)) {
            VStack(alignment: .leading, spacing: 8) {
                if writing, all.count > visible.count {
                    Text("\(all.count - visible.count) written above").clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                if working, all.isEmpty { DraftPlaceholder() }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    DraftRowView(row: row, editable: open, isEditing: editing == row.id, inCheck: step.checking == true,
                                 front: $editFront, back: $editBack,
                                 onToggle: { toggle(row.id) }, onEdit: { begin(row) }, onDone: { commit(row) })
                        .transition(animated
                            ? .asymmetric(insertion: .scale(scale: 0.94, anchor: .topLeading).combined(with: .opacity).combined(with: .offset(y: 12)),
                                          removal: .opacity)
                            : .identity)
                }
                if working, !writing, all.count > visible.count {
                    Text("+\(all.count - visible.count) more").clFont(.caption).foregroundStyle(CLColor.ink3)
                }
                if !working, all.count > 4, editing == nil {
                    Button(showAll ? "Show fewer" : "Show all \(all.count)") { withAnimation(CLMotion.settle) { showAll.toggle() } }
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.skyInk)
                        .buttonStyle(.plain)
                        .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
                }
                caption(all)
            }
            .animation(animated ? CLMotion.pop : nil, value: all.count)
            .animation(animated ? CLMotion.settle : nil, value: step.checking)
            .animation(animated ? CLMotion.settle : nil, value: checked)
        }
        .onChange(of: all.count) { old, new in
            if animated, working, new > old { CLFeel.play(.cardOut(new - 1)) }
        }
        .onChange(of: checked) { old, new in
            if animated, new > old, all.indices.contains(new - 1), all[new - 1].basis.isFromNotes { CLFeel.play(.right(combo: new)) }
        }
        .onChange(of: step.status) { old, new in
            if animated, new == .applied, old != .applied { CLFeel.play(.saved) }
        }
    }

    private func subtitle(_ all: [Row]) -> String? {
        // (The topic is in the title already when it reads "6 flashcards on Mitosis".)
        let topic = step.topicName.flatMap { step.title.contains($0) ? nil : $0 }
        var parts = [step.courseName, topic].compactMap { $0?.clNonEmpty }
        let own = all.filter { $0.basis == .own }.count
        if step.status != .working, own > 0 { parts.append("\(own) not from your notes") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What the colours mean, once the checks are in. (While the work is going on, the line under the card says what Cap is doing.)
    @ViewBuilder
    private func caption(_ all: [Row]) -> some View {
        if !working, all.contains(where: { $0.basis.isFromNotes }) && all.contains(where: { $0.basis == .own }) {
            HStack(spacing: 14) {
                Label("From your notes", systemImage: "checkmark.seal.fill").foregroundStyle(CLColor.mintInk)
                Label("Cap's own words", systemImage: "bubble.left").foregroundStyle(CLColor.sunInk)
            }
            .clFont(.caption)
            .padding(.top, 2)
        }
    }

    // MARK: Changing a draft

    private func toggle(_ id: UUID) {
        CLHaptics.select()
        actions.edit?(step) { s in
            switch s.payload {
            case .cards(var c): if let i = c.firstIndex(where: { $0.id == id }) { c[i].kept.toggle() }; s.payload = .cards(c)
            case .questions(var q): if let i = q.firstIndex(where: { $0.id == id }) { q[i].kept.toggle() }; s.payload = .questions(q)
            default: break
            }
        }
    }

    private func begin(_ row: Row) {
        CLHaptics.tap()
        editFront = row.title
        editBack = row.detail
        withAnimation(CLMotion.settle) { editing = row.id }
    }

    private func commit(_ row: Row) {
        let front = editFront.clTrimmed
        let back = editBack.clTrimmed
        withAnimation(CLMotion.settle) { editing = nil }
        guard !front.isEmpty else { return }
        actions.edit?(step) { s in
            switch s.payload {
            case .cards(var c):
                if let i = c.firstIndex(where: { $0.id == row.id }), !back.isEmpty { c[i].front = front; c[i].back = back }
                s.payload = .cards(c)
            case .questions(var q):
                if let i = q.firstIndex(where: { $0.id == row.id }) {
                    // A blank must stay a blank; a choice question keeps its options.
                    if q[i].kind != .fillBlank || front.contains("{{") { q[i].prompt = front }
                    if q[i].kind == .shortAnswer, !back.isEmpty { q[i].answer = back }
                }
                s.payload = .questions(q)
            default: break
            }
        }
    }
}

/// One draft.
private struct DraftRowView: View {
    let row: DraftsStepView.Row
    let editable: Bool
    let isEditing: Bool
    /// The app is checking the drafts now (not still being written): an unchecked row says so and shimmers.
    let inCheck: Bool
    @Binding var front: String
    @Binding var back: String
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 4) {
                if let label = row.kindLabel {
                    Text(label).clFont(.eyebrow).foregroundStyle(CLColor.ink3)
                }
                if isEditing { editor } else { reading }
                basisLine
            }
            if editable, !isEditing, row.kindLabel == nil || row.options.isEmpty {
                Button(action: onEdit) {
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(CLColor.ink3)
                        .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -10)
                .padding(.top, -10)
                .accessibilityLabel("Edit")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(row.basis == .checking && inCheck ? CLColor.surface2.opacity(0.7) : CLColor.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .workingShimmer(row.basis == .checking && inCheck)
        .opacity(row.kept ? 1 : 0.55)
        .animation(CLMotion.snap, value: row.kept)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(accessibilityState))
    }

    private var accessibilityState: String {
        switch row.basis {
        case .checking: inCheck ? "Checking" : "Just written"
        case .notes(let e): "From your notes, \(e.label)"
        case .own: "Not from your notes"
        }
    }

    @ViewBuilder private var leading: some View {
        if editable {
            Button(action: onToggle) {
                ZStack {
                    Circle().strokeBorder(row.kept ? CLColor.tangerine : CLColor.surface3, lineWidth: 2.5)
                    if row.kept {
                        Circle().fill(CLColor.tangerine)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(CLColor.onFill)
                    }
                }
                .frame(width: 24, height: 24)
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -10)
            .padding(.top, -10)
            .padding(.trailing, -6)
            .accessibilityLabel(Text(row.kept ? "Keep this one" : "Leave this one out"))
            .accessibilityAddTraits(row.kept ? .isSelected : [])
        } else {
            DrawnCheck(done: row.basis.isFromNotes, tint: CLColor.mint, size: 22)
                .overlay {
                    if row.basis == .own {
                        Image(systemName: "bubble.left.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(CLColor.sunInk)
                    }
                }
        }
    }

    @ViewBuilder private var reading: some View {
        Text(verbatim: row.title)
            .clFont(.subheadlineEmphasis)
            .foregroundStyle(CLColor.ink)
            .fixedSize(horizontal: false, vertical: true)
        if !row.options.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(row.options.enumerated()), id: \.offset) { i, option in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: i == row.correct && row.basis != .checking ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(i == row.correct && row.basis != .checking ? CLColor.mintInk : CLColor.ink4)
                        Text(verbatim: option).clFont(.footnote).foregroundStyle(i == row.correct ? CLColor.ink : CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else if !row.detail.isEmpty {
            Text(verbatim: row.detail).clFont(.footnote).foregroundStyle(CLColor.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Front", text: $front)
            if row.options.isEmpty { field("Back", text: $back) }
            Button("Done", action: onDone)
                .buttonStyle(.cl(.soft, size: .small, fullWidth: false))
        }
    }

    private func field(_ title: LocalizedStringResource, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).clFont(.caption).foregroundStyle(CLColor.ink3)
            TextField("", text: text, axis: .vertical)
                .clFont(.subheadline)
                .lineLimit(1...6)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(CLColor.surface, in: RoundedRectangle(cornerRadius: CLRadius.field, style: .continuous))
        }
    }

    @ViewBuilder private var basisLine: some View {
        switch row.basis {
        case .checking:
            // A card that has just been written is not being checked yet: it says nothing until the checks begin.
            if inCheck { Text("Checking…").clFont(.caption).foregroundStyle(CLColor.ink3) }
        case .notes(let evidence):
            CLSourceChip(label: evidence.label)
                .scaleEffect(0.92, anchor: .leading)
                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
        case .own:
            CLPill(text: "Cap's own words, not from your notes", tone: .sun, systemImage: "bubble.left")
                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
        }
        if row.isDuplicate {
            Text("Already in this course").clFont(.caption).foregroundStyle(CLColor.ink3)
        }
    }
}

/// Where the first draft will appear: two quiet lines with a sheen across them, while the model decides what to write.
private struct DraftPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(CLColor.surface3).frame(width: 190, height: 12)
            Capsule().fill(CLColor.surface3.opacity(0.7)).frame(height: 10)
            Capsule().fill(CLColor.surface3.opacity(0.7)).frame(width: 120, height: 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface2.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .workingShimmer(true)
        .accessibilityHidden(true)
    }
}
