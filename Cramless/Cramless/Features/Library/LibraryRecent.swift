import SwiftUI

/// The Library's "Recent": sources with questions waiting for review first, then what was opened or added on this iPhone in the last two
/// weeks. Three rows at most, and none under two: one row isn't a list. Pure: the opens come in from `AppModel.libraryRecent()`.
enum LibraryRecent {
    static let windowDays = 14
    static let limit = 3
    static let minimum = 2

    struct Candidate: Equatable, Sendable {
        var id: UUID
        var title: String
        var kind: SourceKind
        var color: CourseColor
        /// Questions waiting for review.
        var drafts: Int
        var openedAt: Date?
        var addedAt: Date
    }

    enum Destination: Equatable, Sendable {
        case reviewDraft(UUID)
        case lecture(UUID)
        case source(UUID)
    }

    struct Row: Identifiable, Equatable, Sendable {
        var id: UUID
        var title: String
        var kind: SourceKind
        var color: CourseColor
        /// "14 questions to review", "PDF · opened today", "Lecture · added 9 days ago".
        var detail: String
        var destination: Destination
    }

    static func rows(_ candidates: [Candidate], now: Date, calendar: Calendar) -> [Row] {
        func latest(_ c: Candidate) -> Date { max(c.openedAt ?? .distantPast, c.addedAt) }
        let waiting = candidates.filter { $0.drafts > 0 }.sorted { latest($0) > latest($1) }
        let recent = candidates.filter { c in
            c.drafts == 0 && calendar.dayDistance(from: latest(c), to: now) <= windowDays
        }.sorted { latest($0) != latest($1) ? latest($0) > latest($1) : $0.title < $1.title }
        let picked = Array((waiting + recent).prefix(limit))
        guard picked.count >= minimum else { return [] }
        return picked.map { c in
            let destination: Destination = c.drafts > 0 ? .reviewDraft(c.id) : c.kind.opensLectureNotes ? .lecture(c.id) : .source(c.id)
            return Row(id: c.id, title: c.title, kind: c.kind, color: c.color, detail: detail(c, now: now, calendar: calendar),
                       destination: destination)
        }
    }

    static func detail(_ c: Candidate, now: Date, calendar: Calendar) -> String {
        if c.drafts > 0 { return String(localized: "\(c.drafts) questions to review") }
        let kind = LibraryFormat.sourceKindName(c.kind)
        let opened = (c.openedAt ?? .distantPast) >= c.addedAt
        let days = max(0, calendar.dayDistance(from: opened ? c.openedAt ?? c.addedAt : c.addedAt, to: now))
        let when: String
        switch (opened, days) {
        case (true, 0): when = String(localized: "opened today")
        case (true, 1): when = String(localized: "opened yesterday")
        case (true, _): when = String(localized: "opened \(days) days ago")
        case (false, 0): when = String(localized: "added today")
        case (false, 1): when = String(localized: "added yesterday")
        case (false, _): when = String(localized: "added \(days) days ago")
        }
        return "\(kind) · \(when)"
    }
}

/// The section on the Library, above the courses.
struct LibraryRecentSection: View {
    let rows: [LibraryRecent.Row]

    @Environment(AppModel.self) private var app

    var body: some View {
        CLSectionHeader(title: "Recent")
            .id("recent")
        CLList {
            ForEach(rows) { row in
                rowView(row)
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: LibraryRecent.Row) -> some View {
        let label = LibrarySourceRow(kind: row.kind, title: row.title, meta: row.detail, tint: row.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        switch row.destination {
        case .reviewDraft(let id):
            Button {
                CLHaptics.tap()
                app.router.present(.reviewDraft(sourceID: id))
            } label: { label }
            .buttonStyle(LibraryRowButtonStyle())
        case .lecture(let id):
            NavigationLink(value: Route.lectureNotes(id)) { label }
                .buttonStyle(LibraryRowButtonStyle())
        case .source(let id):
            NavigationLink(value: Route.source(id)) { label }
                .buttonStyle(LibraryRowButtonStyle())
        }
    }
}
