import Foundation

/// Fail-closed procedure-duration assessment for one producer-derived repeated
/// OFF₁ -> ON₁ -> OFF₂ -> ON₂ observation result.
///
/// The live CoreBluetooth producer owns callback admission and receipt clocks.
/// This value answers a separate downstream question: did the exact four
/// receipt-bounded windows that earned `correlation` each meet a caller-required
/// monotonic duration policy?
///
/// The assessment deliberately re-binds receipt sequences to the retained
/// package-issued snapshots and correlation report before using their durations.
/// That prevents a detached or internally malformed window list from being
/// treated as the sampling policy that earned a target-correlation result.
///
/// A sufficient result is Nembra procedure evidence only. It does not prove BLE
/// cadence, RF completeness, physical power state, scooter identity, or protocol
/// semantics.
public struct PassiveBluetoothPowerCycleWindowDurationAssessment: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case invalidMinimumDuration
        case resultProvenanceMismatch
        case nonMonotonicWindowClock
        case insufficientDuration
        case sufficient
    }

    public let status: Status
    public let minimumRequiredWindowDurationNanoseconds: UInt64
    public let observedWindowDurationsNanoseconds: [UInt64]
    public let insufficientPhases: [PassiveBluetoothPowerCycleObservationPhase]

    public var isDurationSufficient: Bool {
        status == .sufficient
    }

    private init(
        status: Status,
        minimumRequiredWindowDurationNanoseconds: UInt64,
        observedWindowDurationsNanoseconds: [UInt64] = [],
        insufficientPhases: [PassiveBluetoothPowerCycleObservationPhase] = []
    ) {
        self.status = status
        self.minimumRequiredWindowDurationNanoseconds = minimumRequiredWindowDurationNanoseconds
        self.observedWindowDurationsNanoseconds = observedWindowDurationsNanoseconds
        self.insufficientPhases = insufficientPhases
    }

    /// Re-evaluates the immutable receipt spans against an explicit downstream
    /// policy. For experiment one, the caller supplies 10_000_000_000 ns rather
    /// than relying on the live producer's private construction-time minimum or
    /// an operator/UI countdown.
    public static func assess(
        result: PassiveBluetoothPowerCycleObservationResult,
        minimumWindowDurationNanoseconds: UInt64
    ) -> Self {
        guard minimumWindowDurationNanoseconds > 0 else {
            return Self(
                status: .invalidMinimumDuration,
                minimumRequiredWindowDurationNanoseconds: minimumWindowDurationNanoseconds
            )
        }

        let expectedPhases = PassiveBluetoothPowerCycleObservationPhase.allCases
        let windows = result.windows
        let snapshots = result.observationSnapshots

        guard windows.count == expectedPhases.count,
              snapshots.count == expectedPhases.count,
              zip(windows, expectedPhases).allSatisfy({ $0.phase == $1 }),
              zip(windows, snapshots).allSatisfy({ $0.windowSequence == $1.windowSequence }),
              strictlyIncreasing(windows.map { $0.windowSequence.rawValue }),
              correlationMatchesSnapshots(result.correlation, snapshots: snapshots) else {
            return Self(
                status: .resultProvenanceMismatch,
                minimumRequiredWindowDurationNanoseconds: minimumWindowDurationNanoseconds
            )
        }

        var durations: [UInt64] = []
        durations.reserveCapacity(windows.count)

        for window in windows {
            guard window.endedAtUptimeNanoseconds >= window.startedAtUptimeNanoseconds else {
                return Self(
                    status: .nonMonotonicWindowClock,
                    minimumRequiredWindowDurationNanoseconds: minimumWindowDurationNanoseconds
                )
            }
            durations.append(
                window.endedAtUptimeNanoseconds - window.startedAtUptimeNanoseconds
            )
        }

        let insufficientPhases = zip(windows, durations).compactMap { window, duration in
            duration < minimumWindowDurationNanoseconds ? window.phase : nil
        }

        return Self(
            status: insufficientPhases.isEmpty ? .sufficient : .insufficientDuration,
            minimumRequiredWindowDurationNanoseconds: minimumWindowDurationNanoseconds,
            observedWindowDurationsNanoseconds: durations,
            insufficientPhases: insufficientPhases
        )
    }

    private static func correlationMatchesSnapshots(
        _ correlation: PassiveBluetoothPowerCycleTargetCorrelationReport,
        snapshots: [PassiveBluetoothCandidateObservationSnapshot]
    ) -> Bool {
        let correlationSequences = [
            correlation.firstOffWindowSequence,
            correlation.firstOnWindowSequence,
            correlation.secondOffWindowSequence,
            correlation.secondOnWindowSequence,
        ]
        let snapshotSequences = snapshots.map(\.windowSequence)
        let snapshotSeriesIdentities = snapshots.map(\.observationSeriesIdentity)

        return correlationSequences == snapshotSequences
            && correlation.observationSeriesIdentities == snapshotSeriesIdentities
    }

    private static func strictlyIncreasing(_ values: [UInt64]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy(<)
    }
}
