@preconcurrency import CoreBluetooth
import SwiftUI

// Shared by the legacy raw capture implementation that remains available in this standalone project.
let CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable

@main
@MainActor
struct NembraCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            NembraCaptureRootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// The authenticated Bluetooth write handshake stays intentionally locked until the Tuya account
/// metadata tells us exactly which bound-device credentials/protocol generation this scooter uses.
/// This prevents a second pointless outdoor run and prevents guessed control writes.
struct TuyaSecureLinkPreflightView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TUYA SECURE LINK")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.green)
            Text("Cloud metadata first")
                .font(.largeTitle.bold())
            Text("The scooter is already bound to Tuya. Share the redacted Tuya metadata JSON from the previous screen first. That tells Nembra the exact device identity, DP definitions, and local strategy needed to build the authenticated Bluetooth step without guessing.")
                .foregroundStyle(.secondary)
            Label("No outdoor riding is needed for this step.", systemImage: "figure.stand")
                .foregroundStyle(.green)
            Label("No unbind, reset, speed-limit, lock, or other scooter command is sent.", systemImage: "shield.checkered")
                .foregroundStyle(.green)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Secure Link")
        .navigationBarTitleDisplayMode(.inline)
    }
}
