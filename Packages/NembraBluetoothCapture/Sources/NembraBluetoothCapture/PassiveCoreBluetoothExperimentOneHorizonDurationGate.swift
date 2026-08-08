import Dispatch
import Foundation

/// Experiment One's producer-owned minimum Ready -> Horizon admission barrier.
///
/// This is a software procedure gate only. Passing it proves that Nembra's local monotonic clock
/// advanced by at least the fixed Experiment One minimum after the exact committed Ready decision.
/// It does not prove continuous RF traffic, physical scooter state, packet cadence, target identity,
/// or any GATT/Tuya/telemetry semantic.
///
/// Production admission samples `DispatchTime` internally so a controller cannot weaken the
/// procedure by supplying its own clock value. The resulting permit retains the exact committed
/// Ready epoch; actual Horizon admission therefore still revalidates the canonical artifact fence
/// and the gate-owned Ready revision + process-local identity when `beginHorizon(...)` is called.
enum PassiveCoreBluetoothExperimentOneHorizonDurationGate {
    enum StateError: Error, Equatable, Sendable {
        case uptimeRegressed(
            readyUptimeNanoseconds: UInt64,
            currentUptimeNanoseconds: UInt64
        )
        case minimumObservationDurationNotSatisfied(
            requiredNanoseconds: UInt64,
            observedNanoseconds: UInt64
        )
    }

    struct Permit: Equatable, Sendable {
        private let committedReadyEpoch:
            PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch

        let readyObservedAtUptimeNanoseconds: UInt64
        let admittedAtUptimeNanoseconds: UInt64
        let observedDurationNanoseconds: UInt64

        var authority: PassiveCoreBluetoothArtifactAuthorityContext {
            committedReadyEpoch.authority
        }

        var readyTransactionRevision: UInt64 {
            committedReadyEpoch.transactionRevision
        }

        var readyTransactionIdentity: UUID {
            committedReadyEpoch.transactionIdentity
        }

        /// Begins Horizon only from the exact Ready epoch that earned this duration permit.
        /// Queue/FIFO and canonical-artifact-authority checks remain owned by the accepted
        /// Ready/Horizon transaction machinery rather than being duplicated here.
        @MainActor
        func beginHorizon(
            queueCutoff: UInt64,
            processedThrough: UInt64,
            gate: inout PassiveCoreBluetoothObservationBoundaryQueueGate
        ) throws -> PassiveCoreBluetoothObservationBoundaryTransactionDecision.HorizonAdmission {
            try committedReadyEpoch.beginHorizon(
                queueCutoff: queueCutoff,
                processedThrough: processedThrough,
                gate: &gate
            )
        }

        fileprivate init(
            committedReadyEpoch:
                PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch,
            admittedAtUptimeNanoseconds: UInt64,
            observedDurationNanoseconds: UInt64
        ) {
            self.committedReadyEpoch = committedReadyEpoch
            readyObservedAtUptimeNanoseconds = committedReadyEpoch.observedAtUptimeNanoseconds
            self.admittedAtUptimeNanoseconds = admittedAtUptimeNanoseconds
            self.observedDurationNanoseconds = observedDurationNanoseconds
        }
    }

    static var minimumObservationDurationNanoseconds: UInt64 {
        PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    }

    /// Production-only clock admission. There is intentionally no overload accepting a caller
    /// supplied uptime. Deterministic tests exercise `validatedElapsedDuration(...)`, which can
    /// validate the arithmetic/policy but cannot issue a Horizon permit.
    @MainActor
    static func admit(
        committedReadyEpoch:
            PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
    ) throws -> Permit {
        let currentUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let observedDurationNanoseconds = try validatedElapsedDuration(
            readyUptimeNanoseconds: committedReadyEpoch.observedAtUptimeNanoseconds,
            currentUptimeNanoseconds: currentUptimeNanoseconds
        )

        return Permit(
            committedReadyEpoch: committedReadyEpoch,
            admittedAtUptimeNanoseconds: currentUptimeNanoseconds,
            observedDurationNanoseconds: observedDurationNanoseconds
        )
    }

    /// Pure policy seam for deterministic arithmetic tests. This function cannot mint a permit,
    /// mutate lifecycle state, or authorize Horizon admission.
    static func validatedElapsedDuration(
        readyUptimeNanoseconds: UInt64,
        currentUptimeNanoseconds: UInt64
    ) throws -> UInt64 {
        guard currentUptimeNanoseconds >= readyUptimeNanoseconds else {
            throw StateError.uptimeRegressed(
                readyUptimeNanoseconds: readyUptimeNanoseconds,
                currentUptimeNanoseconds: currentUptimeNanoseconds
            )
        }

        let observedNanoseconds = currentUptimeNanoseconds - readyUptimeNanoseconds
        let requiredNanoseconds = minimumObservationDurationNanoseconds
        guard observedNanoseconds >= requiredNanoseconds else {
            throw StateError.minimumObservationDurationNotSatisfied(
                requiredNanoseconds: requiredNanoseconds,
                observedNanoseconds: observedNanoseconds
            )
        }

        return observedNanoseconds
    }
}
