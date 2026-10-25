import Foundation
import WidgetKit

/// Keeps everything outside the app in step with it: writes the widget snapshot to the App Group, reloads the
/// widgets' timelines, and starts, updates or ends the exam-week Live Activity. `AppModel.save()` calls `refresh()`
/// on its side-effect debounce, `start()` once at launch and `flushSideEffects()` directly (intents finishing in
/// the background).
@MainActor
final class WidgetSync {
    weak var app: AppModel?

    /// Where the snapshot goes; tests point it at a temporary folder. Without an App Group container (unsigned
    /// simulator builds) writes do nothing and the widgets show their empty state.
    var store = WidgetSnapshotStore.shared
    /// Reloads every widget timeline. Tests replace it.
    var reloadTimelines: () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    /// Coalesces reloads: the first one goes now, any more within this window go once at its end.
    var reloadWindow: Duration = .milliseconds(800)

    private(set) var lastWritten: WidgetSnapshot?
    private var lastReloadAt: ContinuousClock.Instant?
    private var trailingReload: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        // Normally done by the app delegate at launch; this covers a launch without it.
        DeepLinks.installIntentBridge()
    }

    /// Builds the snapshot, writes it when it changed, reloads the timelines and syncs the exam-week activity.
    func refresh() {
        guard let app else { return }
        let snapshot = app.makeWidgetSnapshot()
        app.liveActivities.syncExamWeek(with: snapshot)
        guard needsWrite(snapshot, calendar: app.calendar) else { return }
        guard store.write(snapshot) else { return }
        lastWritten = snapshot
        reload()
    }

    /// A write is needed when anything but the timestamp changed, or the last write was on an earlier day (the
    /// widgets roll forward from the write's day).
    func needsWrite(_ snapshot: WidgetSnapshot, calendar: Calendar) -> Bool {
        guard let last = lastWritten else { return true }
        guard calendar.isDate(last.generatedAt, inSameDayAs: snapshot.generatedAt) else { return true }
        var a = last
        a.generatedAt = snapshot.generatedAt
        return a != snapshot
    }

    private func reload() {
        let clock = ContinuousClock()
        let now = clock.now
        if let last = lastReloadAt, now < last.advanced(by: reloadWindow) {
            guard trailingReload == nil else { return }
            let wait = last.advanced(by: reloadWindow) - now
            trailingReload = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                self.trailingReload = nil
                self.lastReloadAt = ContinuousClock().now
                self.reloadTimelines()
            }
            return
        }
        lastReloadAt = now
        reloadTimelines()
    }
}
