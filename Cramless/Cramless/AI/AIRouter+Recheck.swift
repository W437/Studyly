import Foundation

extension AIRouter {
    /// Asks the relay's check about one reported question. Nil when it can't be asked now (no consent, offline, a limit): the report waits.
    func recheck(_ request: CheckRequest, itemKey: String) async -> CheckVerdict? {
        guard cloudStillAllowed(), let transport else { return nil }
        do {
            return try await transport.check(request).verdicts.first { $0.id == itemKey }
        } catch {
            AppConfig.log.notice("re-check waits: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
