import Foundation

/// Producer-owned monotonic admission for the physical Experiment One observation
/// horizon. This gate answers only whether enough system-uptime time has elapsed
/// since the exact committed Ready epoch to permit Horizon admission.
///
/// It is deliberately separate from immutable artifact assessment:
/// - this gate prevents an early caller from mutating the queue lifecycle into H;
/// - `PassiveBluetoothObservationWindowDurationAssessment` independently verifies
///   the final frozen artifact after H exists, including continuity evidence.
///
/// The trusted authorization API samples `DispatchTime.now().uptimeNanoseconds`
/// internally. Callers cannot supply a future timestamp to mint a Permit. The pure
/// `evaluate(...)` helper is descriptive/testable math only and issues no authority.
///
/// Software observation-clock authority only. This does not prove BLE/RF traffic,
/// scooter identity, physical state, protocol semantics, or hardware behavior.
struct PassiveCoreBluetoothObservationHorizonMinimumDurationGate: Sendable {
    /// Experiment One procedure policy has exactly one production authority. The
    /// duration gate consumes the sealed experiment policy instead of restating the
    /// sixty-second literal, so an accepted recipe revision cannot silently diverge
    /// from the lifecycle mutation gate.
    static var experimentOneMinimumDurationNanoseconds: UInt64 {
        PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
    }

    enum Status: Equatable, Sendable {
        case invalidMinimumDuration
        case monotonicClockRegressed(ready: UInt64, observed: UInt64)
        case waiting(required: UInt64, observed: UInt64, remaining: UInt64)
        case eligible(required: UInt64, observed: UInt64)
    }

    enum StateError: Error, Equatable, Sendable {
        case monotonicClockRegressed(ready: UInt64, observed: UInt64)
        case minimumObservationDurationNotReached(required: UInt64, observed: UInt64)
    }

    /// Producer-issued proof that the real system monotonic clock satisfied the
    /// fixed Experiment One Ready -> Horizon minimum for this exact committed Ready
    /// epoch. The initializer is file-private so descriptive `Status` values cannot
    /// be promoted into mutation authority by another package file.
    struct Permit: Equatable, Sendable {
        private let committedReadyEpoch:
            PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
        let readyAtUptimeNanoseconds: UInt64
        let authorizedAtUptimeNanoseconds: UInt64
        let requiredDurationNanoseconds: UInt64

        var observedDurationNanoseconds: UInt64 {
            authorizedAtUptimeNanoseconds - readyAtUptimeNanoseconds
        }

        /// Horizon allocation remains under the exact committed Ready transaction
        /// identity and canonical authority fence. This call performs no await before
        /// the existing `CommittedReadyEpoch.beginHorizon(...)` mutation.
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
            committedReadyEpoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch,
            readyAtUptimeNanoseconds: UInt64,
            authorizedAtUptimeNanoseconds: UInt64,
            requiredDurationNanoseconds: UInt64
        ) {
            self.committedReadyEpoch = committedReadyEpoch
            self.readyAtUptimeNanoseconds = readyAtUptimeNanoseconds
            self.authorizedAtUptimeNanoseconds = authorizedAtUptimeNanoseconds
            self.requiredDurationNanoseconds = requiredDurationNanoseconds
        }
    }

    /// Pure, non-authoritative monotonic interval evaluation. This exists so the
    /// boundary math can be exhaustively tested without waiting sixty real seconds.
    /// A result from this method is never sufficient to allocate Horizon.
    static func evaluate(
        readyAtUptimeNanoseconds ready: UInt64,
        observedAtUptimeNanoseconds observed: UInt64,
        minimumDurationNanoseconds minimum: UInt64
    ) -> Status {
        guard minimum > 0 else {
            return .invalidMinimumDuration
        }
        guard observed >= ready else {
            return .monotonicClockRegressed(ready: ready, observed: observed)
        }

        let duration = observed - ready
        guard duration >= minimum else {
            return .waiting(
                required: minimum,
                observed: duration,
                remaining: minimum - duration
            )
        }
        return .eligible(required: minimum, observed: duration)
    }

    /// Descriptive current status for product presentation. The returned value is
    /// not mutation authority; callers must still obtain `Permit` immediately before
    /// entering Horizon.
    static func currentExperimentOneStatus(
        for committedReadyEpoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
    ) -> Status {
        evaluate(
            readyAtUptimeNanoseconds: committedReadyEpoch.observedAtUptimeNanoseconds,
            observedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            minimumDurationNanoseconds: experimentOneMinimumDurationNanoseconds
        )
    }

    /// Samples the trusted system monotonic clock and issues the only permit this
    /// file can create. An early or regressed clock fails before queue-gate mutation,
    /// leaving the committed Ready epoch in `.observing`.
    static func authorizeExperimentOneHorizon(
        for committedReadyEpoch: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedReadyEpoch
    ) throws -> Permit {
        let observed = DispatchTime.now().uptimeNanoseconds
        let ready = committedReadyEpoch.observedAtUptimeNanoseconds
        switch evaluate(
            readyAtUptimeNanoseconds: ready,
            observedAtUptimeNanoseconds: observed,
            minimumDurationNanoseconds: experimentOneMinimumDurationNanoseconds
        ) {
        case .eligible(let required, _):
            return Permit(
                committedReadyEpoch: committedReadyEpoch,
                readyAtUptimeNanoseconds: ready,
                authorizedAtUptimeNanoseconds: observed,
                requiredDurationNanoseconds: required
            )
        case .waiting(let required, let duration, _):
            throw StateError.minimumObservationDurationNotReached(
                required: required,
                observed: duration
            )
        case .monotonicClockRegressed(let ready, let observed):
            throw StateError.monotonicClockRegressed(ready: ready, observed: observed)
        case .invalidMinimumDuration:
            // The fixed Experiment One minimum is compile-time nonzero. Preserve a
            // fail-closed branch if that invariant is ever changed incorrectly.
            throw StateError.minimumObservationDurationNotReached(
                required: experimentOneMinimumDurationNanoseconds,
                observed: 0
            )
        }
    }
}
