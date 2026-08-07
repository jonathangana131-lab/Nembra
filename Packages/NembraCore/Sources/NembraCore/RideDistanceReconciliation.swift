import Foundation

public enum RideDistanceSource: String, Codable, CaseIterable, Hashable, Sendable {
    case scooterOdometer
    case gpsRoute
    case liveSpeedIntegration
}

public enum RideDistanceCoverage: String, Codable, Equatable, Sendable {
    /// The producing subsystem explicitly observed the source across the ride
    /// interval it claims to represent.
    case complete
    /// The source has known missing coverage, such as a route/location gap or a
    /// late ODO baseline.
    case partial
    /// Coverage completeness cannot currently be proven either way.
    case unknown
}

public enum RideDistanceReconciliationError: Error, Equatable, Sendable {
    case invalidEvidence
    case invalidPolicy
}

/// Independent distance evidence retained for one completed ride.
///
/// Values and coverage are intentionally kept separate. `unknown` is not treated
/// as complete merely because no gap flag was observed. Reconciliation never
/// rewrites GPS/integrated distance to look like scooter ODO and never averages
/// sources merely to produce a cleaner-looking number.
public struct RideDistanceEvidence: Equatable, Sendable {
    public let startingOdometerKilometers: Double?
    public let endingOdometerKilometers: Double?
    public let odometerCoverage: RideDistanceCoverage
    public let gpsRouteDistanceMeters: Double?
    public let gpsRouteCoverage: RideDistanceCoverage
    public let liveIntegratedDistanceMeters: Double?
    public let liveIntegratedCoverage: RideDistanceCoverage
    public let transportGapOccurred: Bool

    public init(
        startingOdometerKilometers: Double?,
        endingOdometerKilometers: Double?,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteDistanceMeters: Double?,
        gpsRouteCoverage: RideDistanceCoverage,
        liveIntegratedDistanceMeters: Double?,
        liveIntegratedCoverage: RideDistanceCoverage,
        transportGapOccurred: Bool
    ) throws {
        switch (startingOdometerKilometers, endingOdometerKilometers) {
        case (nil, nil):
            guard odometerCoverage == .unknown else {
                throw RideDistanceReconciliationError.invalidEvidence
            }
        case let (.some(start), .some(end)):
            guard start.isFinite,
                  start >= 0,
                  end.isFinite,
                  end >= start,
                  Self.odometerDeltaMeters(start: start, end: end) != nil else {
                throw RideDistanceReconciliationError.invalidEvidence
            }
        default:
            throw RideDistanceReconciliationError.invalidEvidence
        }

        try Self.validateOptionalDistance(gpsRouteDistanceMeters, coverage: gpsRouteCoverage)
        try Self.validateOptionalDistance(liveIntegratedDistanceMeters, coverage: liveIntegratedCoverage)

        self.startingOdometerKilometers = startingOdometerKilometers
        self.endingOdometerKilometers = endingOdometerKilometers
        self.odometerCoverage = odometerCoverage
        self.gpsRouteDistanceMeters = gpsRouteDistanceMeters
        self.gpsRouteCoverage = gpsRouteCoverage
        self.liveIntegratedDistanceMeters = liveIntegratedDistanceMeters
        self.liveIntegratedCoverage = liveIntegratedCoverage
        self.transportGapOccurred = transportGapOccurred
    }

#if SWIFT_PACKAGE
    /// Package-only bridge for deterministic core fixtures and future trusted
    /// adapters. Matching session UUIDs reject obvious cross-session mixing but
    /// do not prove that two independently constructible records are the exact
    /// same immutable ride evidence, so this bridge must not be public API.
    package init(
        completedRide: CompletedRideEvidence,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceAggregate: RideLiveDistanceAggregate?,
        transportGapOccurred: Bool
    ) throws {
        if let liveDistanceAggregate,
           liveDistanceAggregate.rideSessionID != completedRide.sessionID {
            throw RideDistanceReconciliationError.invalidEvidence
        }

        try self.init(
            startingOdometerKilometers: completedRide.startingOdometerKilometers,
            endingOdometerKilometers: completedRide.endingOdometerKilometers,
            odometerCoverage: odometerCoverage,
            gpsRouteDistanceMeters: completedRide.qualityScreenedGPSDistanceMeters,
            gpsRouteCoverage: gpsRouteCoverage,
            liveIntegratedDistanceMeters: liveDistanceAggregate?.distanceMeters,
            liveIntegratedCoverage: liveDistanceAggregate?.coverage ?? .unknown,
            transportGapOccurred: transportGapOccurred
        )
    }
#else
    /// `RideDistanceReconciliation.swift` is also compiled directly into the
    /// app target. There is no mechanically bound production adapter yet, so
    /// keep this convenience composition file-owned rather than exposing a
    /// same-module path that can pair independently constructed ride records.
    fileprivate init(
        completedRide: CompletedRideEvidence,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceAggregate: RideLiveDistanceAggregate?,
        transportGapOccurred: Bool
    ) throws {
        if let liveDistanceAggregate,
           liveDistanceAggregate.rideSessionID != completedRide.sessionID {
            throw RideDistanceReconciliationError.invalidEvidence
        }

        try self.init(
            startingOdometerKilometers: completedRide.startingOdometerKilometers,
            endingOdometerKilometers: completedRide.endingOdometerKilometers,
            odometerCoverage: odometerCoverage,
            gpsRouteDistanceMeters: completedRide.qualityScreenedGPSDistanceMeters,
            gpsRouteCoverage: gpsRouteCoverage,
            liveIntegratedDistanceMeters: liveDistanceAggregate?.distanceMeters,
            liveIntegratedCoverage: liveDistanceAggregate?.coverage ?? .unknown,
            transportGapOccurred: transportGapOccurred
        )
    }
#endif

    public var scooterOdometerDeltaMeters: Double? {
        guard let start = startingOdometerKilometers,
              let end = endingOdometerKilometers else {
            return nil
        }
        return Self.odometerDeltaMeters(start: start, end: end)
    }

    public func distance(for source: RideDistanceSource) -> Double? {
        switch source {
        case .scooterOdometer:
            scooterOdometerDeltaMeters
        case .gpsRoute:
            gpsRouteDistanceMeters
        case .liveSpeedIntegration:
            liveIntegratedDistanceMeters
        }
    }

    public func coverage(for source: RideDistanceSource) -> RideDistanceCoverage {
        switch source {
        case .scooterOdometer:
            odometerCoverage
        case .gpsRoute:
            gpsRouteCoverage
        case .liveSpeedIntegration:
            liveIntegratedCoverage
        }
    }

    private static func odometerDeltaMeters(start: Double, end: Double) -> Double? {
        let meters = (end - start) * 1_000
        guard meters.isFinite, meters >= 0 else { return nil }
        return meters
    }

    private static func validateOptionalDistance(
        _ distance: Double?,
        coverage: RideDistanceCoverage
    ) throws {
        guard let distance else {
            guard coverage == .unknown else {
                throw RideDistanceReconciliationError.invalidEvidence
            }
            return
        }
        guard distance.isFinite, distance >= 0 else {
            throw RideDistanceReconciliationError.invalidEvidence
        }
    }
}

/// Reconciliation behavior is injected rather than hard-coded as physical
/// scooter truth. Hardware/field validation will decide the production source
/// order and tolerance values. Every known source must be ranked explicitly so
/// evidence is never silently ignored by an incomplete priority list.
public struct RideDistanceReconciliationPolicy: Equatable, Sendable {
    public let sourcePriority: [RideDistanceSource]
    public let absoluteAgreementToleranceMeters: Double
    public let relativeAgreementTolerance: Double
    public let minimumRelativeComparisonDistanceMeters: Double
    public let allowOdometerToRecoverKnownCoverageGaps: Bool

    public init(
        sourcePriority: [RideDistanceSource],
        absoluteAgreementToleranceMeters: Double,
        relativeAgreementTolerance: Double,
        minimumRelativeComparisonDistanceMeters: Double,
        allowOdometerToRecoverKnownCoverageGaps: Bool
    ) throws {
        guard sourcePriority.count == RideDistanceSource.allCases.count,
              Set(sourcePriority) == Set(RideDistanceSource.allCases),
              absoluteAgreementToleranceMeters.isFinite,
              absoluteAgreementToleranceMeters >= 0,
              relativeAgreementTolerance.isFinite,
              (0...1).contains(relativeAgreementTolerance),
              minimumRelativeComparisonDistanceMeters.isFinite,
              minimumRelativeComparisonDistanceMeters > 0 else {
            throw RideDistanceReconciliationError.invalidPolicy
        }

        self.sourcePriority = sourcePriority
        self.absoluteAgreementToleranceMeters = absoluteAgreementToleranceMeters
        self.relativeAgreementTolerance = relativeAgreementTolerance
        self.minimumRelativeComparisonDistanceMeters = minimumRelativeComparisonDistanceMeters
        self.allowOdometerToRecoverKnownCoverageGaps = allowOdometerToRecoverKnownCoverageGaps
    }
}

public enum RideDistanceComparisonDisposition: String, Equatable, Sendable {
    case agrees
    case explainedCoverageGap
    case conflicts
}

public struct RideDistanceComparison: Equatable, Sendable {
    public let source: RideDistanceSource
    public let distanceMeters: Double
    public let coverage: RideDistanceCoverage
    public let signedDifferenceFromFinalMeters: Double
    public let absoluteDifferenceMeters: Double
    public let relativeDifference: Double
    public let disposition: RideDistanceComparisonDisposition
    public let recoveredGapMeters: Double?
}

public enum RideDistanceConfidence: String, Equatable, Sendable {
    case unavailable
    case singleSource
    case corroborated
    case recoverySupported
    case conflicting
}

public enum RideDistanceReconciliationStatus: String, Equatable, Sendable {
    case insufficientEvidence
    /// The selected final distance source itself has complete ride coverage.
    /// Corroboration can raise confidence but cannot repair another source's
    /// partial or unknown coverage.
    case complete
    case coverageIncomplete
    case vehicleDistanceRecoveredAcrossCoverageGap
    case disagreementRequiresReview
}

public struct ReconciledRideDistance: Equatable, Sendable {
    public let finalDistanceMeters: Double?
    public let finalSource: RideDistanceSource?
    public let finalSourceCoverage: RideDistanceCoverage?
    public let confidence: RideDistanceConfidence
    public let status: RideDistanceReconciliationStatus
    public let comparisons: [RideDistanceComparison]
    /// Distance proven by a complete selected scooter ODO beyond an explicitly
    /// partial lower-coverage source. This recovers mileage only; it never
    /// reconstructs missing GPS path geometry.
    public let recoveredCoverageGapMeters: Double
    public let transportGapOccurred: Bool
}

public enum RideDistanceReconciler {
    public static func reconcile(
        evidence: RideDistanceEvidence,
        policy: RideDistanceReconciliationPolicy
    ) -> ReconciledRideDistance {
        guard let finalSource = policy.sourcePriority.first(where: { evidence.distance(for: $0) != nil }),
              let finalDistance = evidence.distance(for: finalSource) else {
            return ReconciledRideDistance(
                finalDistanceMeters: nil,
                finalSource: nil,
                finalSourceCoverage: nil,
                confidence: .unavailable,
                status: .insufficientEvidence,
                comparisons: [],
                recoveredCoverageGapMeters: 0,
                transportGapOccurred: evidence.transportGapOccurred
            )
        }

        let finalCoverage = evidence.coverage(for: finalSource)
        var comparisons: [RideDistanceComparison] = []
        var recoveredCoverageGapMeters = 0.0
        var hasConflict = false
        var agreementCount = 0
        var recoveryCount = 0

        for source in RideDistanceSource.allCases where source != finalSource {
            guard let distance = evidence.distance(for: source) else { continue }

            let sourceCoverage = evidence.coverage(for: source)
            let signedDifference = distance - finalDistance
            let absoluteDifference = abs(signedDifference)
            let denominator = max(
                max(finalDistance, distance),
                policy.minimumRelativeComparisonDistanceMeters
            )
            let relativeDifference = absoluteDifference / denominator
            let agrees = absoluteDifference <= policy.absoluteAgreementToleranceMeters
                || relativeDifference <= policy.relativeAgreementTolerance

            let disposition: RideDistanceComparisonDisposition
            let recoveredGap: Double?
            if agrees {
                disposition = .agrees
                recoveredGap = nil
                agreementCount += 1
            } else if policy.allowOdometerToRecoverKnownCoverageGaps,
                      finalSource == .scooterOdometer,
                      finalCoverage == .complete,
                      sourceCoverage == .partial,
                      distance < finalDistance {
                let gap = finalDistance - distance
                disposition = .explainedCoverageGap
                recoveredGap = gap
                recoveredCoverageGapMeters = max(recoveredCoverageGapMeters, gap)
                recoveryCount += 1
            } else {
                disposition = .conflicts
                recoveredGap = nil
                hasConflict = true
            }

            comparisons.append(
                RideDistanceComparison(
                    source: source,
                    distanceMeters: distance,
                    coverage: sourceCoverage,
                    signedDifferenceFromFinalMeters: signedDifference,
                    absoluteDifferenceMeters: absoluteDifference,
                    relativeDifference: relativeDifference,
                    disposition: disposition,
                    recoveredGapMeters: recoveredGap
                )
            )
        }

        let confidence: RideDistanceConfidence
        let status: RideDistanceReconciliationStatus
        if hasConflict {
            confidence = .conflicting
            status = .disagreementRequiresReview
        } else if recoveryCount > 0 {
            confidence = agreementCount > 0 ? .corroborated : .recoverySupported
            status = .vehicleDistanceRecoveredAcrossCoverageGap
        } else if agreementCount > 0 {
            confidence = .corroborated
            status = finalCoverage == .complete ? .complete : .coverageIncomplete
        } else {
            confidence = .singleSource
            status = finalCoverage == .complete ? .complete : .coverageIncomplete
        }

        return ReconciledRideDistance(
            finalDistanceMeters: finalDistance,
            finalSource: finalSource,
            finalSourceCoverage: finalCoverage,
            confidence: confidence,
            status: status,
            comparisons: comparisons,
            recoveredCoverageGapMeters: recoveredCoverageGapMeters,
            transportGapOccurred: evidence.transportGapOccurred
        )
    }
}
