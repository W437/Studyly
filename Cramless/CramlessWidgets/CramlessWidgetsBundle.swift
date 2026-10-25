import SwiftUI
import WidgetKit

/// Capling's widgets, Live Activities and control. This extension sees only its own files and Shared/: it reads
/// the snapshot the app writes to the App Group (`WidgetSnapshotStore`) and draws the views in Shared/Widgets/.
@main
struct CramlessWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ExamWidget()
        TodayWidget()
        StreakWidget()
        SessionLiveActivity()
        ExamWeekLiveActivity()
        StartSessionControl()
    }
}
