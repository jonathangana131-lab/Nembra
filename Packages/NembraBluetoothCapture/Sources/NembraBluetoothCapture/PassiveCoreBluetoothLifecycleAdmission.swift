/// Fail-closed admission policy for broad candidate discovery callbacks.
/// CoreBluetooth does not attach an app-owned scan-generation token to
/// `didDiscover`, so callbacks are admitted only while this exact manager is
/// powered on and the controller still owns an active scan interval.
struct PassiveCoreBluetoothDiscoveryAdmissionPolicy: Equatable, Sendable {
    static func accepts(
        callbackIsFromActiveManager: Bool,
        isPoweredOn: Bool,
        isScanning: Bool
    ) -> Bool {
        callbackIsFromActiveManager && isPoweredOn && isScanning
    }
}

/// Indicates whether the caller has already recorded the continuity boundary
/// that justifies a connection cancellation. Public/operator cancellation owns
/// its boundary here; watchdog timeout owns a more specific timeout boundary
/// before it reaches the shared cancellation mechanics.
enum PassiveCoreBluetoothCancellationBoundary: Equatable, Sendable {
    case recordCancellationRequest
    case interruptionAlreadyRecorded

    var shouldRecordCancellationRequest: Bool {
        self == .recordCancellationRequest
    }
}
