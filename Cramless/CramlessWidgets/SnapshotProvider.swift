import SwiftUI
import WidgetKit

/// The one timeline provider every widget uses: the stored snapshot rolled forward to each entry's date.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample())
    }

    /// The gallery shows believable sample values; anywhere else, the person's own data (or the empty state).
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let now = Date.now
        if context.isPreview {
            completion(SnapshotEntry(date: now, snapshot: .sample(now: now)))
            return
        }
        let stored = WidgetSnapshotStore.shared.read()
        completion(SnapshotEntry(date: now, snapshot: stored?.rolled(to: now, calendar: .current)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entries = WidgetTimeline.entries(from: .now, stored: WidgetSnapshotStore.shared.read(), calendar: .current)
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetFamily {
    var isAccessory: Bool {
        self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline
    }
}
