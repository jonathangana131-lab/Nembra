import Foundation
import NembraCore

/// Constructs one genuinely fresh durable capture recorder from exact abandoned-queue
/// resolution authority and carries the resulting session generation as producer-issued proof.
///
/// This is software lifecycle authority only. It does not establish physical scooter
/// identity, BLE/GATT semantics, telemetry meaning, or hardware behavior.
struct PassiveCoreBluetoothAbortedFreshTargetSession: Sendable {
    enum StateError: Error, Equatable, Sendable {
        case targetSessionGenerationExhausted
    }

    /// Proof that a recorder for the exact next target-session generation was actually
    /// constructed from one exact abandoned-queue resolution receipt. File-private init
    /// prevents another package file from wrapping a naked generation and calling it
    /// durable-session authority.
    ///
    /// The receipt strongly retains the exact recorder whose construction earned the
    /// proof. A detached receipt therefore cannot outlive that recorder and later let a
    /// recycled process address satisfy stale fresh-session authority.
    struct Receipt: Equatable, Sendable {
        let abortedResolution: PassiveCoreBluetoothAbortedQueueResolution.Receipt
        let targetSessionGeneration: UInt64
        let sessionID: UUID
        let recorder: PassiveCoreBluetoothCaptureRecorder
        var recorderIdentity: ObjectIdentifier {
            ObjectIdentifier(recorder)
        }
        let provisioningIdentity: UUID

        fileprivate init(
            abortedResolution: PassiveCoreBluetoothAbortedQueueResolution.Receipt,
            targetSessionGeneration: UInt64,
            sessionID: UUID,
            recorder: PassiveCoreBluetoothCaptureRecorder,
            provisioningIdentity: UUID = UUID()
        ) {
            self.abortedResolution = abortedResolution
            self.targetSessionGeneration = targetSessionGeneration
            self.sessionID = sessionID
            self.recorder = recorder
            self.provisioningIdentity = provisioningIdentity
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.abortedResolution == rhs.abortedResolution
                && lhs.targetSessionGeneration == rhs.targetSessionGeneration
                && lhs.sessionID == rhs.sessionID
                && ObjectIdentifier(lhs.recorder) == ObjectIdentifier(rhs.recorder)
                && lhs.provisioningIdentity == rhs.provisioningIdentity
        }
    }

    let recorder: PassiveCoreBluetoothCaptureRecorder
    let receipt: Receipt

    private init(
        recorder: PassiveCoreBluetoothCaptureRecorder,
        receipt: Receipt
    ) {
        self.recorder = recorder
        self.receipt = receipt
    }

    /// The exact abandoned resolution is predecessor authority. Generation is derived
    /// rather than supplied by the caller, and proof is issued only after recorder
    /// construction succeeds.
    static func create(
        after abortedResolution: PassiveCoreBluetoothAbortedQueueResolution.Receipt,
        id: UUID = UUID(),
        vehicleIdentity: VehicleIdentity,
        startedAt: Date = Date()
    ) throws -> Self {
        let previousGeneration = abortedResolution.abortReceipt.abandonedTargetSessionGeneration
        guard previousGeneration != UInt64.max else {
            throw StateError.targetSessionGenerationExhausted
        }

        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            id: id,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        let receipt = Receipt(
            abortedResolution: abortedResolution,
            targetSessionGeneration: previousGeneration + 1,
            sessionID: id,
            recorder: recorder
        )
        return Self(recorder: recorder, receipt: receipt)
    }
}
