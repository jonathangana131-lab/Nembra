import Foundation
import NembraBluetoothCapture

#if canImport(ThingSmartHomeKit)
import ThingSmartHomeKit

/// Read-only bridge from Tuya's documented BLE-manager receive callback into the
/// package-owned C7D09A22 authenticated transport preflight.
///
/// This object deliberately implements only device-to-app transparent receipt. It has
/// no publish/write/reset/remove/unbind surface and therefore cannot mutate the scooter.
/// Exact device and generation admission remain inside
/// `C7D09A22DocumentedTransparentLivePreflight`.
@MainActor
final class SmartLifeTransparentReceiveDelegate: NSObject, ThingSmartBLEManagerDelegate {
    private let preflight: C7D09A22DocumentedTransparentLivePreflight

    init(preflight: C7D09A22DocumentedTransparentLivePreflight) {
        self.preflight = preflight
        super.init()
    }

    /// Tuya Smart Life App SDK documented device-to-app transparent receive callback.
    /// The package boundary handles optionality, empty payloads, exact device identity,
    /// and generation fencing; this adapter does not infer protocol or DP semantics.
    func bleReceiveTransparentData(_ data: Data!, devId: String!) {
        preflight.receiveDocumentedSmartLifeCallback(payload: data, deviceID: devId)
    }
}
#endif
