import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center and Lock Screen control: "Start today's session". Its action, `StartSessionIntent`, is in
/// Shared/ so the app performs it (the control lives here, the routing lives in the app).
struct StartSessionControl: ControlWidget {
    static let kind = "com.loopware.Capling.startSession"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartSessionIntent()) {
                Label("Today's session", systemImage: "graduationcap.fill")
            }
            .tint(CLColor.tangerine)
        }
        .displayName("Start today's session")
        .description("Opens Capling on today's session.")
    }
}
