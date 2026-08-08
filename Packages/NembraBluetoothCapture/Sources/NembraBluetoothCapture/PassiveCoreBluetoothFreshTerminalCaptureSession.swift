import Foundation
import NembraCore

/// One genuinely fresh recorder/session created for post-terminal Capture reuse.
///
/// The reopen authority is intentionally not caller-constructible. A package caller
/// can obtain it only by asking this producer to construct the replacement recorder
/// first. This closes the weaker pattern where `oldGeneration + 1` could be invented
/// as if a durable capture session already existed.
///
/// This is software lifecycle authority only. It does not establish BLE/RF identity,
/// protocol semantics, physical scooter truth, or command acknowledgement.
struct PassiveCoreBluetoothFreshTerminalCaptureSession: Sendable {
    struct ReopenAuthority: Equatable, Sendable {
        let terminalAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let terminalTransactionRevision: UInt64
        let terminalTransactionIdentity: UUID
        let horizonQueueCutoff: UInt64
        let resolvedThroughQueueSequence: UInt64
        let freshArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext
        let targetPeripheralIdentifier: UUID
        /// Opaque process-local identity for this exact successfully-created
        /// replacement recorder/session. It is not persisted evidence.
        let identity: UUID

        fileprivate init(
            resolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt,
            freshArtifactAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
            targetPeripheralIdentifier: UUID,
            identity: UUID = UUID()
        ) {
            terminalAuthority = resolution.terminalAuthority
            terminalTransactionRevision = resolution.terminalTransactionRevision
            terminalTransactionIdentity = resolution.terminalTransactionIdentity
            horizonQueueCutoff = resolution.horizonQueueCutoff
            resolvedThroughQueueSequence = resolution.resolvedThroughQueueSequence
            self.freshArtifactAuthority = freshArtifactAuthority
            self.targetPeripheralIdentifier = targetPeripheralIdentifier
            self.identity = identity
        }
    }

    enum CreationError: Error, Equatable, Sendable {
        case targetSessionGenerationExhausted
    }

    let recorder: PassiveCoreBluetoothCaptureRecorder
    let reopenAuthority: ReopenAuthority

    private init(
        recorder: PassiveCoreBluetoothCaptureRecorder,
        reopenAuthority: ReopenAuthority
    ) {
        self.recorder = recorder
        self.reopenAuthority = reopenAuthority
    }

    /// Creates the replacement recorder before minting any authority that could
    /// reopen the terminal queue gate. If recorder construction throws, no reopen
    /// authority exists and the old terminal lifecycle remains closed.
    static func create(
        after resolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt,
        targetPeripheralIdentifier: UUID,
        vehicleIdentity: VehicleIdentity,
        sessionID: UUID = UUID(),
        startedAt: Date = Date()
    ) throws -> Self {
        guard resolution.terminalAuthority.targetSessionGeneration < UInt64.max else {
            throw CreationError.targetSessionGenerationExhausted
        }

        let freshArtifactAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: resolution.terminalAuthority.targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            id: sessionID,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        let reopenAuthority = ReopenAuthority(
            resolution: resolution,
            freshArtifactAuthority: freshArtifactAuthority,
            targetPeripheralIdentifier: targetPeripheralIdentifier
        )
        return Self(
            recorder: recorder,
            reopenAuthority: reopenAuthority
        )
    }
}
