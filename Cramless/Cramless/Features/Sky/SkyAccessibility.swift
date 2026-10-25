import SwiftUI

/// The memory sky's words: what the screen says, and what VoiceOver says for the sky and each constellation. Pure
/// functions of a `SkyScene`, so they're tested without a view.
enum SkyCopy {
    // MARK: Counts

    static func stars(_ n: Int) -> LocalizedStringResource { "\(n) stars" }
    static func constellations(_ n: Int) -> LocalizedStringResource { "\(n) constellations" }
    static func dim(_ n: Int) -> LocalizedStringResource { "\(n) dim" }
    static func notYetLit(_ n: Int) -> LocalizedStringResource { "\(n) not yet lit" }
    static func brightOf(_ bright: Int, _ total: Int) -> LocalizedStringResource { "\(bright) of \(total) bright" }
    static func starsBrightOf(_ bright: Int, _ total: Int) -> LocalizedStringResource { "\(bright) of \(total) stars bright" }
    /// The summary line: "Relit 12 stars · 3 saved".
    static func relit(_ n: Int) -> LocalizedStringResource { "Relit \(n) stars" }
    static func saved(_ n: Int) -> LocalizedStringResource { "\(n) saved" }

    /// "8 of 14 bright · 2 dim · 4 not yet lit": how a constellation is doing, in words.
    static func detail(_ index: Int, in scene: SkyScene) -> String {
        let c = scene.layout.constellations[index]
        let dim = scene.light.dimCount(c)
        let hollow = c.stars.filter { scene.light.hollow[$0] }.count
        var parts = [String(localized: brightOf(scene.light.brightCount(c), c.stars.count))]
        if dim > 0 { parts.append(String(localized: SkyCopy.dim(dim))) }
        if hollow > 0 { parts.append(String(localized: notYetLit(hollow))) }
        return parts.joined(separator: " · ")
    }

    // MARK: Buttons

    static func relight(_ name: String, minutes: Int) -> LocalizedStringResource { "Relight \(name) · \(minutes) min" }
    static func practice(_ name: String, minutes: Int) -> LocalizedStringResource { "Practice \(name) · \(minutes) min" }

    // MARK: VoiceOver

    /// What the sky is, in one go: "142 stars in 12 constellations. 96 bright, 31 dim, 15 not yet lit."
    static func summary(_ scene: SkyScene) -> String {
        guard !scene.isEmpty else { return String(localized: "Your memory sky is empty. Add class material and every question you study becomes a star.") }
        let counts = [String(localized: dim(scene.dimCount)), String(localized: notYetLit(scene.hollowCount))]
        let bright = String(localized: "\(scene.brightCount) bright")
        return "\(String(localized: stars(scene.starCount))) in \(String(localized: constellations(scene.layout.constellations.count))). "
            + ([bright] + counts).joined(separator: ", ") + "."
    }

    /// One constellation: its name and course, how many of its stars are bright, and how well it is remembered.
    static func label(_ index: Int, in scene: SkyScene) -> String {
        let c = scene.layout.constellations[index]
        let total = c.stars.count
        let bright = scene.light.brightCount(c)
        var parts = [c.name]
        let course = scene.courseName(of: c)
        if !course.isEmpty, course != c.name { parts[0] += ", \(course)" }
        var detail = String(localized: starsBrightOf(bright, total))
        let dim = scene.light.dimCount(c)
        let hollow = c.stars.filter { scene.light.hollow[$0] }.count
        if dim > 0 { detail += ", " + String(localized: SkyCopy.dim(dim)) }
        if hollow > 0 { detail += ", " + String(localized: notYetLit(hollow)) }
        parts.append(detail)
        if let recall = scene.light.meanRecall(c) {
            parts.append(String(localized: "Recall about \(CLFormat.percent(recall))"))
        }
        return parts.joined(separator: ". ") + "."
    }

    /// An exam's region: its name and the constellations it covers.
    static func examLabel(_ region: SkyLayout.Region, in scene: SkyScene) -> String {
        let layout = scene.layout
        let names = layout.constellations.filter { c in
            c.courseID == region.courseID && c.stars.allSatisfy { i in
                let dx = layout.stars[i].point.x - region.center.x
                let dy = layout.stars[i].point.y - region.center.y
                return dx * dx + dy * dy <= region.radius * region.radius
            }
        }.map(\.name).joined(separator: ", ")
        return names.isEmpty ? region.title : "\(region.title). \(names)"
    }
}
