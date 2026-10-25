import SwiftUI

/// The iPhone's accessibility settings as Capling reads them. Views read `@Environment(\.clReduceMotion)` and
/// `@Environment(\.clDifferentiateWithoutColor)` rather than the system keys, and `CLMotion` reads the same
/// switch, so DEBUG builds can force either one for films and screenshots (`CRAMLESS_REDUCE_MOTION=1`,
/// `CRAMLESS_DWC=1`): the Simulator can't turn them on.
enum CLAccessibility {
    #if DEBUG
    static let forcesReduceMotion = ProcessInfo.processInfo.environment["CRAMLESS_REDUCE_MOTION"] == "1"
    static let forcesDifferentiateWithoutColor = ProcessInfo.processInfo.environment["CRAMLESS_DWC"] == "1"
    #else
    static let forcesReduceMotion = false
    static let forcesDifferentiateWithoutColor = false
    #endif
}

extension EnvironmentValues {
    /// Reduce Motion: the iPhone's setting, or the DEBUG override.
    var clReduceMotion: Bool { accessibilityReduceMotion || CLAccessibility.forcesReduceMotion }

    /// Differentiate Without Color: the iPhone's setting, or the DEBUG override.
    var clDifferentiateWithoutColor: Bool {
        accessibilityDifferentiateWithoutColor || CLAccessibility.forcesDifferentiateWithoutColor
    }
}
