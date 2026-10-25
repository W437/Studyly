import Foundation

// The welcome screen's sky: the constellation Cap's mortarboard makes, in seven stars, dim at first and lit by a touch. It teaches
// the app's idea in one gesture (a memory is a star; a little every day keeps it lit) before a word is read. Pure, so what is laid
// out and how a touch plays out are tested; `WelcomeStage` drives it, `WelcomeLook` has the numbers of its motion and
// `WelcomeSkyDrawing` draws it.

enum WelcomeSky {
    /// One course, one constellation: the cap.
    static let courseID = UUID(uuidString: "C0A1D2E3-0000-4000-8000-0000000000C1")!
    static let ids: [UUID] = (1...7).map { UUID(uuidString: String(format: "C0A1D2E3-0000-4000-8000-%012X", $0))! }

    /// The stars, in star spacings, left to right (so the sweep that lights the rest runs across the cap and ends on the tassel): the
    /// board is a diamond with its button in the middle, and the tassel hangs from the right corner.
    static let points: [SkyPoint] = [
        SkyPoint(x: 0.0, y: 1.9),    // 0 left corner
        SkyPoint(x: 2.7, y: 0.0),    // 1 back corner
        SkyPoint(x: 2.7, y: 1.65),   // 2 button
        SkyPoint(x: 2.7, y: 3.3),    // 3 front corner
        SkyPoint(x: 5.4, y: 1.6),    // 4 right corner
        SkyPoint(x: 5.55, y: 2.75),  // 5 tassel
        SkyPoint(x: 5.4, y: 3.85),   // 6 tassel's end
    ]
    static let lines: [SkyLayout.Line] = [
        .init(a: 0, b: 1), .init(a: 1, b: 4), .init(a: 4, b: 3), .init(a: 3, b: 0),   // the board
        .init(a: 1, b: 2), .init(a: 2, b: 3),                                          // its seam, through the button
        .init(a: 4, b: 5), .init(a: 5, b: 6),                                          // the tassel
    ]
    static let count = points.count

    /// The order Cap lights them when nobody does (and VoiceOver's "Light a star"): the back corner, the right, the left, then on.
    static let suggested = [1, 4, 0, 3, 2, 5, 6]

    static let layout: SkyLayout = {
        let center = SkyPoint(x: 2.78, y: 1.93)
        let constellation = SkyLayout.Constellation(
            id: UUID(uuidString: "C0A1D2E3-0000-4000-8000-0000000000C2")!, courseID: courseID, topicID: UUID(uuidString: "C0A1D2E3-0000-4000-8000-0000000000C3")!,
            name: "First light", center: center, radius: 3.3, stars: 0..<count, lines: lines)
        return SkyLayout(stars: (0..<count).map { SkyLayout.Star(id: ids[$0], point: points[$0], constellation: 0) },
                         constellations: [constellation], regions: [], width: 5.6, height: 3.9)
    }()
}

/// What has been lit, and what a touch does. Three stars (the person's, or Cap's if nobody touches) are enough: the third lights the
/// rest of the cap together, and the welcome is done.
struct WelcomeSkyState: Equatable, Sendable {
    /// The stars lit so far, in the order they were lit.
    private(set) var lit: [Int] = []

    /// How many stars it takes before the rest light up together.
    static let guided = 3

    enum Outcome: Equatable, Sendable {
        /// Not a star, or one already lit: nothing happens (the sky still ripples).
        case ignored
        /// One more star, not yet enough: `count` are lit now.
        case lit(star: Int, count: Int)
        /// The third star, and with it the rest of the cap, in the order they ignite.
        case finale(star: Int, rest: [Int])
    }

    var litSet: Set<Int> { Set(lit) }
    var count: Int { lit.count }
    var isFinished: Bool { lit.count >= Self.guided }
    func isLit(_ star: Int) -> Bool { lit.contains(star) }

    /// The star to light when nobody does.
    var suggestion: Int? { WelcomeSky.suggested.first { !lit.contains($0) } }

    @discardableResult
    mutating func light(_ star: Int) -> Outcome {
        guard (0..<WelcomeSky.count).contains(star), !lit.contains(star), !isFinished else { return .ignored }
        lit.append(star)
        guard lit.count >= Self.guided else { return .lit(star: star, count: lit.count) }
        let rest = (0..<WelcomeSky.count).filter { !lit.contains($0) }
        lit.append(contentsOf: rest)
        return .finale(star: star, rest: rest)
    }
}

/// Cap's part: what he says, and when. Short, warm, specific; never a nag.
enum WelcomeCopy {
    static let intro: LocalizedStringResource = "Hi, I'm Cap. Light a star with me."
    static let hint: LocalizedStringResource = "Go on, tap one."
    static let first: LocalizedStringResource = "There. That's one memory."
    static let second: LocalizedStringResource = "One more."
    static let finale: LocalizedStringResource = "That's the whole idea. Shall we?"

    /// Every line, for the voice tests.
    static let all: [LocalizedStringResource] = [intro, hint, first, second, finale]

    /// Seconds after the screen opens: Cap speaks, then (if nobody has touched a star) says to, then lights one himself.
    static let introAt = 1.9
    static let hintAfter = 5.0
    static let lightAfter = 1.5
    static let nextAfter = 4.2
    /// After the third star: the arc climbs for 1.3 s, then he says his last line.
    static let finaleLineAfter = 1.5
}
