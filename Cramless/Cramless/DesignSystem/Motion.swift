import SwiftUI
import UIKit

// Motion tokens. Each one reads Reduce Motion itself, so a call site never branches on it: under Reduce Motion
// every token becomes a short cross-fade-length ease and springs stop overshooting. Use these with
// `withAnimation(CLMotion.pop) { … }` or `.animation(CLMotion.settle, value: …)`; never a bare literal spring.
//
// The live onboarding scenes replay the product's motion with these same tokens, so the demo and the feature
// can never drift apart.

enum CLMotion {
    private static var reduced: Bool { UIAccessibility.isReduceMotionEnabled || CLAccessibility.forcesReduceMotion }

    /// Chips, checks and badges landing: a small spring with a little overshoot.
    static var pop: Animation {
        reduced ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.62)
    }

    /// Cards and panels arriving or rearranging.
    static var settle: Animation {
        reduced ? .easeOut(duration: 0.18) : .spring(response: 0.48, dampingFraction: 0.86)
    }

    /// Quick UI responses: selection, toggles, pressed states.
    static var snap: Animation {
        reduced ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.9)
    }

    /// Calm, deliberate moves: the scanner's brackets locking on, a sheet of results sliding in.
    static var calm: Animation {
        reduced ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.7)
    }

    /// Progress that should be watched: the readiness ring climbing, a bar filling, the highlighter sweeping.
    static var fill: Animation {
        reduced ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 1.2)
    }

    /// Fades between states, and the invisible reset of a looping demo.
    static var fade: Animation { .easeInOut(duration: reduced ? 0.15 : 0.28) }

    /// Things leaving the screen.
    static var exit: Animation { .easeIn(duration: reduced ? 0.12 : 0.22) }

    /// A button's face going down onto its edge: quick and firm.
    static var press: Animation { reduced ? .easeOut(duration: 0.05) : .easeOut(duration: 0.07) }

    /// The face springing back up when let go, with a small bounce.
    static var release: Animation {
        reduced ? .easeOut(duration: 0.1) : .spring(response: 0.26, dampingFraction: 0.58)
    }

    /// The answer panel rising from the bottom edge.
    static var sheet: Animation {
        reduced ? .easeOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.84)
    }

    /// A progress segment's glow shrinking back after an answer lands.
    static var bloom: Animation { reduced ? .easeOut(duration: 0.1) : .easeOut(duration: 0.7) }

    /// Duration of the highlighter sweep over one key idea, in seconds.
    static var highlightSweep: Double { reduced ? 0 : 0.55 }

    /// True when looping or decorative motion should not run at all.
    static var isReduced: Bool { reduced }
}

/// A cancellable pause for scripted motion (onboarding scenes, the processing steps). Throws on cancellation so
/// a script stops the moment its page leaves the screen.
func nap(_ milliseconds: Int) async throws {
    try await Task.sleep(for: .milliseconds(milliseconds))
}
