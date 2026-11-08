import SwiftUI

/// Who in the person's Squad has studied today, as Today's line under the quests row says it. Kept for the day on this phone; only the people who chose to share say anything.
struct SquadToday: Codable, Equatable, Sendable {
    struct Friend: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        /// Nil: they don't share it.
        var studied: Bool?
    }

    /// The day it was read.
    var day: String
    var readAt: Date
    /// Everyone but the person.
    var friends: [Friend]

    /// The Squad without the person asking: by their id, or, when they own it, the owner's seat.
    static func friends(in members: SquadMembers, me: String?, owner: Bool) -> [Friend] {
        members.members.filter { $0.id != me && !(owner && $0.isOwner) }.map { Friend(id: $0.id, name: $0.name, studied: $0.studiedToday) }
    }

    /// "Priya studied today", "Priya and Sam studied today". When people share and none has yet, it says so plainly. When nobody shares, it's the way to the Squad.
    var line: String {
        let studied = friends.filter { $0.studied == true }.map(\.name)
        if !studied.isEmpty { return SquadCopy.studied(studied) }
        return friends.contains { $0.studied != nil } ? String(localized: "No one in your Squad has studied yet today")
            : String(localized: "Who's in your Squad")
    }
}

/// The Squad's words about studying today.
enum SquadCopy {
    /// "Priya studied today", "Priya and Sam studied today".
    static func studied(_ names: [String]) -> String {
        String(localized: "\(names.formatted(.list(type: .and))) studied today")
    }

    static let switchTitle: LocalizedStringResource = "Show when I've studied"
    static let switchNote: LocalizedStringResource = "Your Squad sees a mark on days you finish a session. Never your courses, notes, answers or exams."
    static let switchOnFailed: LocalizedStringResource = "Couldn't turn this on. Try again in a while."
    static let switchOffFailed: LocalizedStringResource = "Couldn't turn this off. Try again in a while."
}

/// A friend's face, with a mark when they've studied today. A check, so it never rests on colour alone.
struct SquadFace: View {
    let name: String
    var studied: Bool = false
    var size: CGFloat = 38
    var fill: Color = CLColor.sky
    /// A ring in the card's colour, for faces that overlap. It goes under the mark.
    var ring = false

    var body: some View {
        InitialsAvatar(name: name, size: size, fill: fill)
            .overlay { if ring { Circle().strokeBorder(CLColor.surface, lineWidth: 2) } }
            .overlay(alignment: .bottomTrailing) {
                if studied {
                    let mark = max(13, size * 0.36)
                    Image(systemName: "checkmark")
                        .font(.system(size: mark * 0.56, weight: .heavy))
                        .foregroundStyle(CLColor.onFill)
                        .frame(width: mark, height: mark)
                        .background(CLColor.mint, in: Circle())
                        .overlay(Circle().stroke(CLColor.surface, lineWidth: 1.5))
                        .offset(x: mark * 0.18, y: mark * 0.18)
                        .accessibilityHidden(true)
                }
            }
    }
}
