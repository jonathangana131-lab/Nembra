import Foundation
import NembraCore

/// Constructs one genuinely fresh durable capture recorder from exact terminal
/// queue-resolution authority and carries the resulting session generation as
/// producer-issued proof.
///
/// This is software lifecycle authority only. It does not establish physical
/// scooter identity, BLE/GATT semantics, or hardware behavior.
struct PassiveCoreBluetoothTerminalFreshTargetSession: Sendable {
    enum StateError: Error, Equatable, Sendable {
        case targetSessionGenerationExhausted
    }

    /// Proof that a recorder for the exact next target-session generation was
    /// actually constructed from one exact terminal-resolution receipt. The
    /// initializer is file-private so another package file cannot wrap a naked
    /// caller-chosen generation and call it durable-session authority.
    struct Receipt: Equatable, Sendable {
        let terminalResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt
        let targetSessionGeneration: UInt64
        let sessionID: UUID
        /// Opaque process-local identity for this exact provisioning event. It is
        /// not persisted capture evidence and carries no BLE/RF meaning.
        let provisioningIdentity: UUID

        fileprivate init(
            terminalResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt,
            targetSessionGeneration: UInt64,
            sessionID: UUID,
            provisioningIdentity: UUID = UUID()
        ) {
            self.terminalResolution = terminalResolution
            self.targetSessionGeneration = targetSessionGeneration
            self.sessionID = sessionID
            self.provisioningIdentity = provisioningIdentity
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

    /// The exact terminal resolution is the predecessor authority. Generation is
    /// derived rather than supplied by the caller, and proof is issued only after
    /// `PassiveCoreBluetoothCaptureRecorder` construction succeeds.
    static func create(
        after terminalResolution: PassiveCoreBluetoothTerminalQueueResolution.Receipt,
        id: UUID = UUID(),
        vehicleIdentity: VehicleIdentity,
        startedAt: Date = Date()
    ) throws -> Self {
        let previousGeneration = terminalResolution.terminalAuthority.targetSessionGeneration
        guard previousGeneration != UInt64.max else {
            throw StateError.targetSessionGenerationExhausted
        }

        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            id: id,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        let receipt = Receipt(
            terminalResolution: terminalResolution,
            targetSessionGeneration: previousGeneration + 1,
            sessionID: id
        )
        return Self(recorder: recorder, receipt: receipt)
    }
}
