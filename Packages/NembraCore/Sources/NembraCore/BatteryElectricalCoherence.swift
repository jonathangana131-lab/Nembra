/// Injected temporal-coherence policy for a future verified voltage/current pair.
///
/// There is deliberately no ES80 default. Physical capture must establish whether the
/// two fields are emitted synchronously enough to justify any nonzero pairing window.
public struct BatteryElectricalCoherencePolicy: Equatable, Sendable {
    public let maximumVoltageCurrentSkewNanoseconds: UInt64

    public init(maximumVoltageCurrentSkewNanoseconds: UInt64) {
        self.maximumVoltageCurrentSkewNanoseconds = maximumVoltageCurrentSkewNanoseconds
    }
}

/// Availability/coherence of verified-live voltage and current observations.
///
/// This type intentionally does not calculate watts, energy, Wh, or Wh/mi.
public enum BatteryVerifiedElectricalPairState: Equatable, Sendable {
    case unavailable
    case voltageOnly(BatteryEvidenceObservation)
    case currentOnly(BatteryEvidenceObservation)
    case coherent(
        voltage: BatteryEvidenceObservation,
        current: BatteryEvidenceObservation,
        skewNanoseconds: UInt64
    )
    case incoherent(
        voltage: BatteryEvidenceObservation,
        current: BatteryEvidenceObservation,
        skewNanoseconds: UInt64
    )

    public var isCoherentPair: Bool {
        if case .coherent = self { return true }
        return false
    }
}

/// Pure evaluator that pairs only already-verified-live voltage/current evidence.
///
/// Stale, freshness-unclassified, stock-app, Simulator, derived, and presentation-only
/// observations are excluded upstream by `verifiedLiveObservation(for:)`.
public enum BatteryVerifiedElectricalPairEvaluator {
    public static func evaluate(
        _ liveTruth: BatteryEvidenceLiveTruthSnapshot,
        policy: BatteryElectricalCoherencePolicy
    ) -> BatteryVerifiedElectricalPairState {
        let voltage = liveTruth.verifiedLiveObservation(for: .voltageVolts)
        let current = liveTruth.verifiedLiveObservation(for: .currentAmps)

        switch (voltage, current) {
        case (nil, nil):
            return .unavailable
        case let (voltage?, nil):
            return .voltageOnly(voltage)
        case let (nil, current?):
            return .currentOnly(current)
        case let (voltage?, current?):
            let voltageUptime = voltage.receivedAtUptimeNanoseconds
            let currentUptime = current.receivedAtUptimeNanoseconds
            let skew: UInt64
            if voltageUptime >= currentUptime {
                skew = voltageUptime - currentUptime
            } else {
                skew = currentUptime - voltageUptime
            }

            if skew <= policy.maximumVoltageCurrentSkewNanoseconds {
                return .coherent(
                    voltage: voltage,
                    current: current,
                    skewNanoseconds: skew
                )
            }

            return .incoherent(
                voltage: voltage,
                current: current,
                skewNanoseconds: skew
            )
        }
    }
}
