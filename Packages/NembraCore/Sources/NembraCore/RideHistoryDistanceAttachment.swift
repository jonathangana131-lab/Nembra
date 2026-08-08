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

/// Durable copy of the exact reconciliation policy used for one completed-ride
/// distance attachment.
///
/// This is persisted configuration, not distance authority. Decoding always
/// crosses the production policy initializer again so malformed priorities or
/// tolerances fail closed before a checkpoint can be restored by trusted package
/// code.
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

/// Durable serialized representation of the measured-speed segments needed to
/// reproduce one ride's live-distance aggregate after relaunch.
///
/// A decoded value is not trusted distance evidence. It is only checkpoint data.
/// `RideHistoryDistanceRecord` can consume it only through package-sealed restore
/// after exact completed-ride binding and authoritative reaggregation succeed.
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

/// Durable serialized inputs for one completed-ride distance reconciliation.
///
/// This value is intentionally only a checkpoint. Public decoding cannot mint a
/// trusted history attachment. The checkpoint stores the exact immutable
/// completed-ride snapshot it was created from, coverage classifications, durable
/// live-speed segment records, transport-gap fact, and exact reconciliation
/// policy. It deliberately never stores a caller-supplied final distance,
/// confidence, comparison result, or completion status.
///
/// Restoring trusted distance authority from these bytes is package-sealed and
/// requires an independently trusted exact `RideHistoryRecord`.
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

    private init(
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

        let policy = try reconciliationPolicy.policy()
        return RideDistanceReconciler.reconcile(evidence: evidence, policy: policy)
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

/// Trusted distance attachment bound to one immutable completed-history row.
///
/// This value is intentionally **not Decodable**. Arbitrary durable bytes must
/// first decode into `RideHistoryDistanceCheckpoint`, which remains only an
/// untrusted persisted representation. Package-owned construction/restoration
/// then requires exact base-history equality and deterministically re-runs both
/// live-distance aggregation and distance reconciliation before this trusted
/// runtime capability can exist.
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

/// Persistence owns only serialized checkpoint inputs. It never returns a
/// trusted `RideHistoryDistanceRecord` directly. On every read the coordinator
/// independently loads immutable base history, restores the checkpoint through
/// the sealed constructor, and re-runs live aggregation + reconciliation before a
/// joined trusted capability can exist.
public protocol RideHistoryDistanceStore: Sendable {
    func commit(
        _ checkpoint: RideHistoryDistanceCheckpoint
    ) async throws -> RideHistoryDistanceCommitResult

    func checkpoint(sessionID: UUID) async throws -> RideHistoryDistanceCheckpoint?
}

/// Freshly revalidated join between immutable base history and its trusted
/// distance attachment. This runtime capability is also intentionally non-Codable.
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

/// Idempotently attaches a trusted deterministic distance record to an
/// already-durable completed ride by persisting only its checkpoint inputs.
///
/// Durable read-back is verified at the checkpoint layer. Trusted runtime
/// authority is never loaded from storage directly; `joinedRecord` reconstructs
/// it only after an independently loaded exact `RideHistoryRecord` matches and
/// reconciliation succeeds again.
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

        let checkpoint = record.checkpoint
        let result = try await distanceStore.commit(checkpoint)
        guard try await distanceStore.checkpoint(sessionID: record.sessionID) == checkpoint else {
            throw RideHistoryDistanceAttachmentError.durableVerificationFailed(record.sessionID)
        }
        return result
    }

    /// A base history row with no distance checkpoint is ordinary unavailability.
    /// An orphaned checkpoint or a checkpoint bound to different immutable base
    /// evidence fails closed. The durable store never mints the trusted record.
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
    /// Package-sealed production adapter from the immutable-history distance join.
    /// Delegating to the canonical reconciliation bridge keeps one authoritative
    /// status/confidence -> statistics-disposition policy instead of duplicating
    /// that truth switch in a second file.
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
