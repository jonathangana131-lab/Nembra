import SwiftUI

@main
struct NembraApp: App {
    @State private var runtime = AppBootstrap.makeRuntime()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(runtime.vehicleStore)
                .environment(runtime.rideStore)
                .environment(runtime.rideHistoryStore)
                .task { await runtime.start() }
        }
    }
}
