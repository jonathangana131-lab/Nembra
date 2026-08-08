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
    case invalidDistanceEvidence
    case unsupportedCheckpointSchema(Int)
    case completedRideMismatch(UUID)
    case missingCompletedRide(UUID)
    case durableVerificationFailed(UUID)
}

/// Durable configuration only. Decoding re-enters the validated production
/// reconciliation policy initializer so malformed priorities/tolerances fail closed.
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

/// Serialized measured-speed evidence. A decoded value is checkpoint data, not
/// trusted distance authority. Trusted restore always reruns the aggregator.
public struct RideHistoryLiveDistanceCheckpoint: Codable, Equatable, Sendable {
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

    fileprivate func aggregate(rideSessionID: UUID) throws -> RideLiveDistanceAggregate {
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
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Ride-history live-distance checkpoint is invalid."
                )
            )
        }
    }
}

/// Durable reconciliation inputs for one immutable completed ride.
///
/// No final distance, confidence, comparison result, or completion status is
/// persisted here. Those outputs are recomputed whenever trusted authority is
/// restored from the checkpoint.
public struct RideHistoryDistanceCheckpoint: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let completedRideEvidence: CompletedRideEvidence
    public let odometerCoverage: RideDistanceCoverage
    public let gpsRouteCoverage: RideDistanceCoverage
    public let liveDistanceCheckpoint: RideHistoryLiveDistanceCheckpoint?
    public let transportGapOccurred: Bool
    public let reconciliationPolicy: RideHistoryDistancePolicySnapshot

    public var sessionID: UUID { completedRideEvidence.sessionID }

    fileprivate init(
        schemaVersion: Int,
        completedRideEvidence: CompletedRideEvidence,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceCheckpoint: RideHistoryLiveDistanceCheckpoint?,
        transportGapOccurred: Bool,
        reconciliationPolicy: RideHistoryDistancePolicySnapshot
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RideHistoryDistanceAttachmentError.unsupportedCheckpointSchema(schemaVersion)
        }

        self.schemaVersion = schemaVersion
        self.completedRideEvidence = completedRideEvidence
        self.odometerCoverage = odometerCoverage
        self.gpsRouteCoverage = gpsRouteCoverage
        self.liveDistanceCheckpoint = liveDistanceCheckpoint
        self.transportGapOccurred = transportGapOccurred
        self.reconciliationPolicy = reconciliationPolicy

        _ = try reconciledDistance(validatingAgainst: completedRideEvidence)
    }

    fileprivate func reconciledDistance(
        validatingAgainst completedRide: CompletedRideEvidence
    ) throws -> ReconciledRideDistance {
        guard completedRide == completedRideEvidence else {
            throw RideHistoryDistanceAttachmentError.completedRideMismatch(
                completedRideEvidence.sessionID
            )
        }

        let liveAggregate = try liveDistanceCheckpoint?.aggregate(
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
            throw RideHistoryDistanceAttachmentError.invalidDistanceEvidence
        }

        return RideDistanceReconciler.reconcile(
            evidence: evidence,
            policy: try reconciliationPolicy.policy()
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case completedRideEvidence
        case odometerCoverage
        case gpsRouteCoverage
        case liveDistanceCheckpoint
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
                liveDistanceCheckpoint: container.decodeIfPresent(
                    RideHistoryLiveDistanceCheckpoint.self,
                    forKey: .liveDistanceCheckpoint
                ),
                transportGapOccurred: container.decode(Bool.self, forKey: .transportGapOccurred),
                reconciliationPolicy: container.decode(
                    RideHistoryDistancePolicySnapshot.self,
                    forKey: .reconciliationPolicy
                )
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Ride-history distance checkpoint is invalid."
                )
            )
        }
    }
}

/// Trusted runtime attachment. This is intentionally not Decodable: checkpoint
/// bytes must be rebound to independently loaded immutable history and reconciled
/// again before this capability can exist.
public struct RideHistoryDistanceRecord: Equatable, Sendable {
    private let checkpointStorage: RideHistoryDistanceCheckpoint

    public var sessionID: UUID { checkpointStorage.sessionID }
    public var checkpoint: RideHistoryDistanceCheckpoint { checkpointStorage }

#if SWIFT_PACKAGE
    package init(
        historyRecord: RideHistoryRecord,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceCheckpoint: RideHistoryLiveDistanceCheckpoint?,
        transportGapOccurred: Bool,
        reconciliationPolicy: RideDistanceReconciliationPolicy
    ) throws {
        let checkpoint = try RideHistoryDistanceCheckpoint(
            schemaVersion: RideHistoryDistanceCheckpoint.currentSchemaVersion,
            completedRideEvidence: historyRecord.evidence,
            odometerCoverage: odometerCoverage,
            gpsRouteCoverage: gpsRouteCoverage,
            liveDistanceCheckpoint: liveDistanceCheckpoint,
            transportGapOccurred: transportGapOccurred,
            reconciliationPolicy: RideHistoryDistancePolicySnapshot(policy: reconciliationPolicy)
        )
        try self.init(checkpoint: checkpoint, historyRecord: historyRecord)
    }

    package init(
        checkpoint: RideHistoryDistanceCheckpoint,
        historyRecord: RideHistoryRecord
    ) throws {
        _ = try checkpoint.reconciledDistance(validatingAgainst: historyRecord.evidence)
        checkpointStorage = checkpoint
    }
#else
    fileprivate init(
        historyRecord: RideHistoryRecord,
        odometerCoverage: RideDistanceCoverage,
        gpsRouteCoverage: RideDistanceCoverage,
        liveDistanceCheckpoint: RideHistoryLiveDistanceCheckpoint?,
        transportGapOccurred: Bool,
        reconciliationPolicy: RideDistanceReconciliationPolicy
    ) throws {
        let checkpoint = try RideHistoryDistanceCheckpoint(
            schemaVersion: RideHistoryDistanceCheckpoint.currentSchemaVersion,
            completedRideEvidence: historyRecord.evidence,
            odometerCoverage: odometerCoverage,
            gpsRouteCoverage: gpsRouteCoverage,
            liveDistanceCheckpoint: liveDistanceCheckpoint,
            transportGapOccurred: transportGapOccurred,
            reconciliationPolicy: RideHistoryDistancePolicySnapshot(policy: reconciliationPolicy)
        )
        try self.init(checkpoint: checkpoint, historyRecord: historyRecord)
    }

    fileprivate init(
        checkpoint: RideHistoryDistanceCheckpoint,
        historyRecord: RideHistoryRecord
    ) throws {
        _ = try checkpoint.reconciledDistance(validatingAgainst: historyRecord.evidence)
        checkpointStorage = checkpoint
    }
#endif

    fileprivate func reconciledDistance(
        validatingAgainst completedRide: CompletedRideEvidence
    ) throws -> ReconciledRideDistance {
        try checkpointStorage.reconciledDistance(validatingAgainst: completedRide)
    }
}

/// Persistence owns only checkpoint inputs. It never returns a pre-trusted runtime
/// distance record after relaunch.
public protocol RideHistoryDistanceStore: Sendable {
    func commit(
        _ checkpoint: RideHistoryDistanceCheckpoint
    ) async throws -> RideHistoryDistanceCommitResult

    func checkpoint(sessionID: UUID) async throws -> RideHistoryDistanceCheckpoint?
}

/// Runtime-only exact join between immutable base history and reminted distance
/// authority.
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

/// Capability required to construct the public coordinator restore surface.
///
/// The type is public so it can appear in the initializer signature, but its
/// initializer is intentionally package-owned in SwiftPM and file-owned when this
/// source is compiled directly into Nembra.app. Decoded checkpoint bytes alone
/// therefore cannot be turned back into trusted runtime authority by an arbitrary
/// package client or same-module app caller.
public struct RideHistoryDistanceRestoreAuthority: Sendable {
#if SWIFT_PACKAGE
    package init() {}
#else
    fileprivate init() {}
#endif
}

/// Persists only checkpoint inputs and remints trusted distance authority by
/// independently loading immutable base history on every read.
public actor RideHistoryDistanceCommitCoordinator {
    private let historyStore: any RideHistoryStore
    private let distanceStore: any RideHistoryDistanceStore

    /// Public shape, sealed construction: callers must possess package/file-owned
    /// restore authority rather than merely decoded checkpoint bytes.
    public init(
        historyStore: any RideHistoryStore,
        distanceStore: any RideHistoryDistanceStore,
        restoreAuthority: RideHistoryDistanceRestoreAuthority
    ) {
        _ = restoreAuthority
        self.historyStore = historyStore
        self.distanceStore = distanceStore
    }

#if SWIFT_PACKAGE
    /// Package-owned convenience used by trusted NembraCore adapters/tests.
    package init(
        historyStore: any RideHistoryStore,
        distanceStore: any RideHistoryDistanceStore
    ) {
        self.init(
            historyStore: historyStore,
            distanceStore: distanceStore,
            restoreAuthority: RideHistoryDistanceRestoreAuthority()
        )
    }
#endif

    @discardableResult
    public func commit(
        _ record: RideHistoryDistanceRecord
    ) async throws -> RideHistoryDistanceCommitResult {
        guard let historyRecord = try await historyStore.record(sessionID: record.sessionID) else {
            throw RideHistoryDistanceAttachmentError.missingCompletedRide(record.sessionID)
        }

        _ = try record.reconciledDistance(validatingAgainst: historyRecord.evidence)

        let checkpoint = record.checkpoint
        let result = try await distanceStore.commit(checkpoint)
        guard try await distanceStore.checkpoint(sessionID: record.sessionID) == checkpoint else {
            throw RideHistoryDistanceAttachmentError.durableVerificationFailed(record.sessionID)
        }
        return result
    }

    /// Base history with no checkpoint is ordinary distance unavailability.
    /// Orphaned/mismatched checkpoints fail closed, and storage itself never mints
    /// the trusted record.
    public func joinedRecord(
        sessionID: UUID
    ) async throws -> RideHistoryDistanceJoinedRecord? {
        let historyRecord = try await historyStore.record(sessionID: sessionID)
        let checkpoint = try await distanceStore.checkpoint(sessionID: sessionID)

        switch (historyRecord, checkpoint) {
        case (nil, nil), (.some, nil):
            return nil
        case (nil, .some):
            throw RideHistoryDistanceAttachmentError.missingCompletedRide(sessionID)
        case let (.some(historyRecord), .some(checkpoint)):
            let distanceRecord = try RideHistoryDistanceRecord(
                checkpoint: checkpoint,
                historyRecord: historyRecord
            )
            return try RideHistoryDistanceJoinedRecord(
                historyRecord: historyRecord,
                distanceRecord: distanceRecord
            )
        }
    }
}

#if SWIFT_PACKAGE
extension RideStatisticsRide {
    /// Delegates to the canonical reconciliation->statistics truth switch so the
    /// history adapter cannot drift from selected-source coverage semantics.
    package init(
        historyDistanceRecord record: RideHistoryDistanceJoinedRecord,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        try self.init(
            completedRide: record.historyRecord.evidence,
            reconciledDistance: record.reconciledDistance,
            calendarAttribution: calendarAttribution
        )
    }
}
#endif
