import SwiftUI

@main
struct NembraApp: App {
    @State private var vehicleStore = AppBootstrap.makeVehicleStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(vehicleStore)
                .task { await vehicleStore.start() }
        }
    }
}
