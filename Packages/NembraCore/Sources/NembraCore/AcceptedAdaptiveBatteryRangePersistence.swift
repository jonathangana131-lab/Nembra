import Foundation

public enum AcceptedAdaptiveBatteryRangePersistenceError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidVehicleIdentityKey
    case invalidOperatingModeKey
    case scopeAuthorityMismatch
    case scopeMismatch
    case candidateAuthorityMismatch
    case candidateIdentityConflict
    case invalidCandidateSequence
    case invalidCandidateRecord
    case candidateReplayRejected
}

/// Authority of the durable identity used to scope learned range history.
///
/// This is intentionally separate from battery-measurement authority. A physically verified
/// battery percentage does not by itself prove which durable scooter identity should own the
/// learned history.
public enum AcceptedAdaptiveBatteryRangePersistenceScopeAuthority: String, Codable, Equatable, Hashable, Sendable {
    case verifiedVehicleIdentity
    case simulatorQA
}

/// Opaque durable scope for one learned-range history.
///
/// Verified physical construction is package-sealed. Ordinary app/UI code therefore cannot
/// turn a BLE name, profile label, or arbitrary string into verified persistence identity.
public struct AcceptedAdaptiveBatteryRangePersistenceScope: Codable, Equatable, Hashable, Sendable {
    public let vehicleIdentityKey: String
    public let operatingModeKey: String?
    public let authority: AcceptedAdaptiveBatteryRangePersistenceScopeAuthority

    private init(
        vehicleIdentityKey: String,
        operatingModeKey: String?,
        authority: AcceptedAdaptiveBatteryRangePersistenceScopeAuthority
    ) throws {
        guard !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AcceptedAdaptiveBatteryRangePersistenceError.invalidVehicleIdentityKey
        }
        if let operatingModeKey,
           operatingModeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AcceptedAdaptiveBatteryRangePersistenceError.invalidOperatingModeKey
        }
        self.vehicleIdentityKey = vehicleIdentityKey
        self.operatingModeKey = operatingModeKey
        self.authority = authority
    }

    public static func simulatorQA(
        vehicleIdentityKey: String,
        operatingModeKey: String? = nil
    ) throws -> Self {
        try Self(
            vehicleIdentityKey: vehicleIdentityKey,
            operatingModeKey: operatingModeKey,
            authority: .simulatorQA
        )
    }

#if SWIFT_PACKAGE
    package static func verifiedVehicleIdentity(
        vehicleIdentityKey: String,
        operatingModeKey: String? = nil
    ) throws -> Self {
        try Self(
            vehicleIdentityKey: vehicleIdentityKey,
            operatingModeKey: operatingModeKey,
            authority: .verifiedVehicleIdentity
        )
    }
#endif
}

public enum AcceptedAdaptiveBatteryRangeCandidateIdentityAuthority: String, Codable, Equatable, Hashable, Sendable {
    case verifiedDurableSource
    case simulatorQA
}

/// Durable higher-layer identity for one deterministic learned-range candidate.
///
/// Battery receipt identity is deliberately not used here: receipt acquisition epochs are
/// process-local currentness facts. Crash/relaunch exactly-once protection requires a durable
/// source session plus deterministic candidate ordinal that a trusted ride/evidence owner can
/// reproduce when the same durable evidence is replayed.
///
/// If replay under a changed policy produces different candidate bytes for the same identity,
/// persistence fails with `candidateIdentityConflict` instead of silently double-learning.
public struct AcceptedAdaptiveBatteryRangeCandidateIdentity: Codable, Equatable, Hashable, Sendable {
    public let sourceSessionID: UUID
    public let candidateOrdinal: UInt64
    public let authority: AcceptedAdaptiveBatteryRangeCandidateIdentityAuthority

    private init(
        sourceSessionID: UUID,
        candidateOrdinal: UInt64,
        authority: AcceptedAdaptiveBatteryRangeCandidateIdentityAuthority
    ) {
        self.sourceSessionID = sourceSessionID
        self.candidateOrdinal = candidateOrdinal
        self.authority = authority
    }

    public static func simulatorQA(
        sourceSessionID: UUID,
        candidateOrdinal: UInt64
    ) -> Self {
        Self(
            sourceSessionID: sourceSessionID,
            candidateOrdinal: candidateOrdinal,
            authority: .simulatorQA
        )
    }

#if SWIFT_PACKAGE
    package static func verifiedDurableSource(
        sourceSessionID: UUID,
        candidateOrdinal: UInt64
    ) -> Self {
        Self(
            sourceSessionID: sourceSessionID,
            candidateOrdinal: candidateOrdinal,
            authority: .verifiedDurableSource
        )
    }
#endif
}

/// One immutable accepted-learning journal record.
///
/// The record intentionally stores normalized learning inputs, not live receipt/currentness
/// authority. On restore these inputs are replayed through the raw validated math model inside
/// the package and only then wrapped by `AcceptedAdaptiveBatteryRangeModel`'s trusted restore
/// hook. Generic Codable import alone never produces an accepted live model.
public struct AcceptedAdaptiveBatteryRangeCandidateCheckpoint: Codable, Equatable, Sendable {
    public let sequenceIndex: UInt64
    public let identity: AcceptedAdaptiveBatteryRangeCandidateIdentity
    public let distanceMeters: Double
    public let distanceCoverage: BatteryRangeDistanceCoverage
    public let transportGapOccurred: Bool
    public let startSOCPercent: Double
    public let endSOCPercent: Double
    public let startUptimeNanoseconds: UInt64
    public let endUptimeNanoseconds: UInt64
    public let policy: AdaptiveBatteryRangePolicy
    public let plausibilityMaximumFullChargeEquivalentMeters: Double?

    fileprivate init(
        sequenceIndex: UInt64,
        identity: AcceptedAdaptiveBatteryRangeCandidateIdentity,
        window: AcceptedBatteryRangeLearningWindow,
        policy: AdaptiveBatteryRangePolicy,
        plausibilityPolicy: AcceptedAdaptiveRangePlausibilityPolicy
    ) {
        self.sequenceIndex = sequenceIndex
        self.identity = identity
        distanceMeters = window.distanceMeters
        distanceCoverage = window.distanceCoverage
        transportGapOccurred = window.transportGapOccurred
        startSOCPercent = window.startSOC.percentage
        endSOCPercent = window.endSOC.percentage
        startUptimeNanoseconds = window.startSOC.receivedAtUptimeNanoseconds
        endUptimeNanoseconds = window.endSOC.receivedAtUptimeNanoseconds
        self.policy = policy
        plausibilityMaximumFullChargeEquivalentMeters = plausibilityPolicy.maximumFullChargeEquivalentMeters
    }
}

/// Versioned journal checkpoint. This is a data object only; decoding it does not restore
/// accepted authority. Verified restore remains package-sealed and requires an independently
/// supplied expected verified vehicle scope.
public struct AcceptedAdaptiveBatteryRangePersistenceCheckpoint: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let scope: AcceptedAdaptiveBatteryRangePersistenceScope
    public let acceptedCandidates: [AcceptedAdaptiveBatteryRangeCandidateCheckpoint]

    fileprivate init(
        scope: AcceptedAdaptiveBatteryRangePersistenceScope,
        acceptedCandidates: [AcceptedAdaptiveBatteryRangeCandidateCheckpoint]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.scope = scope
        self.acceptedCandidates = acceptedCandidates
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case scope
        case acceptedCandidates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw AcceptedAdaptiveBatteryRangePersistenceError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        scope = try container.decode(AcceptedAdaptiveBatteryRangePersistenceScope.self, forKey: .scope)
        acceptedCandidates = try container.decode(
            [AcceptedAdaptiveBatteryRangeCandidateCheckpoint].self,
            forKey: .acceptedCandidates
        )
    }
}

public struct AcceptedAdaptiveBatteryRangePersistentIngestResult: Equatable, Sendable {
    public let learningResult: AcceptedBatteryRangeLearningResult
    public let alreadyCommitted: Bool

    fileprivate init(
        learningResult: AcceptedBatteryRangeLearningResult,
        alreadyCommitted: Bool
    ) {
        self.learningResult = learningResult
        self.alreadyCommitted = alreadyCommitted
    }
}

/// Accepted learned-range model plus its durable exactly-once journal.
///
/// This type does not choose a physical vehicle identity, ride/distance source, candidate ID,
/// ES80 field, or plausibility ceiling. Those remain higher-layer evidence responsibilities.
/// It only guarantees that an accepted candidate and its durable identity enter learned history
/// together in one in-memory state transition, and that a serialized checkpoint can later be
/// replay-validated before accepted model authority is restored.
public struct AcceptedAdaptiveBatteryRangePersistentModel: Sendable {
    public let scope: AcceptedAdaptiveBatteryRangePersistenceScope

    private var model: AcceptedAdaptiveBatteryRangeModel
    private var acceptedCandidates: [AcceptedAdaptiveBatteryRangeCandidateCheckpoint]

    private init(
        scope: AcceptedAdaptiveBatteryRangePersistenceScope,
        model: AcceptedAdaptiveBatteryRangeModel = AcceptedAdaptiveBatteryRangeModel(),
        acceptedCandidates: [AcceptedAdaptiveBatteryRangeCandidateCheckpoint] = []
    ) {
        self.scope = scope
        self.model = model
        self.acceptedCandidates = acceptedCandidates
    }

    public static func simulatorQA(
        vehicleIdentityKey: String,
        operatingModeKey: String? = nil
    ) throws -> Self {
        Self(
            scope: try .simulatorQA(
                vehicleIdentityKey: vehicleIdentityKey,
                operatingModeKey: operatingModeKey
            )
        )
    }

#if SWIFT_PACKAGE
    package static func verifiedVehicleIdentity(
        vehicleIdentityKey: String,
        operatingModeKey: String? = nil
    ) throws -> Self {
        Self(
            scope: try .verifiedVehicleIdentity(
                vehicleIdentityKey: vehicleIdentityKey,
                operatingModeKey: operatingModeKey
            )
        )
    }
#endif

    public var hasLearnedEfficiency: Bool { model.hasLearnedEfficiency }
    public var historicalConsumedPercentagePoints: Double { model.historicalConsumedPercentagePoints }
    public var acceptedWindowCount: Int { model.acceptedWindowCount }
    public var committedCandidateCount: Int { acceptedCandidates.count }

    public func confidence(using policy: AdaptiveBatteryRangePolicy) -> AdaptiveRangeConfidence {
        model.confidence(using: policy)
    }

    public func typicalFullChargeRangeMeters(
        using policy: AdaptiveBatteryRangePolicy
    ) -> Double? {
        model.typicalFullChargeRangeMeters(using: policy)
    }

    public func checkpoint() -> AcceptedAdaptiveBatteryRangePersistenceCheckpoint {
        AcceptedAdaptiveBatteryRangePersistenceCheckpoint(
            scope: scope,
            acceptedCandidates: acceptedCandidates
        )
    }

#if SWIFT_PACKAGE
    /// Package-trusted mutation path. Candidate identity must come from the same authority class
    /// as the persistent scope. Replaying the exact same committed candidate is idempotent;
    /// reusing its identity for different evidence fails closed.
    package mutating func ingest(
        _ window: AcceptedBatteryRangeLearningWindow,
        candidateIdentity: AcceptedAdaptiveBatteryRangeCandidateIdentity,
        policy: AdaptiveBatteryRangePolicy,
        plausibilityPolicy: AcceptedAdaptiveRangePlausibilityPolicy
    ) throws -> AcceptedAdaptiveBatteryRangePersistentIngestResult {
        try Self.requireCompatibleAuthority(
            scope: scope,
            candidateIdentity: candidateIdentity
        )

        if let existing = acceptedCandidates.first(where: { $0.identity == candidateIdentity }) {
            let replay = AcceptedAdaptiveBatteryRangeCandidateCheckpoint(
                sequenceIndex: existing.sequenceIndex,
                identity: candidateIdentity,
                window: window,
                policy: policy,
                plausibilityPolicy: plausibilityPolicy
            )
            guard replay == existing else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.candidateIdentityConflict
            }

            return AcceptedAdaptiveBatteryRangePersistentIngestResult(
                learningResult: AcceptedBatteryRangeLearningResult(
                    disposition: .accepted,
                    sample: BatteryRangeEfficiencySample(
                        distanceMeters: existing.distanceMeters,
                        consumedPercentagePoints: existing.startSOCPercent - existing.endSOCPercent
                    ),
                    confidence: model.confidence(using: policy)
                ),
                alreadyCommitted: true
            )
        }

        let result = model.ingest(
            window,
            policy: policy,
            plausibilityPolicy: plausibilityPolicy
        )

        if case .accepted = result.disposition {
            guard acceptedCandidates.count < Int.max,
                  let sequenceIndex = UInt64(exactly: acceptedCandidates.count) else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.invalidCandidateSequence
            }
            acceptedCandidates.append(
                AcceptedAdaptiveBatteryRangeCandidateCheckpoint(
                    sequenceIndex: sequenceIndex,
                    identity: candidateIdentity,
                    window: window,
                    policy: policy,
                    plausibilityPolicy: plausibilityPolicy
                )
            )
        }

        return AcceptedAdaptiveBatteryRangePersistentIngestResult(
            learningResult: result,
            alreadyCommitted: false
        )
    }

    package static func restoringVerifiedVehicleIdentity(
        _ checkpoint: AcceptedAdaptiveBatteryRangePersistenceCheckpoint,
        expectedScope: AcceptedAdaptiveBatteryRangePersistenceScope
    ) throws -> Self {
        guard expectedScope.authority == .verifiedVehicleIdentity else {
            throw AcceptedAdaptiveBatteryRangePersistenceError.scopeAuthorityMismatch
        }
        return try restore(
            checkpoint,
            expectedScope: expectedScope,
            requiredCandidateAuthority: .verifiedDurableSource
        )
    }
#endif

    public static func restoringSimulatorQA(
        _ checkpoint: AcceptedAdaptiveBatteryRangePersistenceCheckpoint,
        expectedScope: AcceptedAdaptiveBatteryRangePersistenceScope
    ) throws -> Self {
        guard expectedScope.authority == .simulatorQA else {
            throw AcceptedAdaptiveBatteryRangePersistenceError.scopeAuthorityMismatch
        }
        return try restore(
            checkpoint,
            expectedScope: expectedScope,
            requiredCandidateAuthority: .simulatorQA
        )
    }

    private static func restore(
        _ checkpoint: AcceptedAdaptiveBatteryRangePersistenceCheckpoint,
        expectedScope: AcceptedAdaptiveBatteryRangePersistenceScope,
        requiredCandidateAuthority: AcceptedAdaptiveBatteryRangeCandidateIdentityAuthority
    ) throws -> Self {
        guard checkpoint.schemaVersion == AcceptedAdaptiveBatteryRangePersistenceCheckpoint.currentSchemaVersion else {
            throw AcceptedAdaptiveBatteryRangePersistenceError.unsupportedSchemaVersion(checkpoint.schemaVersion)
        }
        guard checkpoint.scope == expectedScope else {
            throw AcceptedAdaptiveBatteryRangePersistenceError.scopeMismatch
        }

        var rawModel = AdaptiveBatteryRangeModel()
        var seenIdentities = Set<AcceptedAdaptiveBatteryRangeCandidateIdentity>()

        for (offset, record) in checkpoint.acceptedCandidates.enumerated() {
            guard let expectedSequence = UInt64(exactly: offset),
                  record.sequenceIndex == expectedSequence else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.invalidCandidateSequence
            }
            guard record.identity.authority == requiredCandidateAuthority else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.candidateAuthorityMismatch
            }
            guard seenIdentities.insert(record.identity).inserted else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.candidateIdentityConflict
            }

            let start: BatterySOCReading
            let end: BatterySOCReading
            let rawWindow: BatteryRangeLearningWindow
            do {
                start = try BatterySOCReading(
                    percentage: record.startSOCPercent,
                    provenance: .authoritativeMeasurement,
                    receivedAtUptimeNanoseconds: record.startUptimeNanoseconds
                )
                end = try BatterySOCReading(
                    percentage: record.endSOCPercent,
                    provenance: .authoritativeMeasurement,
                    receivedAtUptimeNanoseconds: record.endUptimeNanoseconds
                )
                rawWindow = try BatteryRangeLearningWindow(
                    distanceMeters: record.distanceMeters,
                    distanceCoverage: record.distanceCoverage,
                    transportGapOccurred: record.transportGapOccurred,
                    startSOC: start,
                    endSOC: end
                )
            } catch {
                throw AcceptedAdaptiveBatteryRangePersistenceError.invalidCandidateRecord
            }

            let consumed = record.startSOCPercent - record.endSOCPercent
            guard consumed.isFinite, consumed > 0 else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.invalidCandidateRecord
            }
            let metersPerPercentagePoint = record.distanceMeters / consumed
            let fullChargeEquivalentMeters = metersPerPercentagePoint * 100
            guard metersPerPercentagePoint.isFinite,
                  metersPerPercentagePoint > 0,
                  fullChargeEquivalentMeters.isFinite else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.invalidCandidateRecord
            }

            if let maximum = record.plausibilityMaximumFullChargeEquivalentMeters {
                guard maximum.isFinite,
                      maximum > 0,
                      fullChargeEquivalentMeters <= maximum else {
                    throw AcceptedAdaptiveBatteryRangePersistenceError.invalidCandidateRecord
                }
            } else if rawModel.hasLearnedEfficiency == false {
                // A brand-new accepted model cannot have learned its first window under the
                // fail-closed `deferredUntilVerifiedEvidence` policy.
                throw AcceptedAdaptiveBatteryRangePersistenceError.invalidCandidateRecord
            }

            let replay = rawModel.ingest(rawWindow, policy: record.policy)
            guard case .accepted = replay.disposition else {
                throw AcceptedAdaptiveBatteryRangePersistenceError.candidateReplayRejected
            }
        }

        guard rawModel.acceptedWindowCount == checkpoint.acceptedCandidates.count else {
            throw AcceptedAdaptiveBatteryRangePersistenceError.candidateReplayRejected
        }

        return Self(
            scope: expectedScope,
            model: AcceptedAdaptiveBatteryRangeModel(trustedRestoredModel: rawModel),
            acceptedCandidates: checkpoint.acceptedCandidates
        )
    }

    private static func requireCompatibleAuthority(
        scope: AcceptedAdaptiveBatteryRangePersistenceScope,
        candidateIdentity: AcceptedAdaptiveBatteryRangeCandidateIdentity
    ) throws {
        switch (scope.authority, candidateIdentity.authority) {
        case (.verifiedVehicleIdentity, .verifiedDurableSource),
             (.simulatorQA, .simulatorQA):
            return
        default:
            throw AcceptedAdaptiveBatteryRangePersistenceError.candidateAuthorityMismatch
        }
    }
}
