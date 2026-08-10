@preconcurrency import CoreBluetooth
import SwiftUI

let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main @MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureP0Root()
                .preferredColorScheme(.dark)
        }
    }
}
