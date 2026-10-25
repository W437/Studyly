import Foundation

// Shared/Core holds Foundation-only code shared by the app, the widget extension and the Watch app: nothing here
// imports SwiftUI, UIKit, ActivityKit, WidgetKit or AppIntents.

/// Course colours, by stable key, so a course keeps its colour on every device. The colours themselves live in
/// `BrandPalette.swift` (`fill`, `soft`, `ink`); this file stays Foundation-only so the widget snapshot and the
/// Watch can carry a course's colour.
enum CourseColor: String, CaseIterable, Codable, Sendable {
    case sky, tangerine, mint, sun, rose, capy
}
