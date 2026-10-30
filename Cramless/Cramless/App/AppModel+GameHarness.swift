#if DEBUG
import Foundation

// Launch hooks for the game loop (DEBUG only), so every state can be filmed and screenshotted with no taps:
//
// - `CRAMLESS_SCENARIO=streak:<n>`: the history is n studied days in a row up to yesterday, today not yet studied, so a
//   session today makes it n + 1 (`streak:29` and a session is the 30-day milestone; the flame has the stage for n).
// - `CRAMLESS_QUESTS=start|partial|done|weekFull`: today's quests and the week as they would be at some point of the day
//   (`start`: none done, 7 earlier this week; `partial`: one of three done, 5 of 12 this week; `done`: 3 of 3, 8 this week;
//   `weekFull`: 2 of 3 done and 9 earlier this week, so the session makes 12 and lights a sky). The week is made to end
//   today, so there are earlier days to hold the earlier quests whatever day it is.
// - `CRAMLESS_QUEST_PICKS=finishSession,ownWords,learnNew`: those are today's quests, whatever the day would pick.
// - `CRAMLESS_UNLOCK=all`: every icon and every sky shows as unlocked.
// - `CRAMLESS_SKY_THEME=<night|dusk|aurora|ember|bloom|glacier>`: that sky behind the stars (it unlocks them all).
// - `CRAMLESS_TILT=<pitch>,<roll>`: holds a badge medal's tilt (`MedalTilt.held`).
// - `CRAMLESS_SESSION_STATE=milestone-summary|badge-summary|quest-summary`: answers a session and shows its summary
//   (`badge-summary` first forgets that the 7-day badge was ever shown, so the session earns it again).
extension AppModel {
    /// Applies the hooks that set up the world. Called once at launch, after the demo world is seeded.
    func applyGameHarness() {
        guard config.isHarness else { return }
        if TestHarness.value("CRAMLESS_UNLOCK") == "all" { debugUnlockAll = true }
        if let id = TestHarness.value("CRAMLESS_SKY_THEME"), let theme = SkyTheme(rawValue: id) {
            debugUnlockAll = true
            settings.skyTheme = theme
        }
        if let scenario = TestHarness.value("CRAMLESS_SCENARIO"), scenario.hasPrefix("streak:"),
           let days = Int(scenario.dropFirst("streak:".count)) {
            applyStreakScenario(days)
        }
        if let mode = TestHarness.value("CRAMLESS_QUESTS") { applyQuestScenario(mode) }
    }

    /// n studied days in a row up to yesterday, and the day before them missed.
    func applyStreakScenario(_ days: Int) {
        let n = max(0, min(days, 800))
        for offset in 1...(n + 1) {
            let date = calendar.adding(days: -offset, to: now)
            let record = dayRecord(key: calendar.dayKey(for: date), date: date)
            let studied = offset <= n
            record.sessions = studied ? 1 : 0
            record.studySeconds = studied ? 15 * 60 : 0
            record.itemsReviewed = studied ? 18 : 0
            record.frozen = false
            record.repaired = false
            record.syncedAt = nil
        }
        save()
    }

    /// Today's quests and the week as they would be at some point of the day (see the list above).
    func applyQuestScenario(_ mode: String) {
        // Make the week end today, so there are six earlier days to hold the quests of the week so far.
        let today = calendar.dayNumber(for: now)
        // (The week starts the day after today's weekday, so today is its seventh day.)
        calendar.firstWeekday = Calendar.weekday(dayNumber: today) % 7 + 1
        ensureQuestPicks()
        let picks = todayQuestKinds()
        guard picks.count == QuestEngine.perDay else { return }
        let record = dayRecord(for: now)
        let (todayDone, earlier): ([QuestKind], Int)
        switch mode {
        case "start": (todayDone, earlier) = ([], 7)
        case "partial": (todayDone, earlier) = ([picks[1]], 4)
        case "done": (todayDone, earlier) = (picks, 5)
        case "weekFull": (todayDone, earlier) = ([picks[1], picks[2]], 9)
        default: return
        }
        record.questMask = todayDone.reduce(0) { $0 | $1.bit }
        record.syncedAt = nil
        // The earlier quests of the week, newest day first, up to three a day.
        var left = earlier
        for back in 1...6 where left > 0 {
            let date = calendar.adding(days: -back, to: now)
            let day = dayRecord(key: calendar.dayKey(for: date), date: date)
            let count = min(QuestEngine.perDay, left)
            day.questMask = QuestKind.allCases.prefix(count).reduce(0) { $0 | $1.bit }
            day.syncedAt = nil
            left -= count
        }
        save()
    }

    /// `badge-summary`: the badge for a week's streak is earned again by the next session.
    func debugForgetBadge(_ badge: Badge) {
        guard var known = settings.badges else { return }
        known.removeValue(forKey: badge.rawValue)
        settings.badges = known
    }
}
#endif
