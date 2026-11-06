import Foundation
import Network

/// Says when the connection comes back, so a question kept for later is answered as soon as it can be. `AppModel+AnswerLater` runs it only while
/// the app is active and a question waits: a path monitor is a live object, and nothing else in the app needs one.
@MainActor
final class Connectivity {
    private var monitor: NWPathMonitor?
    private var wasOnline: Bool?

    var isWatching: Bool { monitor != nil }

    /// Starts watching. `onBackOnline` runs each time the path goes from unusable to usable; the path as it stands at the start only sets the baseline.
    func start(onBackOnline: @escaping @MainActor () -> Void) {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let cameBack = self.wasOnline == false && online
                self.wasOnline = online
                if cameBack { onBackOnline() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.loopware.Capling.connectivity", qos: .utility))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        wasOnline = nil
    }
}
