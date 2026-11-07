import Foundation
import OSLog

/// The one seam that decides how this run of the app talks to the world. Feature code never asks which mode
/// it's in; services are built from this once, in `AppModel.init`.
///
/// - `relay`: a Supabase project is configured (Secrets.xcconfig): cloud AI through the relay after consent,
///   sync and Squad when signed in.
/// - `local`: nothing configured (the default for a fresh checkout): on-device AI where the iPhone has it, the
///   offline rules everywhere else. Every screen still works.
/// - `mock`: canned relay replies from the fixtures with believable latency, for tests, screenshots and demos.
///   Chosen with `CRAMLESS_MOCK_AI=1` (DEBUG builds only).
struct AppConfig: Sendable {
    enum AIMode: Equatable, Sendable {
        case relay
        case local
        case mock
    }

    var supabaseURL: URL?
    var supabaseAnonKey: String?
    var aiMode: AIMode
    /// The screenshot and UI-test harness: `CRAMLESS_UITEST=1`. Seeds the demo world, skips first-run gates.
    var isHarness: Bool
    /// In-memory store: tests and the harness never touch the real store.
    var inMemoryStore: Bool
    /// Seed the curated demo world on launch.
    var seedDemoData: Bool
    var environment: [String: String]

    var isRelayConfigured: Bool { supabaseURL != nil && !(supabaseAnonKey ?? "").isEmpty }

    static func resolve(environment env: [String: String] = ProcessInfo.processInfo.environment,
                        info given: [String: Any]? = nil) -> AppConfig {
        let isTests = env["XCTestConfigurationFilePath"] != nil
        // A test run never takes the backend from the app's own Info.plist, even with a filled Secrets.xcconfig: a test that
        // starts an account would sign up on production. A test that wants a backend names it in `info`.
        let info = given ?? (isTests ? [:] : Bundle.main.infoDictionary ?? [:])
        let host = (info["CramlessSupabaseHost"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let key = (info["CramlessSupabaseAnonKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let url: URL? = host.isEmpty ? nil : URL(string: host.hasPrefix("http") ? host : "https://\(host)")
        #if DEBUG
        let harness = env["CRAMLESS_UITEST"] == "1"
        let mock = env["CRAMLESS_MOCK_AI"] == "1" || (harness && env["CRAMLESS_MOCK_AI"] != "0")
        #else
        let harness = false
        let mock = false
        #endif
        let mode: AIMode = mock ? .mock : (url != nil && !key.isEmpty ? .relay : .local)
        return AppConfig(supabaseURL: url, supabaseAnonKey: key.isEmpty ? nil : key, aiMode: mode,
                         isHarness: harness, inMemoryStore: harness || isTests,
                         seedDemoData: harness && env["CRAMLESS_SEED"] != "0", environment: env)
    }

    /// One unmistakable line at startup.
    var startupLine: String {
        let ai: String = switch aiMode {
        case .relay: "RELAY → \(supabaseURL?.host() ?? "?")"
        case .local: "LOCAL (on-device and offline rules; no relay configured)"
        case .mock: "MOCK (canned relay replies, no network)"
        }
        return "Capling — AI: \(ai) · store: \(inMemoryStore ? "in-memory" : "on disk") · harness: \(isHarness ? "on" : "off")"
    }

    static let log = Logger(subsystem: "com.loopware.Capling", category: "app")
}
