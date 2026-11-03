import Foundation

/// When a relay call that failed is worth one more quiet try. Under heavy load the relay's gateway answered a few
/// question-writing calls with HTTP 503 and the same calls succeeded when repeated by hand, so the JSON routes (generate,
/// check, grade, lecture, cards-from-chat, confusions, transcribe-image, quota) try once more on a 503 or a 504, or when the
/// connection dropped before any answer. The relay refunds the scan or meter of a request that failed (`refund` in
/// `ai/handler.ts`), so a retry doesn't charge a scan twice.
///
/// Never on a 502. The relay answers 502 for failures it was PAID for and that repeat: every question dropped, a reply cut off, an
/// unreadable reply. The scan is given back, but the model's cost counts toward the account's 10 cents a day, and asking again
/// would spend it again for the same answer. A 503 is the provider being busy (it names `retryAfter`, 15 or 20 seconds) and a
/// 504 a timeout; neither was paid for.
///
/// A 503 that names a wait of 15 seconds or less is retried after that wait (and a little jitter), and one that names a longer
/// wait is not retried at all: the person is not kept waiting for it. A 503 that names none (a gateway's own) and a 504 or a
/// dropped connection wait 1.5 to 3 seconds. Never on a 4xx, a quota or `entitlement_required` answer (those are decisions, not
/// accidents), never when the task was cancelled, never twice, and never when the first attempt was slow: a retry only happens
/// when the call failed fast enough that the first attempt and the pause fit in half of the route's timeout, and the retry
/// gets only what is left of it. A 120 second generate never waits 240.
///
/// The decision is this pure function; `HTTPRelayTransport` does the waiting and the second request.
enum RelayRetry {

    /// What went wrong with an attempt, as far as a retry cares.
    enum Failure: Equatable, Sendable {
        /// The relay (or its gateway) answered with this HTTP status; `retryAfter` is the wait it named, in seconds.
        case status(Int, retryAfter: TimeInterval? = nil)
        /// The connection dropped before any answer.
        case connectionLost
        /// Anything else: a refusal, a decoding problem, no network at all.
        case other

        init(status: Int?, retryAfter: TimeInterval? = nil, urlError: URLError.Code?) {
            if let status {
                self = .status(status, retryAfter: retryAfter)
            } else if urlError == .networkConnectionLost {
                self = .connectionLost
            } else {
                self = .other
            }
        }
    }

    /// The statuses worth a second try: the provider busy (503) and a timeout (504). Not 502: that one was paid for.
    static let statuses: Set<Int> = [503, 504]

    /// The longest wait a 503 may name for it to be retried.
    static let longestRetryAfter: TimeInterval = 15

    /// How long to wait before the retry when the relay names no wait: 1.5 to 3 seconds.
    static let pauseRange: ClosedRange<TimeInterval> = 1.5...3

    /// The pause before the one retry, or nil for none. `attempt` is the attempt that just failed (1 for the first);
    /// `elapsed` is how long the call has taken so far; `timeout` is the route's whole budget; `jitter` is 0...1.
    static func pause(after failure: Failure, attempt: Int, elapsed: TimeInterval, timeout: TimeInterval,
                      jitter: Double, range: ClosedRange<TimeInterval> = pauseRange) -> TimeInterval? {
        guard attempt == 1 else { return nil }
        let spread = range.upperBound - range.lowerBound
        let unit = min(1, max(0, jitter))
        let pause: TimeInterval
        switch failure {
        case .connectionLost:
            pause = range.lowerBound + spread * unit
        case .status(let code, let named):
            guard statuses.contains(code) else { return nil }
            if code == 503, let named {
                // The relay named a wait: after it, if it is a short one.
                guard named <= longestRetryAfter else { return nil }
                pause = max(named, range.lowerBound) + spread * unit
            } else {
                pause = range.lowerBound + spread * unit
            }
        case .other:
            return nil
        }
        // Fast failures only: the first attempt and the pause together use at most half of the route's time, so the retry keeps
        // at least half of it.
        guard elapsed + pause <= timeout / 2 else { return nil }
        return pause
    }

    /// What is left of the route's timeout for the retry once the first attempt and the pause are spent.
    static func remainingTimeout(timeout: TimeInterval, elapsed: TimeInterval, pause: TimeInterval) -> TimeInterval {
        max(1, timeout - elapsed - pause)
    }

    /// The wait an error answer named, in seconds: the envelope's `retryAfter`, else the `Retry-After` header (seconds).
    static func retryAfter(body: Data, header: String?) -> TimeInterval? {
        if let envelope = try? JSONDecoder.cramless.decode(RelayErrorBody.self, from: body), let seconds = envelope.error.retryAfter,
           seconds.isFinite, seconds >= 0 {
            return seconds
        }
        if let header, let seconds = TimeInterval(header.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 {
            return seconds
        }
        return nil
    }
}
