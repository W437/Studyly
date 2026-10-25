import CoreMotion
import Foundation

/// What the world reads each frame: the phone's tilt, smoothed, and where it was held a moment ago taken as the middle. A plain
/// box, because the drawing reads it 30 times a second and nothing else needs to hear of it.
final class HeroTiltBox: @unchecked Sendable {
    nonisolated(unsafe) var x = 0.0
    nonisolated(unsafe) var y = 0.0
}

/// The phone's motion sensor, feeding `HeroTiltFilter`. There is no tilt in the Simulator (or on an iPad without the sensor), and
/// `isAvailable` says so: the world then sways on its own, slowly (`idleSway`), so it still has depth.
@MainActor
final class HeroTilt {
    nonisolated(unsafe) private static let manager = CMMotionManager()
    private var filter = HeroTiltFilter()
    private var lastStamp: TimeInterval?
    let box = HeroTiltBox()

    nonisolated static var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard Self.isAvailable, !Self.manager.isDeviceMotionActive else { return }
        filter.reset()
        lastStamp = nil
        Self.manager.deviceMotionUpdateInterval = 1.0 / 30.0
        Self.manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            // Gravity in the phone's own axes: x grows as the right edge goes down, z as the top leans away from you.
            let side = motion.gravity.x, lean = -motion.gravity.z, stamp = motion.timestamp
            MainActor.assumeIsolated { self?.consume(side: side, lean: lean, at: stamp) }
        }
    }

    func stop() {
        if Self.manager.isDeviceMotionActive { Self.manager.stopDeviceMotionUpdates() }
        filter.reset()
        lastStamp = nil
        box.x = 0
        box.y = 0
    }

    private func consume(side: Double, lean: Double, at stamp: TimeInterval) {
        let dt = lastStamp.map { min(0.25, max(0.001, stamp - $0)) } ?? (1.0 / 30.0)
        lastStamp = stamp
        filter.update(side: side, lean: lean, dt: dt)
        box.x = filter.x
        box.y = filter.y
    }

    /// The tilt a world with no sensor shows at `time`: a slow, wide sway that never quite repeats.
    nonisolated static func idleSway(at time: Double) -> (x: Double, y: Double) {
        (0.62 * sin(2 * .pi * time / 15.0), 0.40 * sin(2 * .pi * time / 21.0 + 1.1))
    }
}
