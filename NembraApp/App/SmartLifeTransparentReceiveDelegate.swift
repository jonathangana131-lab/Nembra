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

/// Owns the process-global Tuya BLE-manager receive-delegate slot for exactly one
/// package-authenticated C7D09A22 connection generation.
///
/// `ThingSmartBLEManager.delegate` is weak, so this lease deliberately holds the
/// receive adapter strongly. It will not replace another component's delegate and it
/// will only clear the manager slot when that slot still belongs to this lease.
/// Arming is downstream of package authentication; merely completing `connectBLE`
/// is not sufficient authority to install the receive path.
@MainActor
final class SmartLifeTransparentReceiveLease {
    typealias Generation =
        C7D09A22DocumentedTransparentLivePreflight.AuthenticatedConnectionGeneration

    private let preflight: C7D09A22DocumentedTransparentLivePreflight
    private let manager: ThingSmartBLEManager
    private let receiveDelegate: SmartLifeTransparentReceiveDelegate

    private(set) var generation: Generation?

    init(
        preflight: C7D09A22DocumentedTransparentLivePreflight,
        manager: ThingSmartBLEManager = ThingSmartBLEManager.sharedInstance()
    ) {
        self.preflight = preflight
        self.manager = manager
        self.receiveDelegate = SmartLifeTransparentReceiveDelegate(preflight: preflight)
    }

    /// Arms package custody first, then installs the documented device-to-app receive
    /// callback only if the process-global delegate slot is empty or already ours.
    /// A foreign delegate is never displaced.
    @discardableResult
    func armAndInstallAfterSmartLifeAuthentication() async -> Generation? {
        if let generation {
            return generation
        }

        guard let armedGeneration = await preflight.armAfterSmartLifeAuthentication() else {
            return nil
        }

        guard manager.delegate == nil || ownsManagerDelegateSlot else {
            preflight.terminalLifecycleDidOccur(for: armedGeneration)
            return nil
        }

        manager.delegate = receiveDelegate

        guard ownsManagerDelegateSlot else {
            preflight.terminalLifecycleDidOccur(for: armedGeneration)
            return nil
        }

        generation = armedGeneration
        return armedGeneration
    }

    /// Terminal teardown is generation-fenced inside the package. The global manager
    /// slot is cleared only when it still points at this lease's adapter, so a later
    /// owner cannot be accidentally disconnected by a stale lifecycle callback.
    func terminalLifecycleDidOccur() {
        let retiringGeneration = generation

        if ownsManagerDelegateSlot {
            manager.delegate = nil
        }

        generation = nil
        preflight.terminalLifecycleDidOccur(for: retiringGeneration)
    }

    private var ownsManagerDelegateSlot: Bool {
        guard let installedDelegate = manager.delegate else {
            return false
        }
        return (installedDelegate as AnyObject) === receiveDelegate
    }
}
#endif
