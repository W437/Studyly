import AppIntents

/// Siri, Spotlight and Shortcuts phrases. Every phrase names the app; keep them short and the way a student says
/// them out loud.
struct CramlessShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartSessionIntent(), phrases: [
            "Start my \(.applicationName) session",
            "Start today's session in \(.applicationName)",
            "Study with \(.applicationName)",
        ], shortTitle: "Start today's session", systemImageName: "play.circle")
        AppShortcut(intent: HowReadyAmIIntent(), phrases: [
            "How ready am I in \(.applicationName)",
            "Ask \(.applicationName) how ready I am",
            "How ready am I for my exam in \(.applicationName)",
        ], shortTitle: "How ready am I?", systemImageName: "gauge.with.dots.needle.67percent")
        AppShortcut(intent: ScanPagesIntent(), phrases: [
            "Scan pages with \(.applicationName)",
            "Scan my notes in \(.applicationName)",
        ], shortTitle: "Scan pages", systemImageName: "doc.viewfinder")
        AppShortcut(intent: RecordLectureIntent(), phrases: [
            "Record a lecture with \(.applicationName)",
            "Record my lecture in \(.applicationName)",
        ], shortTitle: "Record a lecture", systemImageName: "mic")
        AppShortcut(intent: StudyOutLoudIntent(), phrases: [
            "Study out loud with \(.applicationName)",
            "Quiz me out loud in \(.applicationName)",
        ], shortTitle: "Study out loud", systemImageName: "waveform")
    }

    static let shortcutTileColor: ShortcutTileColor = .tangerine
}
