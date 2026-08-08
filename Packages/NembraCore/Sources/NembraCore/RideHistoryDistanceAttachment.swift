import Foundation

public enum RideHistoryDistanceCommitResult: Equatable, Sendable {
    case inserted
    case alreadyPresent
}

public enum RideHistoryDistanceStoreError: Error, Equatable, Sendable {
    case sessionConflict(UUID)
}

public enum RideHistoryDistanceAttachmentError: Error, Equatable, Sendable {
    case invalidPolicy
    case invalidLiveDistanceEvidence
    case completedRideMismatch(UUID)
    case missingCompletedRide(UUID)
    case durableVerificationFailed(UUID)
}

/// Durable copy of the exact reconciliation policy used for one completed-ride
/// distance attachment.
///
/// Persisting the inputs rather than a caller-supplied "final distance" lets a
/// later read re-run `RideDistanceReconciler` under the exact policy that owned
/// the original decision. Decoding always crosses the production policy
/// initializer again, so malformed priorities/tolerances fail closed.
public struct RideHistoryDistancePolicySnapshot: Codable, Equatable, Sendable {
    public let sourcePriority: [RideDistanceSource]
    public let absoluteAgreementToleranceMeters: Double
    public let relativeAgreementTolerance: Double
    public let minimumRelativeComparisonDistanceMeters: Double
    public let allowOdometerToRecoverKnownCoverageGaps: Bool

    public init(policy: RideDistanceReconciliationPolicy) {
        sourcePriority = policy.sourcePriority
        absoluteAgreementToleranceMeters = policy.absoluteAgreementToleranceMeters
        relativeAgreementTolerance = policy.relativeAgreementTolerance
        minimumRelativeComparisonDistanceMeters = policy.minimumRelativeComparisonDistanceMeters
        allowOdometerToRecoverKnownCoverageGaps = policy.allowOdometerToRecoverKnownCoverageGaps
    }

    public func policy() throws -> RideDistanceReconciliationPolicy {
        do {
            return try RideDistanceReconciliationPolicy(
                sourcePriority: sourcePriority,
                absoluteAgreementToleranceMeters: absoluteAgreementToleranceMeters,
                relativeAgreementTolerance: relativeAgreementTolerance,
                minimumRelativeComparisonDistanceMeters: minimumRelativeComparisonDistanceMeters,
                allowOdometerToRecoverKnownCoverageGaps: allowOdometerToRecoverKnownCoverageGaps
            )
        } catch {
            throw RideHistoryDistanceAttachmentError.invalidPolicy
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePriority
        case absoluteAgreementToleranceMeters
        case relativeAgreementTolerance
        case minimumRelativeComparisonDistanceMeters
        case allowOdometerToRecoverKnownCoverageGaps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePriority = try container.decode([RideDistanceSource].self, forKey: .sourcePriority)
        absoluteAgreementToleranceMeters = try container.decode(
            Double.self,
            forKey: .absoluteAgreementToleranceMeters
        )
        relativeAgreementTolerance = try container.decode(
            Double.self,
            forKey: .relativeAgreementTolerance
        )
        minimumRelativeComparisonDistanceMeters = try container.decode(
            Double.self,
            forKey: .minimumRelativeComparisonDistanceMeters
        )
        allowOdometerToRecoverKnownCoverageGaps = try container.decode(
            Bool.self,
            forKey: .allowOdometerToRecoverKnownCoverageGaps
        )

        do {
            _ = try policy()
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Ride-history distance policy is structurally invalid."
                )
            )
        }
    }
}

/// Durable measured-speed segments needed to reproduce one ride's live-distance
/// aggregate after relaunch.
///
/// The aggregate itself is intentionally sealed/non-Codable in NembraCore. This
/// record therefore persists its already-validated segment evidence and re-runs
/// the authoritative aggregator on every read. Empty evidence is represented by
/// the absence of this bundle, never by a fake zero-distance aggregate.
public struct RideHistoryLiveDistanceEvidence: Codable, Equatable, Sendable {
    public let source: SpeedTelemetrySource
    public let method: LiveDistanceIntegrationMethod
    public let segmentRecords: [RideLiveDistanceSegmentEvidence]

#if SWIFT_PACKAGE
    package init(
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        segmentRecords: [RideLiveDistanceSegmentEvidence]
    ) throws {
        try self.init(
            validatingSource: source,
            method: method,
            segmentRecords: segmentRecords
        )
    }
#else
    fileprivate init(
        source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        segmentRecords: [RideLiveDistanceSegmentEvidence]
    ) throws {
        try self.init(
            validatingSource: source,
            method: method,
            segmentRecords: segmentRecords
        )
    }
#endif

    private init(
        validatingSource source: SpeedTelemetrySource,
        method: LiveDistanceIntegrationMethod,
        segmentRecords: [RideLiveDistanceSegmentEvidence]
    ) throws {
        guard source != .motionAssist, !segmentRecords.isEmpty else {
            throw RideHistoryDistanceAttachmentError.invalidLiveDistanceEvidence
        }
        self.source = source
        self.method = method
        self.segmentRecords = segmentRecords
    }

    func aggregate(rideSessionID: UUID) throws -> RideLiveDistanceAggregate {
        do {
            return try RideLiveDistanceAggregator.aggregate(
                rideSessionID: rideSessionID,
                source: source,
                method: method,
                records: segmentRecords
            )
        } catch {
            throw RideHistoryDistanceAttachmentError.invalidLiveDistanceEvidence
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case method
        case segmentRecords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                validatingSource: container.decode(SpeedTelemetrySource.self, forKey: .source),
                method: container.decode(LiveDistanceIntegrationMethod.self, forKey: .method),
                segmentRecords: container.decode(
                    [RideLiveDistanceSegmentEvidence].self,
                    forKey: .segmentRecords
                )
            )
        } catch let error as RideHistoryDistanceAttachmentError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Ride-history live-distance evidence is invalid: \(error)."
                )
            )
        }
    }
}

/// Immutable supplemental distance-reconciliation inputs for one completed
/// history entry.
///
/// This deliberately stores the *exact completed-ride evidence* it was bound to,
/// source coverage, durable live-distance segments, transport-gap fact, and the
/// exact reconciliation policy. It does not persist a free-form final mileage.
/// A trusted read must first prove that `completedRideEvidence` still equals the
/// base `RideHistoryRecord`, then deterministically rebuild and reconcile the
/// distance evidence.
public struct RideHistoryDistanceRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let completedRideEvidence: CompletedRideEvidence
    public let odometerCoverage: RideDistanceCoverage
    public let gpsRouteCoverage: RideDistanceCoverage
    public let liveDistanceEvidence: RideHistoryLiveDistanceEvidence?
    public let transportGapOccurred: Bool
    public let reconciliationPolicy: RideHistoryDistancePolicySnapshot

    public var sessionID: UUID { completedRideEvidence.sessionID }

#if SWIFT_PACKAGE
    package init(
        historyRecord: RideHistoryRecord,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceEvidence: RideHistoryLiveDistanceEvidence?,
        transportGapOccurred: Bool,
        reconciliationPolicy: RideDistanceReconciliationPolicy
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            completedRideEvidence: historyRecord.evidence,
            odometerCoverage: odometerCoverage,
            gpsRouteCoverage: gpsRouteCoverage,
            liveDistanceEvidence: liveDistanceEvidence,
            transportGapOccurred: transportGapOccurred,
            reconciliationPolicy: RideHistoryDistancePolicySnapshot(policy: reconciliationPolicy)
        )
    }
#else
    fileprivate init(
        historyRecord: RideHistoryRecord,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceEvidence: RideHistoryLiveDistanceEvidence?,
        transportGapOccurred: Bool,
        reconciliationPolicy: RideDistanceReconciliationPolicy
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            completedRideEvidence: historyRecord.evidence,
            odometerCoverage: odometerCoverage,
            gpsRouteCoverage: gpsRouteCoverage,
            liveDistanceEvidence: liveDistanceEvidence,
            transportGapOccurred: transportGapOccurred,
            reconciliationPolicy: RideHistoryDistancePolicySnapshot(policy: reconciliationPolicy)
        )
    }
#endif

    private init(
        schemaVersion: Int,
        completedRideEvidence: CompletedRideEvidence,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceEvidence: RideHistoryLiveDistanceEvidence?,
        transportGapOccurred: Bool,
        reconciliationPolicy: RideHistoryDistancePolicySnapshot
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RideHistoryDistanceAttachmentError.invalidPolicy
        }

        self.schemaVersion = schemaVersion
        self.completedRideEvidence = completedRideEvidence
        self.odometerCoverage = odometerCoverage
        self.gpsRouteCoverage = gpsRouteCoverage
        self.liveDistanceEvidence = liveDistanceEvidence
        self.transportGapOccurred = transportGapOccurred
        self.reconciliationPolicy = reconciliationPolicy

        _ = try reconciledDistance(validatingAgainst: completedRideEvidence)
    }

    /// Rebuilds source evidence directly from the exact bound completed ride and
    /// durable live-distance segments. No UUID-only convenience bridge and no
    /// persisted final-distance output participates in this calculation.
    fileprivate func reconciledDistance(
        validatingAgainst completedRide: CompletedRideEvidence
    ) throws -> ReconciledRideDistance {
        guard completedRide == completedRideEvidence else {
            throw RideHistoryDistanceAttachmentError.completedRideMismatch(
                completedRideEvidence.sessionID
            )
        }

        let liveAggregate = try liveDistanceEvidence?.aggregate(
            rideSessionID: completedRide.sessionID
        )

        let evidence: RideDistanceEvidence
        do {
            evidence = try RideDistanceEvidence(
                startingOdometerKilometers: completedRide.startingOdometerKilometers,
                endingOdometerKilometers: completedRide.endingOdometerKilometers,
                odometerCoverage: odometerCoverage,
                gpsRouteDistanceMeters: completedRide.qualityScreenedGPSDistanceMeters,
                gpsRouteCoverage: gpsRouteCoverage,
                liveIntegratedDistanceMeters: liveAggregate?.distanceMeters,
                liveIntegratedCoverage: liveAggregate?.coverage ?? .unknown,
                transportGapOccurred: transportGapOccurred
            )
        } catch {
            throw RideHistoryDistanceAttachmentError.completedRideMismatch(
                completedRide.sessionID
            )
        }

        let policy = try reconciliationPolicy.policy()
        return RideDistanceReconciler.reconcile(evidence: evidence, policy: policy)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case completedRideEvidence
        case odometerCoverage
        case gpsRouteCoverage
        case liveDistanceEvidence
        case transportGapOccurred
        case reconciliationPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
                completedRideEvidence: container.decode(
                    CompletedRideEvidence.self,
                    forKey: .completedRideEvidence
                ),
                odometerCoverage: container.decode(RideDistanceCoverage.self, forKey: .odometerCoverage),
                gpsRouteCoverage: container.decode(RideDistanceCoverage.self, forKey: .gpsRouteCoverage),
                liveDistanceEvidence: container.decodeIfPresent(
                    RideHistoryLiveDistanceEvidence.self,
                    forKey: .liveDistanceEvidence
                ),
                transportGapOccurred: container.decode(Bool.self, forKey: .transportGapOccurred),
                reconciliationPolicy: container.decode(
                    RideHistoryDistancePolicySnapshot.self,
                    forKey: .reconciliationPolicy
                )
            )
        } catch let error as RideHistoryDistanceAttachmentError {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Ride-history distance attachment is invalid: \(error)."
                )
            )
        }
    }
}

public protocol RideHistoryDistanceStore: Sendable {
    func commit(_ record: RideHistoryDistanceRecord) async throws -> RideHistoryDistanceCommitResult
    func record(sessionID: UUID) async throws -> RideHistoryDistanceRecord?
}

/// Freshly revalidated join between immutable base history and its distance
/// attachment. This runtime capability is intentionally not Codable; persistence
/// remains the two records plus their exact evidence equality check.
public struct RideHistoryDistanceJoinedRecord: Equatable, Sendable {
    public let historyRecord: RideHistoryRecord
    public let distanceRecord: RideHistoryDistanceRecord
    public let reconciledDistance: ReconciledRideDistance

#if SWIFT_PACKAGE
    package init(
        historyRecord: RideHistoryRecord,
        distanceRecord: RideHistoryDistanceRecord
    ) throws {
        let reconciledDistance = try distanceRecord.reconciledDistance(
            validatingAgainst: historyRecord.evidence
        )
        self.historyRecord = historyRecord
        self.distanceRecord = distanceRecord
        self.reconciledDistance = reconciledDistance
    }
#else
    fileprivate init(
        historyRecord: RideHistoryRecord,
        distanceRecord: RideHistoryDistanceRecord
    ) throws {
        let reconciledDistance = try distanceRecord.reconciledDistance(
            validatingAgainst: historyRecord.evidence
        )
        self.historyRecord = historyRecord
        self.distanceRecord = distanceRecord
        self.reconciledDistance = reconciledDistance
    }
#endif

    public var sessionID: UUID { historyRecord.sessionID }
}

/// Idempotently attaches deterministic distance-reconciliation inputs to an
/// already-durable completed ride, then verifies exact durable read-back.
public actor RideHistoryDistanceCommitCoordinator {
    private let historyStore: any RideHistoryStore
    private let distanceStore: any RideHistoryDistanceStore

    public init(
        historyStore: any RideHistoryStore,
        distanceStore: any RideHistoryDistanceStore
    ) {
        self.historyStore = historyStore
        self.distanceStore = distanceStore
    }

    @discardableResult
    public func commit(
        _ record: RideHistoryDistanceRecord
    ) async throws -> RideHistoryDistanceCommitResult {
        guard let historyRecord = try await historyStore.record(sessionID: record.sessionID) else {
            throw RideHistoryDistanceAttachmentError.missingCompletedRide(record.sessionID)
        }

        _ = try record.reconciledDistance(validatingAgainst: historyRecord.evidence)

        let result = try await distanceStore.commit(record)
        guard try await distanceStore.record(sessionID: record.sessionID) == record else {
            throw RideHistoryDistanceAttachmentError.durableVerificationFailed(record.sessionID)
        }
        return result
    }

    /// A base history row with no distance attachment is ordinary unavailability.
    /// An orphaned attachment or a mismatched immutable base fails closed.
    public func joinedRecord(
        sessionID: UUID
    ) async throws -> RideHistoryDistanceJoinedRecord? {
        let historyRecord = try await historyStore.record(sessionID: sessionID)
        let distanceRecord = try await distanceStore.record(sessionID: sessionID)

        switch (historyRecord, distanceRecord) {
        case (nil, nil), (.some, nil):
            return nil
        case (nil, .some):
            throw RideHistoryDistanceAttachmentError.missingCompletedRide(sessionID)
        case let (.some(historyRecord), .some(distanceRecord)):
            return try RideHistoryDistanceJoinedRecord(
                historyRecord: historyRecord,
                distanceRecord: distanceRecord
            )
        }
    }
}

public extension RideStatisticsRide {
    /// Production-safe statistics bridge from a revalidated immutable-history
    /// distance join. Unlike the package fixture bridge, callers cannot pair an
    /// arbitrary completed ride with an unrelated `ReconciledRideDistance`.
    init(
        historyDistanceRecord record: RideHistoryDistanceJoinedRecord,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        let reconciledDistance = record.reconciledDistance
        let disposition: RideStatisticsDistanceDisposition
        switch reconciledDistance.status {
        case .complete, .vehicleDistanceRecoveredAcrossCoverageGap:
            switch reconciledDistance.confidence {
            case .unavailable:
                disposition = .excludedInsufficientEvidence
            case .conflicting:
                disposition = .excludedConflict
            case .singleSource, .corroborated, .recoverySupported:
                disposition = reconciledDistance.finalDistanceMeters == nil
                    ? .excludedInsufficientEvidence
                    : .included
            }
        case .coverageIncomplete:
            disposition = .excludedIncompleteCoverage
        case .disagreementRequiresReview:
            disposition = .excludedConflict
        case .insufficientEvidence:
            disposition = .excludedInsufficientEvidence
        }

        let completedRide = record.historyRecord.evidence
        let attributedDate: Date
        switch calendarAttribution {
        case .rideBegan:
            attributedDate = completedRide.beganAtDate
        case .rideEnded:
            attributedDate = completedRide.endedAtDate
        }

        guard attributedDate.timeIntervalSinceReferenceDate.isFinite else {
            throw RideStatisticsError.invalidRide
        }

        sessionID = completedRide.sessionID
        self.attributedDate = attributedDate
        distanceMeters = reconciledDistance.finalDistanceMeters
        distanceDisposition = disposition
    }
}
