public enum BatteryEvidenceFreshnessPolicyError: Error, Equatable, Sendable {
    case invalidMaximumAge
}

/// Injected freshness limits for normalized battery fields.
///
/// There are deliberately no ES80 defaults here. Real field cadence must be measured
/// before production chooses a maximum age. A missing field policy means Nembra can
/// preserve the observation but cannot truthfully classify it as fresh or stale.
public struct BatteryEvidenceFreshnessPolicy: Equatable, Sendable {
    public let maximumAgeNanosecondsByField: [BatteryEvidenceField: UInt64]

    public init(maximumAgeNanosecondsByField: [BatteryEvidenceField: UInt64]) throws {
        guard maximumAgeNanosecondsByField.values.allSatisfy({ $0 > 0 }) else {
            throw BatteryEvidenceFreshnessPolicyError.invalidMaximumAge
        }
        self.maximumAgeNanosecondsByField = maximumAgeNanosecondsByField
    }

    public func maximumAgeNanoseconds(for field: BatteryEvidenceField) -> UInt64? {
        maximumAgeNanosecondsByField[field]
    }
}

public enum BatteryEvidenceAvailabilityError: Error, Equatable, Sendable {
    case observationFromFutureUptime
}

/// Current-process availability of one field. Freshness never changes evidence truth role.
public enum BatteryEvidenceFieldAvailability: Equatable, Sendable {
    case unavailable
    case unclassified(BatteryEvidenceObservation)
    case fresh(BatteryEvidenceObservation, ageNanoseconds: UInt64)
    case stale(BatteryEvidenceObservation, ageNanoseconds: UInt64)

    public var observation: BatteryEvidenceObservation? {
        switch self {
        case .unavailable:
            nil
        case let .unclassified(observation),
             let .fresh(observation, _),
             let .stale(observation, _):
            observation
        }
    }

    public var isFresh: Bool {
        if case .fresh = self { return true }
        return false
    }
}

/// Availability view over every battery semantic field for one validated current segment.
public struct BatteryEvidenceAvailabilitySnapshot: Equatable, Sendable {
    public let availabilityByField: [BatteryEvidenceField: BatteryEvidenceFieldAvailability]

    /// Raw snapshot construction stays inside NembraCore. Production consumers obtain
    /// this aggregate only from `BatteryEvidenceAvailabilityEvaluator.snapshot(...)`,
    /// preventing arbitrary `.fresh` labels from bypassing uptime/policy evaluation.
    init(availabilityByField: [BatteryEvidenceField: BatteryEvidenceFieldAvailability]) {
        self.availabilityByField = availabilityByField
    }

    public subscript(field: BatteryEvidenceField) -> BatteryEvidenceFieldAvailability {
        availabilityByField[field] ?? .unavailable
    }
}

/// Pure uptime-based availability classifier.
///
/// Wall-clock dates are intentionally ignored. This layer does not infer transport gaps,
/// erase stale evidence, promote truth roles, or select production thresholds.
public enum BatteryEvidenceAvailabilityEvaluator {
    /// Field-level classification remains public because it performs the real injected
    /// uptime-policy calculation itself; callers do not provide a preclassified state.
    public static func availability(
        for observation: BatteryEvidenceObservation?,
        atUptimeNanoseconds nowUptimeNanoseconds: UInt64,
        policy: BatteryEvidenceFreshnessPolicy
    ) throws -> BatteryEvidenceFieldAvailability {
        guard let observation else { return .unavailable }
        guard observation.receivedAtUptimeNanoseconds <= nowUptimeNanoseconds else {
            throw BatteryEvidenceAvailabilityError.observationFromFutureUptime
        }

        guard let maximumAgeNanoseconds = policy.maximumAgeNanoseconds(for: observation.value.field) else {
            return .unclassified(observation)
        }

        let age = nowUptimeNanoseconds - observation.receivedAtUptimeNanoseconds
        if age <= maximumAgeNanoseconds {
            return .fresh(observation, ageNanoseconds: age)
        }
        return .stale(observation, ageNanoseconds: age)
    }

    public static func snapshot(
        for currentSegment: BatteryEvidenceCurrentSegmentSnapshot,
        atUptimeNanoseconds nowUptimeNanoseconds: UInt64,
        policy: BatteryEvidenceFreshnessPolicy
    ) throws -> BatteryEvidenceAvailabilitySnapshot {
        var result: [BatteryEvidenceField: BatteryEvidenceFieldAvailability] = [:]
        result.reserveCapacity(BatteryEvidenceField.allCases.count)

        for field in BatteryEvidenceField.allCases {
            result[field] = try availability(
                for: currentSegment[field],
                atUptimeNanoseconds: nowUptimeNanoseconds,
                policy: policy
            )
        }

        return BatteryEvidenceAvailabilitySnapshot(availabilityByField: result)
    }
}
