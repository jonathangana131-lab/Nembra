/// Product-facing truth state for one battery field after freshness is evaluated.
///
/// A value becomes `verifiedLive` only when it is both fresh under an injected policy
/// and already classified as a physically verified vehicle measurement. Freshness alone
/// can never promote stock-app, Simulator, derived, or presentation-only evidence.
public enum BatteryEvidenceLiveTruthState: Equatable, Sendable {
    case unavailable
    case freshnessUnclassified(BatteryEvidenceObservation)
    case stale(BatteryEvidenceObservation, ageNanoseconds: UInt64)
    case freshNonAuthoritative(BatteryEvidenceObservation, ageNanoseconds: UInt64)
    case verifiedLive(BatteryEvidenceObservation, ageNanoseconds: UInt64)

    public var observation: BatteryEvidenceObservation? {
        switch self {
        case .unavailable:
            nil
        case let .freshnessUnclassified(observation),
             let .stale(observation, _),
             let .freshNonAuthoritative(observation, _),
             let .verifiedLive(observation, _):
            observation
        }
    }

    public var verifiedLiveObservation: BatteryEvidenceObservation? {
        if case let .verifiedLive(observation, _) = self {
            return observation
        }
        return nil
    }

    public var isVerifiedLive: Bool {
        verifiedLiveObservation != nil
    }
}

fileprivate enum BatteryEvidenceLiveTruthConstructionBoundary {
    case resolvedSnapshot
}

public struct BatteryEvidenceLiveTruthSnapshot: Equatable, Sendable {
    public let stateByField: [BatteryEvidenceField: BatteryEvidenceLiveTruthState]

    /// Production aggregate construction is file-scoped. If this package-domain source is
    /// manually compiled into the Nembra app target, unrelated app code must not gain the
    /// ability to hand-label arbitrary fields `.verifiedLive` merely through same-module
    /// `internal` access.
    fileprivate init(
        stateByField: [BatteryEvidenceField: BatteryEvidenceLiveTruthState],
        constructionBoundary: BatteryEvidenceLiveTruthConstructionBoundary
    ) {
        _ = constructionBoundary
        self.stateByField = stateByField
    }

#if SWIFT_PACKAGE
    /// Package-only fixture seam for NembraCore tests/dependent package-domain tests.
    /// This initializer is absent from direct app-source compilation.
    init(stateByField: [BatteryEvidenceField: BatteryEvidenceLiveTruthState]) {
        self.init(
            stateByField: stateByField,
            constructionBoundary: .resolvedSnapshot
        )
    }
#endif

    public subscript(field: BatteryEvidenceField) -> BatteryEvidenceLiveTruthState {
        stateByField[field] ?? .unavailable
    }

    public func verifiedLiveObservation(for field: BatteryEvidenceField) -> BatteryEvidenceObservation? {
        self[field].verifiedLiveObservation
    }
}

/// Pure projection from validated freshness/availability into product live-truth state.
public enum BatteryEvidenceLiveTruthResolver {
    /// File-scoped field projection. `BatteryEvidenceFieldAvailability` is a public
    /// descriptive enum whose cases can be constructed by callers; direct app-source code
    /// must not be able to forge `.fresh` and feed it into a same-module resolver that
    /// returns `verifiedLive` without the aggregate availability evaluator.
    fileprivate static func resolveField(
        _ availability: BatteryEvidenceFieldAvailability
    ) -> BatteryEvidenceLiveTruthState {
        switch availability {
        case .unavailable:
            .unavailable

        case let .unclassified(observation):
            .freshnessUnclassified(observation)

        case let .stale(observation, ageNanoseconds):
            .stale(observation, ageNanoseconds: ageNanoseconds)

        case let .fresh(observation, ageNanoseconds):
            if observation.isAuthoritativeVehicleMeasurement {
                .verifiedLive(observation, ageNanoseconds: ageNanoseconds)
            } else {
                .freshNonAuthoritative(observation, ageNanoseconds: ageNanoseconds)
            }
        }
    }

#if SWIFT_PACKAGE
    /// Package-only field-level fixture seam for focused NembraCore tests. The production
    /// app-source composition does not receive this overload.
    static func resolve(
        _ availability: BatteryEvidenceFieldAvailability
    ) -> BatteryEvidenceLiveTruthState {
        resolveField(availability)
    }
#endif

    /// Production live-truth construction accepts only an aggregate produced by the
    /// availability pipeline. The aggregate's raw initializer is file-scoped in direct app
    /// composition, so this public method cannot be fed caller-manufactured freshness state.
    public static func resolve(
        _ availabilitySnapshot: BatteryEvidenceAvailabilitySnapshot
    ) -> BatteryEvidenceLiveTruthSnapshot {
        var result: [BatteryEvidenceField: BatteryEvidenceLiveTruthState] = [:]
        result.reserveCapacity(BatteryEvidenceField.allCases.count)

        for field in BatteryEvidenceField.allCases {
            result[field] = resolveField(availabilitySnapshot[field])
        }

        return BatteryEvidenceLiveTruthSnapshot(
            stateByField: result,
            constructionBoundary: .resolvedSnapshot
        )
    }
}
