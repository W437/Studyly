import SwiftUI

@main
struct CramlessApp: App {
    @UIApplicationDelegateAdaptor(CramlessAppDelegate.self) private var appDelegate
    @State private var app = AppModel.forLaunch()

    #if DEBUG
    init() {
        // `CRAMLESS_OFFLINE_BENCH=1` measures the offline tutor and this iPhone's model on the device (see `OfflineBench`).
        OfflineBench.runIfRequested()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .modelContainer(app.container)
        }
    }
}
