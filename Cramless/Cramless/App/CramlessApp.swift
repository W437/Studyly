import SwiftUI

@main
struct CramlessApp: App {
    @UIApplicationDelegateAdaptor(CramlessAppDelegate.self) private var appDelegate
    @State private var app = AppModel.forLaunch()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .modelContainer(app.container)
        }
    }
}
