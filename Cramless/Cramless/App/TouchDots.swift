import UIKit
import ObjectiveC

#if DEBUG
/// `CRAMLESS_SHOW_TOUCHES=1` (set by `scripts/journey_film.sh`): a soft ring under every finger, drawn in a window above every
/// other (so it shows over sheets, covers and the keyboard's window too), so a film of real taps and swipes shows where the
/// person touched. The Simulator's recorder draws no touches of its own.
///
/// Like the film timecode it takes no touch itself (the window is not interactive) and exists only when asked for. It reads the
/// touches in `UIApplication.sendEvent`, after the app has handled them, so it can't change what a tap does.
@MainActor
enum TouchDots {
    fileprivate static var overlay: TouchDotsView?
    private static var window: UIWindow?
    private static var swizzled = false

    static func installIfAsked() {
        guard ProcessInfo.processInfo.environment["CRAMLESS_SHOW_TOUCHES"] == "1", window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let host = UIWindow(windowScene: scene)
        host.windowLevel = .statusBar + 2
        host.isUserInteractionEnabled = false
        let view = TouchDotsView(frame: scene.screen.bounds)
        let controller = UIViewController()
        controller.view = view
        host.rootViewController = controller
        host.frame = scene.screen.bounds
        host.isHidden = false
        window = host
        overlay = view
        guard !swizzled else { return }
        swizzled = true
        if let original = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
           let replacement = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.cl_touchDots_sendEvent(_:))) {
            method_exchangeImplementations(original, replacement)
        }
    }
}

extension UIApplication {
    /// Runs in place of `sendEvent(_:)` once exchanged: the call to itself is the original.
    @objc fileprivate func cl_touchDots_sendEvent(_ event: UIEvent) {
        cl_touchDots_sendEvent(event)
        guard event.type == .touches, let touches = event.allTouches else { return }
        MainActor.assumeIsolated { TouchDots.overlay?.handle(touches) }
    }
}

/// The rings: one layer per finger, put down on `began`, followed on `moved`, let go with a short fade on `ended`.
final class TouchDotsView: UIView {
    private var rings: [ObjectIdentifier: (layer: CALayer, since: CFTimeInterval)] = [:]
    /// A tap from a script is down for about a tenth of a second; a ring that short can fall between two frames of a 60 fps film.
    private let minimumShown: CFTimeInterval = 0.24

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func handle(_ touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch)
            let point = touch.location(in: nil)
            switch touch.phase {
            case .began: put(key, at: point)
            case .moved: follow(key, to: point)
            case .ended, .cancelled: lift(key, at: point)
            default: break
            }
        }
    }

    private func put(_ key: ObjectIdentifier, at point: CGPoint) {
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 54, height: 54)
        layer.cornerRadius = 27
        layer.backgroundColor = UIColor(white: 0.1, alpha: 0.2).cgColor
        layer.borderColor = UIColor.white.withAlphaComponent(0.96).cgColor
        layer.borderWidth = 2.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowRadius = 4
        layer.shadowOffset = .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = point
        self.layer.addSublayer(layer)
        CATransaction.commit()
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.55
        pop.toValue = 1
        pop.duration = 0.12
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(pop, forKey: "pop")
        rings[key] = (layer, CACurrentMediaTime())
    }

    private func follow(_ key: ObjectIdentifier, to point: CGPoint) {
        guard let ring = rings[key] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.layer.position = point
        CATransaction.commit()
    }

    private func lift(_ key: ObjectIdentifier, at point: CGPoint) {
        guard let ring = rings.removeValue(forKey: key) else { return }
        follow(for: ring.layer, to: point)
        let wait = max(0, minimumShown - (CACurrentMediaTime() - ring.since))
        let layer = ring.layer
        Task { @MainActor in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 1
            grow.toValue = 1.35
            let group = CAAnimationGroup()
            group.animations = [fade, grow]
            group.duration = 0.28
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            layer.add(group, forKey: "lift")
            try? await Task.sleep(for: .seconds(0.3))
            layer.removeFromSuperlayer()
        }
    }

    private func follow(for layer: CALayer, to point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = point
        CATransaction.commit()
    }
}
#endif
