import Dispatch
import Foundation
import NembraCore

/// One synchronous MainActor decision that binds a lifecycle-boundary intent to
/// the exact controller FIFO prefix, recorder-completed prefix, artifact authority,
/// and local clock correlation seen before the first asynchronous hop.
///
/// `observedAtUptimeNanoseconds` is the software chronology authority. `observedAtDate`
/// is wall-clock correlation metadata only and must never be treated as monotonic.
/// Neither clock is a BLE/RF emission timestamp, and this type establishes no
/// physical scooter state.
struct PassiveCoreBluetoothObservationBoundaryDecision: Equatable, Sendable {
    enum StateError: Error, Equatable, Sendable {
        case processedFrontierBeyondCutoff
    }

    let queueKind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind
    let queueCutoff: UInt64
    let processedThrough: UInt64
    let authority: PassiveCoreBluetoothArtifactAuthorityContext
    let observedAtUptimeNanoseconds: UInt64
    let observedAtDate: Date

    /// Mechanical mapping into the already-accepted durable capture vocabulary.
    /// Keeping it on the decision token prevents controller wiring from beginning
    /// one queue-boundary kind and accidentally recording the other schema kind.
    var observationBoundaryKind: PassiveBluetoothObservationBoundaryKind {
        switch queueKind {
        case .finiteAcquisitionReady:
            .finiteAcquisitionReady
        case .observationHorizon:
            .observationHorizon
        }
    }

    /// Captures the complete boundary decision synchronously on the MainActor.
    /// Production callers cannot inject a future/past lifecycle clock through this
    /// type; deterministic explicit-clock construction is intentionally private.
    @MainActor
    static func capture(
        kind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind,
        queueCutoff: UInt64,
        processedThrough: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws -> Self {
        guard processedThrough <= queueCutoff else {
            throw StateError.processedFrontierBeyondCutoff
        }

        return Self(
            queueKind: kind,
            queueCutoff: queueCutoff,
            processedThrough: processedThrough,
            authority: authority,
            observedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            observedAtDate: Date()
        )
    }

    /// Records this exact pre-await decision through the recorder's package-owned
    /// explicit-clock path. Controller wiring should use this helper rather than
    /// the recorder's public clock-owning overload, which would resample after the
    /// asynchronous actor hop and sever the decision-time chronology.
    func recordBoundary(on recorder: PassiveCoreBluetoothCaptureRecorder) async throws {
        try await recorder.recordObservationBoundary(
            observationBoundaryKind,
            observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
            observedAtDate: observedAtDate
        )
    }

    private init(
        queueKind: PassiveCoreBluetoothObservationBoundaryQueueGate.BoundaryKind,
        queueCutoff: UInt64,
        processedThrough: UInt64,
        authority: PassiveCoreBluetoothArtifactAuthorityContext,
        observedAtUptimeNanoseconds: UInt64,
        observedAtDate: Date
    ) {
        self.queueKind = queueKind
        self.queueCutoff = queueCutoff
        self.processedThrough = processedThrough
        self.authority = authority
        self.observedAtUptimeNanoseconds = observedAtUptimeNanoseconds
        self.observedAtDate = observedAtDate
    }
}
