import SwiftUI

/// Dedicated one-time ES80 Bluetooth evidence build.
///
/// This branch intentionally does not boot the normal Nembra product or the release-grade
/// Experiment One authorization stack. Its only job is to collect passive CoreBluetooth evidence
/// once, export the raw JSON, and then be discarded after the ES80 transport is understood.
@main
@MainActor
struct NembraApp: App {
    var body: some Scene {
        WindowGroup {
            ES80OneTimeBluetoothDumpView()
        }
    }
}
