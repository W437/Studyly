import Foundation

extension AppModel {
    /// How long pull to refresh waits for the account before it stops waiting (the pull carries on in the background).
    nonisolated static let refreshPatience = Duration.seconds(5)

    /// Pull to refresh on Today: rolls the day over (idempotent, as on launch), and with sync on brings in what other devices
    /// changed, waiting `patience` at most. The screen then looks at the world again as of now. Returns false only when sync is
    /// on and the account couldn't be reached in time: the sky is then current on this iPhone alone.
    @discardableResult
    func refreshToday(patience: Duration = AppModel.refreshPatience) async -> Bool {
        applyDailyRollover()
        guard sync.isEnabled else { return true }
        let pull = RefreshFlag()
        Task { [sync] in
            await sync.pullNow()
            pull.done = true
        }
        let deadline = ContinuousClock.now + patience
        while !pull.done, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(80))
        }
        return pull.done && sync.lastError == nil
    }
}

/// Whether a pull has finished, readable from the loop that is waiting for it.
@MainActor
private final class RefreshFlag {
    var done = false
}
