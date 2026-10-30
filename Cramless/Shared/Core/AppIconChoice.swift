import Foundation

/// The app's icons: Cap on blue, and four more that a streak unlocks. Foundation only; the asset catalog holds the art
/// (`AppIcon` and `AppIcon-<Name>`, with a preview image `IconPreview-<Name>` for the picker).
///
/// An icon unlocks at a best streak and never locks again, so a streak that breaks takes nothing away (`unlocked(best:)`
/// reads the best, not the current one).
enum AppIconChoice: String, Codable, CaseIterable, Sendable, Identifiable {
    case standard
    /// Cap under the stars.
    case night
    /// Cap by the fire.
    case ember
    /// The golden Cap.
    case gold
    /// Cap under the aurora.
    case aurora

    var id: String { rawValue }

    /// The best streak, in days, that unlocks it: the flame's own milestones.
    var unlockDays: Int {
        switch self {
        case .standard: 0
        case .night: 7
        case .ember: 30
        case .gold: 100
        case .aurora: 365
        }
    }

    /// The name `UIApplication.setAlternateIconName` takes; nil for the main icon.
    var alternateName: String? {
        switch self {
        case .standard: nil
        case .night: "AppIcon-Night"
        case .ember: "AppIcon-Ember"
        case .gold: "AppIcon-Gold"
        case .aurora: "AppIcon-Aurora"
        }
    }

    /// The image set the picker draws (the icon sets themselves can't be loaded by name).
    var previewName: String {
        switch self {
        case .standard: "IconPreview-Standard"
        case .night: "IconPreview-Night"
        case .ember: "IconPreview-Ember"
        case .gold: "IconPreview-Gold"
        case .aurora: "IconPreview-Aurora"
        }
    }

    /// The icon for a name `UIApplication.alternateIconName` reports (nil is the main icon).
    init(alternateName: String?) {
        self = Self.allCases.first { $0.alternateName == alternateName } ?? .standard
    }

    func isUnlocked(best: Int) -> Bool { best >= unlockDays }

    /// Every icon a best streak has unlocked, in order.
    static func unlocked(best: Int) -> [AppIconChoice] {
        allCases.filter { $0.isUnlocked(best: best) }
    }
}
