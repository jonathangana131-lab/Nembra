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

/// Fixed evidence semantics for the shared transport-cancellation mechanics.
/// Callers choose a concrete product cause rather than supplying arbitrary text,
/// so teardown cannot silently mint misleading continuity evidence.
enum PassiveCoreBluetoothCancellationCause: Equatable, Sendable {
    case operatorRequest
    case foregroundIntegrityLoss
    case finalizedArtifactTeardown
    case interruptionAlreadyRecorded

    var interruptionReason: String? {
        switch self {
        case .operatorRequest:
            "connection cancellation requested"
        case .foregroundIntegrityLoss:
            "foreground evidence integrity lost"
        case .finalizedArtifactTeardown, .interruptionAlreadyRecorded:
            nil
        }
    }

    var diagnosticMessage: String? {
        switch self {
        case .operatorRequest:
            "Connection cancellation requested."
        case .foregroundIntegrityLoss:
            "Connection ended because foreground evidence integrity was lost."
        case .finalizedArtifactTeardown, .interruptionAlreadyRecorded:
            nil
        }
    }
}
