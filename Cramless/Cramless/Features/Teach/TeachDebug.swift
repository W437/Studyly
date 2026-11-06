#if DEBUG
import Foundation

/// The harness's Teach Cap, with no microphone. `CRAMLESS_ROUTE=teach[:n]` opens it on the nth topic with enough to ask. `CRAMLESS_TEACH_SCRIPT=good|thin` "says" an explanation
/// that covers every idea, or only the first. `CRAMLESS_TEACH_STATE=prompt|listening|check|followup|added` opens on that state, from the same paths as a finger
/// (`check` and later use the script; `thin` unless it says otherwise, so there is something to follow up).
enum TeachDebug {
    @MainActor static var state: String? { TestHarness.value("CRAMLESS_TEACH_STATE") }
    @MainActor static var script: String { TestHarness.value("CRAMLESS_TEACH_SCRIPT") ?? (state == "check" ? "good" : "thin") }

    /// What a person says, for a plan's ideas.
    static func words(_ script: String, plan: TeachPlan) -> String {
        let phrases = plan.ideas.map { $0.idea.terms.first ?? $0.label }
        if script == "good" { return "So basically " + phrases.joined(separator: " and then ") + " and that's the whole idea." }
        return "It has something to do with " + (phrases.first ?? "this topic") + " I think."
    }

    @MainActor static func ports(plan: TeachPlan) -> TeachPorts {
        let hold = state == "listening"
        let spoken = words(script, plan: plan)
        var turns = 0
        return TeachPorts(makeListener: {
            ScriptedSpokenListener(wordInterval: .milliseconds(120), holdsAfterWords: hold) { turn in
                turns += 1
                // The second turn is the follow-up's answer.
                return turns == 1 ? spoken : "I'm not really sure about this one"
            }
        })
    }

    /// Walks to the state asked for.
    @MainActor static func play(_ session: TeachSession) async {
        guard let state else {
            if TestHarness.value("CRAMLESS_TEACH_SCRIPT") != nil { session.sayIt() }
            return
        }
        guard state != "prompt" else { return }
        session.sayIt()
        guard state != "listening" else { return }
        while session.phase != .check { try? await Task.sleep(for: .milliseconds(100)) }
        guard state != "check" else { return }
        while session.isRefining { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(500))
        session.askFollowUp()
        guard state != "followup" else { return }
        session.typedFollowUp("I'm not really sure about this one")
        session.typeFollowUp()
        session.doneFollowUp()
        while session.followUpRefining { try? await Task.sleep(for: .milliseconds(100)) }
        session.addMissingIdea()
    }
}
#endif
