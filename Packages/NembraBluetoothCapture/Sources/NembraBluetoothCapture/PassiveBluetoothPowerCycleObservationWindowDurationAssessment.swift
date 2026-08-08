import Foundation

/// Fail-closed duration-policy assessment for one completed four-window power-cycle result.
///
/// The live producer intentionally permits a caller-defined minimum because research/debug flows
/// may need shorter software windows. A completed result therefore does not, by itself, prove that
/// it satisfies experiment one's stronger per-phase minimum. Downstream provenance must supply the
/// required policy explicitly and preserve this producer-derived assessment with the artifact.
///
/// This assessment uses only the result's monotonic callback-receipt window bounds. It does not
/// prove RF completeness, advertisement cadence, physical scooter power state, ES80 identity, or
/// protocol semantics.
public struct PassiveBluetoothPowerCycleObservationWindowDurationAssessment: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case sufficient
        case invalidMinimumDuration
        case invalidWindowSet
        case nonMonotonicWindowClock
        case insufficientDuration
    }

    public struct WindowEvidence: Equatable, Sendable {
        public let phase: PassiveBluetoothPowerCycleObservationPhase
        public let windowSequence: PassiveBluetoothCandidateObservationWindowSequence
        public let observedDurationNanoseconds: UInt64

        fileprivate init(
            phase: PassiveBluetoothPowerCycleObservationPhase,
            windowSequence: PassiveBluetoothCandidateObservationWindowSequence,
            observedDurationNanoseconds: UInt64
        ) {
            self.phase = phase
            self.windowSequence = windowSequence
            self.observedDurationNanoseconds = observedDurationNanoseconds
        }
    }

    public let status: Status
    /// The explicit downstream policy this assessment evaluated, retained for durable provenance.
    public let minimumRequiredDurationNanoseconds: UInt64
    /// Ordered, recomputed monotonic receipt durations for the exact four result windows.
    public let windows: [WindowEvidence]

    public var isDurationSufficient: Bool {
        status == .sufficient
    }

    private init(
        status: Status,
        minimumRequiredDurationNanoseconds: UInt64,
        windows: [WindowEvidence]
    ) {
        self.status = status
        self.minimumRequiredDurationNanoseconds = minimumRequiredDurationNanoseconds
        self.windows = windows
    }

    /// Evaluates a caller-required minimum against the exact completed window receipts.
    ///
    /// The canonical OFF₁ -> ON₁ -> OFF₂ -> ON₂ phase order and strictly increasing package-issued
    /// window sequence are rechecked instead of trusting only `result != nil`. A zero minimum fails
    /// closed so an accidentally unconfigured provenance gate cannot silently pass.
    public static func assess(
        result: PassiveBluetoothPowerCycleObservationResult,
        minimumDurationNanoseconds: UInt64
    ) -> Self {
        guard minimumDurationNanoseconds > 0 else {
            return Self(
                status: .invalidMinimumDuration,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                windows: []
            )
        }

        let expectedPhases = PassiveBluetoothPowerCycleObservationPhase.allCases
        guard result.windows.count == expectedPhases.count,
              result.windows.map(\.phase) == expectedPhases else {
            return Self(
                status: .invalidWindowSet,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                windows: []
            )
        }

        var previousSequence: UInt64?
        var evidence: [WindowEvidence] = []
        evidence.reserveCapacity(result.windows.count)

        for receipt in result.windows {
            if let previousSequence,
               receipt.windowSequence.rawValue <= previousSequence {
                return Self(
                    status: .invalidWindowSet,
                    minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                    windows: evidence
                )
            }
            previousSequence = receipt.windowSequence.rawValue

            guard receipt.endedAtUptimeNanoseconds >= receipt.startedAtUptimeNanoseconds else {
                return Self(
                    status: .nonMonotonicWindowClock,
                    minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                    windows: evidence
                )
            }

            evidence.append(
                WindowEvidence(
                    phase: receipt.phase,
                    windowSequence: receipt.windowSequence,
                    observedDurationNanoseconds:
                        receipt.endedAtUptimeNanoseconds - receipt.startedAtUptimeNanoseconds
                )
            )
        }

        let status: Status = evidence.allSatisfy {
            $0.observedDurationNanoseconds >= minimumDurationNanoseconds
        } ? .sufficient : .insufficientDuration

        return Self(
            status: status,
            minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
            windows: evidence
        )
    }
}
