import ObjectiveC
import SwiftUI
import UIKit

/// Makes the tab bar's + a button instead of a destination.
///
/// SwiftUI has no action tab. The + is a `Tab` like the others, so a tap makes UIKit select it, the `TabView` swaps its page
/// for the + tab's (empty) one, and only then does SwiftUI hear about it and put the selection back. For four frames the page
/// the person was on vanished and came back (a flash of the window behind it, and every `onAppear` on it ran again): the
/// owner's recording of Today shows it. This stands between UIKit and SwiftUI's own tab delegate and answers "may this tab be
/// selected?" with no for the +, running the action instead, so the selection never moves and nothing swaps.
///
/// It sits in each tab's content (`TabRoot`), because the tab bar controller is only an ancestor from in there.
struct AddTabAction: UIViewControllerRepresentable {
    var action: () -> Void

    func makeUIViewController(context: Context) -> Installer { Installer(action: action) }

    func updateUIViewController(_ controller: Installer, context: Context) {
        controller.action = action
        controller.install()
    }

    final class Installer: UIViewController {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isHidden = true
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        func install() {
            guard let controller = tabBarController else { return }
            AddTabProxy.attach(to: controller, action: action)
        }
    }
}

/// Stands in front of SwiftUI's tab delegate (`TabViewCoordinator_Phone`): it answers one question and passes every other to
/// the delegate it replaced, so SwiftUI still hears of every real selection.
final class AddTabProxy: NSObject, UITabBarControllerDelegate {
    nonisolated(unsafe) private static var key = 0

    /// The delegate this one replaced; every call but the one answered here goes to it.
    nonisolated(unsafe) weak var original: (any UITabBarControllerDelegate)?
    nonisolated(unsafe) var action: () -> Void = {}
    nonisolated(unsafe) private var observation: NSKeyValueObservation?

    /// Puts the proxy in front of `controller`'s delegate (once), and keeps it there if SwiftUI sets its own back.
    @MainActor static func attach(to controller: UITabBarController, action: @escaping () -> Void) {
        if let proxy = objc_getAssociatedObject(controller, &key) as? AddTabProxy {
            proxy.action = action
            proxy.takeOver(controller)
            return
        }
        let proxy = AddTabProxy()
        proxy.action = action
        objc_setAssociatedObject(controller, &key, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        proxy.takeOver(controller)
        proxy.observation = controller.observe(\.delegate, options: [.new]) { [weak proxy] controller, _ in
            MainActor.assumeIsolated { proxy?.takeOver(controller) }
        }
    }

    @MainActor private func takeOver(_ controller: UITabBarController) {
        guard controller.delegate !== self else { return }
        original = controller.delegate
        controller.delegate = self
    }

    /// The + is the last tab, and nothing selects it: the action runs instead.
    @MainActor private func isAction(_ controller: UITabBarController, tab: UITab?) -> Bool {
        guard let tab, let last = controller.tabs.last else { return false }
        return tab === last
    }

    @MainActor func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        if isAction(tabBarController, tab: tab) {
            action()
            return false
        }
        return original?.tabBarController?(tabBarController, shouldSelectTab: tab) ?? true
    }

    // The delegate that was there keeps every other call.

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original as? NSObject)?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        if let original = original as? NSObject, original.responds(to: selector) { return original }
        return super.forwardingTarget(for: selector)
    }
}

extension AppModel {
    /// The course of the page in front on the current tab, for the tab bar's +: a course page or its questions, an exam, a source, a page of
    /// one or a lecture's notes. Nil anywhere else (Today, Ask, Progress, Settings), where the + sheet's flows pick the usual course.
    var courseOnScreen: UUID? {
        guard let route = router.paths[router.tab]?.last else { return nil }
        let found: Course? = switch route {
        case .course(let id), .courseQuestions(let id, _): course(id)
        case .exam(let id): exam(id)?.course
        case .source(let id), .lectureNotes(let id), .sourcePage(let id, _, _): source(id)?.course
        default: nil
        }
        guard let found, found.deletedAt == nil else { return nil }
        return found.id
    }
}
