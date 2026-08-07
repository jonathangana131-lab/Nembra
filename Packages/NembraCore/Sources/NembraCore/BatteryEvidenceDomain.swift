import Foundation

public enum BatteryEvidenceValidationError: Error, Equatable, Sendable {
    case invalidSemanticValue
    case invalidTimestamp
    case invalidEvidenceRole
    case missingReceiptIdentity
}

/// Semantic battery fields that Nembra may eventually learn from real ES80 evidence.
///
/// These cases name the meaning of a normalized value only. Their presence does not
/// prove that the physical scooter exposes that field; `BatteryEvidenceRole` keeps
/// the evidence/truth status separate from the semantic value.
public enum BatteryEvidenceField: String, Codable, CaseIterable, Sendable {
    case stateOfChargePercent
    case voltageVolts
    case currentAmps
    case powerWatts
    case chargingState
}

/// A validated, normalized battery value with no embedded claim about where it came from.
///
/// Raw BLE/Tuya bytes remain outside this type. Decoding/normalizing a plausible number
/// does not establish that the target scooter physically exposes that semantic field.
public struct BatterySemanticValue: Equatable, Codable, Sendable {
    public let field: BatteryEvidenceField
    public let numericValue: Double?
    public let booleanValue: Bool?

    private init(
        field: BatteryEvidenceField,
        numericValue: Double?,
        booleanValue: Bool?
    ) throws {
        switch field {
        case .stateOfChargePercent:
            guard let numericValue,
                  booleanValue == nil,
                  numericValue.isFinite,
                  (0...100).contains(numericValue) else {
                throw BatteryEvidenceValidationError.invalidSemanticValue
            }

        case .voltageVolts:
            guard let numericValue,
                  booleanValue == nil,
                  numericValue.isFinite,
                  numericValue >= 0 else {
                throw BatteryEvidenceValidationError.invalidSemanticValue
            }

        case .currentAmps, .powerWatts:
            // Do not assume sign semantics before the real ES80 is verified. A future
            // validated protocol may legitimately use signed current/power for braking,
            // charging, or another direction convention.
            guard let numericValue,
                  booleanValue == nil,
                  numericValue.isFinite else {
                throw BatteryEvidenceValidationError.invalidSemanticValue
            }

        case .chargingState:
            guard numericValue == nil, booleanValue != nil else {
                throw BatteryEvidenceValidationError.invalidSemanticValue
            }
        }

        self.field = field
        self.numericValue = numericValue
        self.booleanValue = booleanValue
    }

    public static func stateOfChargePercent(_ percentage: Double) throws -> Self {
        try Self(field: .stateOfChargePercent, numericValue: percentage, booleanValue: nil)
    }

    public static func voltageVolts(_ volts: Double) throws -> Self {
        try Self(field: .voltageVolts, numericValue: volts, booleanValue: nil)
    }

    public static func currentAmps(_ amps: Double) throws -> Self {
        try Self(field: .currentAmps, numericValue: amps, booleanValue: nil)
    }

    public static func powerWatts(_ watts: Double) throws -> Self {
        try Self(field: .powerWatts, numericValue: watts, booleanValue: nil)
    }

    public static func chargingState(_ isCharging: Bool) throws -> Self {
        try Self(field: .chargingState, numericValue: nil, booleanValue: isCharging)
    }

    private enum CodingKeys: String, CodingKey {
        case field
        case numericValue
        case booleanValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let field = try container.decode(BatteryEvidenceField.self, forKey: .field)
        let numericValue = try container.decodeIfPresent(Double.self, forKey: .numericValue)
        let booleanValue = try container.decodeIfPresent(Bool.self, forKey: .booleanValue)

        do {
            try self.init(field: field, numericValue: numericValue, booleanValue: booleanValue)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .field,
                in: container,
                debugDescription: "Persisted battery semantic value violates domain invariants."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(field, forKey: .field)
        try container.encodeIfPresent(numericValue, forKey: .numericValue)
        try container.encodeIfPresent(booleanValue, forKey: .booleanValue)
    }
}

/// Truth role of one normalized battery value.
public enum BatteryEvidenceRole: String, Codable, CaseIterable, Sendable {
    /// Reserved for a target-vehicle field whose raw source, semantics, and scaling have
    /// been physically verified. Generic external construction/Codable import cannot set
    /// this role on a trusted `BatteryEvidenceObservation`.
    case verifiedVehicleMeasurement

    case stockAppCorrelationAnchor
    case simulationFixture
    case derivedEstimate
    case presentationOnly
}

public enum BatteryEvidenceContinuity: String, Codable, Sendable {
    case continuous
    case afterUnobservedInterval
}

/// File-scoped construction marker. Its only purpose is to prevent a role-selecting raw
/// initializer from becoming visible merely because this source is manually compiled into
/// the Nembra app target's Swift module.
fileprivate enum BatteryEvidenceConstructionBoundary {
    case validatedDomain
}

/// Process-local identity of one raw acquisition callback before semantic normalization.
///
/// The epoch separates unrelated acquisition lifetimes. The sequence number gives a strict
/// callback order inside that epoch even when two callbacks receive the same uptime tick.
/// This identity is deliberately not `Codable`: imported/persisted data cannot restore live
/// callback identity or currentness merely by replaying an epoch/sequence pair.
public struct BatteryEvidenceReceiptIdentity: Equatable, Hashable, Sendable {
    public let acquisitionEpoch: UUID
    public let sequenceNumber: UInt64

    fileprivate init(
        acquisitionEpoch: UUID,
        sequenceNumber: UInt64,
        constructionBoundary: BatteryEvidenceConstructionBoundary
    ) {
        _ = constructionBoundary
        self.acquisitionEpoch = acquisitionEpoch
        self.sequenceNumber = sequenceNumber
    }

#if SWIFT_PACKAGE
    /// Package-scoped deterministic construction supports package tests and a future trusted
    /// acquisition target in this same Swift package. Package clients outside NembraCore's
    /// package cannot mint receipt identities through this initializer.
    package init(acquisitionEpoch: UUID, sequenceNumber: UInt64) {
        self.init(
            acquisitionEpoch: acquisitionEpoch,
            sequenceNumber: sequenceNumber,
            constructionBoundary: .validatedDomain
        )
    }
#endif
}

#if SWIFT_PACKAGE
package enum BatteryEvidenceReceiptSequencerError: Error, Equatable, Sendable {
    case sequenceExhausted
}

/// Small synchronous sequencer intended to be owned by one serialized acquisition boundary.
///
/// Receipt identity must be minted before work fans out asynchronously. This is a reference
/// type deliberately: copying a mutable value sequencer could fork the counter and mint two
/// identical `(epoch, sequence)` receipts. Aliasing this object instead shares one counter.
/// The trusted acquisition owner must call it only from its already-serialized callback path;
/// immutable receipt identities, not the sequencer, are what cross into async normalization.
package final class BatteryEvidenceReceiptSequencer {
    package let acquisitionEpoch: UUID
    private var nextSequenceNumber: UInt64

    package init(
        acquisitionEpoch: UUID = UUID(),
        startingSequenceNumber: UInt64 = 1
    ) {
        self.acquisitionEpoch = acquisitionEpoch
        self.nextSequenceNumber = startingSequenceNumber
    }

    package func nextReceiptIdentity() throws -> BatteryEvidenceReceiptIdentity {
        guard nextSequenceNumber != UInt64.max else {
            throw BatteryEvidenceReceiptSequencerError.sequenceExhausted
        }

        let identity = BatteryEvidenceReceiptIdentity(
            acquisitionEpoch: acquisitionEpoch,
            sequenceNumber: nextSequenceNumber
        )
        nextSequenceNumber += 1
        return identity
    }
}
#endif

/// One normalized battery observation with explicit truth/provenance boundaries.
///
/// Authoritative construction is deliberately unavailable to ordinary app/source files.
/// External callers can create only non-authoritative observations through
/// `nonAuthoritative(...)`. Live stream/currentness consumers additionally require a
/// process-local `receiptIdentity`; generic imported observations intentionally lack one.
public struct BatteryEvidenceObservation: Equatable, Codable, Sendable {
    public let value: BatterySemanticValue
    public let role: BatteryEvidenceRole
    public let receiptIdentity: BatteryEvidenceReceiptIdentity?
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let continuity: BatteryEvidenceContinuity

    /// Lowest-level construction is file-scoped. This matters because the current Nembra
    /// Xcode project manually compiles selected NembraCore source files into the app target
    /// rather than linking the package product. Plain module-internal access would therefore
    /// become callable by unrelated app code in that direct-source composition.
    fileprivate init(
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        receiptIdentity: BatteryEvidenceReceiptIdentity?,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        continuity: BatteryEvidenceContinuity = .continuous,
        constructionBoundary: BatteryEvidenceConstructionBoundary
    ) throws {
        _ = constructionBoundary
        guard receivedAtDate.timeIntervalSinceReferenceDate.isFinite else {
            throw BatteryEvidenceValidationError.invalidTimestamp
        }
        if role == .verifiedVehicleMeasurement, receiptIdentity == nil {
            throw BatteryEvidenceValidationError.missingReceiptIdentity
        }

        self.value = value
        self.role = role
        self.receiptIdentity = receiptIdentity
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtDate = receivedAtDate
        self.continuity = continuity
    }

#if SWIFT_PACKAGE
    /// Package-scoped construction exists only when NembraCore is compiled as an actual
    /// Swift package module. Verified observations require a receipt identity minted at the
    /// trusted acquisition boundary. Non-authoritative package fixtures may omit identity
    /// when they intentionally model imported/retained evidence that is not live-current.
    package init(
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        receiptIdentity: BatteryEvidenceReceiptIdentity? = nil,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws {
        try self.init(
            value: value,
            role: role,
            receiptIdentity: receiptIdentity,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            receivedAtDate: receivedAtDate,
            continuity: continuity,
            constructionBoundary: .validatedDomain
        )
    }
#endif

    /// Public construction path for evidence that must not claim physical target
    /// verification. Generic public observations are deliberately unbound to a live receipt;
    /// a caller cannot turn imported/research data into current stream evidence by supplying
    /// an epoch/sequence pair.
    public static func nonAuthoritative(
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> Self {
        guard role != .verifiedVehicleMeasurement else {
            throw BatteryEvidenceValidationError.invalidEvidenceRole
        }

        return try Self(
            value: value,
            role: role,
            receiptIdentity: nil,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            receivedAtDate: receivedAtDate,
            continuity: continuity,
            constructionBoundary: .validatedDomain
        )
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case role
        case receivedAtUptimeNanoseconds
        case receivedAtDate
        case continuity
    }

    /// Generic Codable import is deliberately non-authoritative and receipt-unbound. A
    /// serialized payload cannot self-assert physical verification or live callback identity.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(BatterySemanticValue.self, forKey: .value)
        let role = try container.decode(BatteryEvidenceRole.self, forKey: .role)
        let receivedAtUptimeNanoseconds = try container.decode(UInt64.self, forKey: .receivedAtUptimeNanoseconds)
        let receivedAtDate = try container.decode(Date.self, forKey: .receivedAtDate)
        let continuity = try container.decode(BatteryEvidenceContinuity.self, forKey: .continuity)

        guard role != .verifiedVehicleMeasurement else {
            throw DecodingError.dataCorruptedError(
                forKey: .role,
                in: container,
                debugDescription: "Generic battery observation import cannot establish verified vehicle authority."
            )
        }

        do {
            try self.init(
                value: value,
                role: role,
                receiptIdentity: nil,
                receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
                receivedAtDate: receivedAtDate,
                continuity: continuity,
                constructionBoundary: .validatedDomain
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .receivedAtDate,
                in: container,
                debugDescription: "Persisted battery evidence observation violates domain invariants."
            )
        }
    }

    /// The generic Codable channel is for non-authoritative research/simulation/derived
    /// evidence. Verified observations are process/trust-boundary evidence and require a
    /// future explicit verified persistence design rather than silently serializing trust.
    /// Receipt identity is intentionally omitted even for bound non-authoritative package
    /// fixtures, so process-local callback identity never survives this generic codec.
    public func encode(to encoder: Encoder) throws {
        guard role != .verifiedVehicleMeasurement else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Generic battery observation encoding cannot serialize verified vehicle authority."
                )
            )
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(role, forKey: .role)
        try container.encode(receivedAtUptimeNanoseconds, forKey: .receivedAtUptimeNanoseconds)
        try container.encode(receivedAtDate, forKey: .receivedAtDate)
        try container.encode(continuity, forKey: .continuity)
    }

    public var isAuthoritativeVehicleMeasurement: Bool {
        role == .verifiedVehicleMeasurement
    }

    public var isAdaptiveRangeSOCEvidence: Bool {
        isAuthoritativeVehicleMeasurement && value.field == .stateOfChargePercent
    }

    public var isVerifiedElectricalTelemetry: Bool {
        guard isAuthoritativeVehicleMeasurement else { return false }
        switch value.field {
        case .voltageVolts, .currentAmps, .powerWatts, .chargingState:
            return true
        case .stateOfChargePercent:
            return false
        }
    }

    public var isStockAppCorrelationAnchor: Bool {
        role == .stockAppCorrelationAnchor
    }

    public var requiresNewContinuityAnchor: Bool {
        continuity == .afterUnobservedInterval
    }
}
