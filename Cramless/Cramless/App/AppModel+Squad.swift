import Foundation
import SwiftData

// The Squad's studied-today dot. Off until the person switches it on (`settings.shareSquadDay`, which follows the server's `SquadMembers.sharing`). Their side: after the day's first
// finished session the phone tells the server "studied" and nothing else; it needs only a session, not sync, and a day it couldn't reach the server is tried again when the app comes back.
// Everyone's side: who in the Squad has studied today, for one line in Today's "Your plan" (`SquadToday`), read at most every 15 minutes and kept for the rest of the day, so
// the line is there at once. It's never read for someone with no Squad.
extension AppModel {
    private static let squadTodayKey = "capling.squad.today.v1"
    private static let squadStudiedKey = "capling.squad.studied.v1"
    /// How long a look at who's studied is good for.
    private static let squadTodayFresh: TimeInterval = 15 * 60

    /// Bought Squad, a seat on a friend's, or neither.
    var squadRole: SquadView.Role { SquadView.role(allowsSeats: purchases.allows(.squadSeats), plan: purchases.plan) }

    // MARK: Today's line

    /// Who's in the person's Squad and what they've shared, as of today. Nil with no Squad, nobody else in it, or nothing read today.
    var squadTodayLine: SquadToday? {
        guard squadRole != .none, let today = squadToday, today.day == calendar.dayKey(for: now), !today.friends.isEmpty else { return nil }
        return today
    }

    /// Reads who's studied, unless a look is still fresh. Quietly keeps what it has if it can't. A seat on a friend's Squad arrives from the server a moment after launch, so what's kept
    /// isn't thrown away for want of a role: the line asks for the role itself.
    func refreshSquadToday(force: Bool = false) async {
        guard config.aiMode != .local, squadRole != .none else { return }
        if !force, let today = squadToday, today.day == calendar.dayKey(for: now), now.timeIntervalSince(today.readAt) < Self.squadTodayFresh { return }
        _ = try? await squadMembers()
    }

    /// What a reply from the server says: the person's own switch, and the line. Every call that returns the members comes through here.
    func noteSquadMembers(_ members: SquadMembers) {
        if let sharing = members.sharing, settings.shareSquadDay != sharing { settings.shareSquadDay = sharing }
        let today = SquadToday(day: calendar.dayKey(for: now), readAt: now,
                               friends: SquadToday.friends(in: members, me: account.userID, owner: squadRole == .owner))
        if today.friends != squadToday?.friends || today.day != squadToday?.day { squadToday = today } else { squadToday?.readAt = now }
        if let data = try? JSONEncoder.cramless.encode(today) { defaults.set(data, forKey: Self.squadTodayKey) }
    }

    /// What was last read, so the line is there from the first frame of a launch.
    func loadSquadToday() {
        guard let data = defaults.data(forKey: Self.squadTodayKey) else { return }
        squadToday = try? JSONDecoder.cramless.decode(SquadToday.self, from: data)
    }

    /// Everything the Squad's dot keeps on this phone, for a local wipe.
    func clearSquadToday() {
        squadToday = nil
        defaults.removeObject(forKey: Self.squadTodayKey)
        defaults.removeObject(forKey: Self.squadStudiedKey)
    }

    // MARK: Sharing

    /// The switch. Off deletes what was shared, on the server, at once. On says "studied" right away if a session is already done today.
    func setSquadSharing(_ on: Bool) async throws -> SquadMembers {
        if on { await account.pushProfileIfNeeded() }
        let members = try await account.backend.setSquadSharing(on: on)
        noteSquadMembers(members)
        guard on else {
            defaults.removeObject(forKey: Self.squadStudiedKey)
            return members
        }
        guard await sendSquadStudiedIfDue() else { return members }
        return (try? await squadMembers()) ?? members
    }

    /// A session ended: a moment later (never in the summary's first frames), the server hears about it, and the line is read again.
    func noteSessionFinishedForSquad() {
        guard sideEffectsEnabled, squadRole != .none else { return }
        Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self else { return }
            if await self.sendSquadStudiedIfDue() { await self.refreshSquadToday(force: true) }
        }
    }

    /// Tells the server the person studied today, once a day, if they share and have finished a session today. True if it was told just now. What it costs: their day, and that's all.
    @discardableResult
    func sendSquadStudiedIfDue() async -> Bool {
        guard settings.shareSquadDay, config.aiMode != .local, squadRole != .none else { return false }
        let key = calendar.dayKey(for: now)
        guard defaults.string(forKey: Self.squadStudiedKey) != key, finishedASessionToday(), !squadSending else { return false }
        squadSending = true
        defer { squadSending = false }
        // The server reads "today" by the person's profile: it has to know their time zone first.
        await account.pushProfileIfNeeded()
        guard let reply = try? await account.backend.markSquadStudied(dayKey: key) else { return false }
        defaults.set(key, forKey: Self.squadStudiedKey)
        return reply.recorded
    }

    private func finishedASessionToday() -> Bool {
        let start = calendar.startOfDay(for: now)
        let quick = SessionKind.quickCheck.rawValue
        var descriptor = FetchDescriptor<StudySession>(predicate: #Predicate {
            $0.startedAt >= start && $0.endedAt != nil && $0.itemCount > 0 && $0.kindRaw != quick
        })
        descriptor.fetchLimit = 1
        return !fetch(descriptor).isEmpty
    }
}

#if DEBUG
extension AppModel {
    /// `CRAMLESS_SQUAD_TODAY=two|none|private|sharing`: the demo Squad, as the mock's fixture can't show it. `two`: Priya and Sam have studied. `none`: they share, and neither has yet.
    /// `private`: nobody shares. `sharing`: the person's own switch is on, and they've studied.
    func debugShapeSquad(_ members: SquadMembers) -> SquadMembers {
        guard config.isHarness, let raw = TestHarness.value("CRAMLESS_SQUAD_TODAY") else { return members }
        var out = members
        let sam = SquadMember(id: "u-sam", name: "Sam", joinedAt: Date(timeIntervalSince1970: 1_792_000_000), isOwner: false, studiedToday: true)
        switch raw {
        case "two":
            out.members.append(sam)
        case "none":
            var other = sam
            other.studiedToday = false
            out.members.append(other)
            out.members = out.members.map { var m = $0; if !m.isOwner { m.studiedToday = false }; return m }
        case "private":
            out.members = out.members.map { var m = $0; m.studiedToday = nil; return m }
        case "sharing":
            out.sharing = true
            out.members = out.members.map { var m = $0; if m.isOwner { m.studiedToday = true }; return m }
        default:
            break
        }
        return out
    }
}
#endif
