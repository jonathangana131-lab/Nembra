import Foundation

public enum BatteryEvidenceValidationError: Error, Equatable, Sendable {
    case invalidSemanticValue
    case invalidTimestamp
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
/// Raw BLE/Tuya bytes remain in the passive capture/research layer. A protocol adapter
/// may construct one of these only after it has decoded a candidate semantic value.
/// Whether that candidate is verified, a stock-app correlation anchor, an estimate, or
/// presentation-only state is expressed separately by `BatteryEvidenceObservation.role`.
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
        try Self(
            field: .stateOfChargePercent,
            numericValue: percentage,
            booleanValue: nil
        )
    }

    public static func voltageVolts(_ volts: Double) throws -> Self {
        try Self(
            field: .voltageVolts,
            numericValue: volts,
            booleanValue: nil
        )
    }

    public static func currentAmps(_ amps: Double) throws -> Self {
        try Self(
            field: .currentAmps,
            numericValue: amps,
            booleanValue: nil
        )
    }

    public static func powerWatts(_ watts: Double) throws -> Self {
        try Self(
            field: .powerWatts,
            numericValue: watts,
            booleanValue: nil
        )
    }

    public static func chargingState(_ isCharging: Bool) throws -> Self {
        try Self(
            field: .chargingState,
            numericValue: nil,
            booleanValue: isCharging
        )
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
            try self.init(
                field: field,
                numericValue: numericValue,
                booleanValue: booleanValue
            )
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
///
/// The role is intentionally stricter than a generic "source" string so a stock-app
/// number, Simulator fixture, estimate, or animated/display value cannot silently become
/// a verified scooter measurement merely because the numeric value looks plausible.
public enum BatteryEvidenceRole: String, Codable, CaseIterable, Sendable {
    /// Semantics and scaling have been physically verified for the target vehicle/protocol.
    case verifiedVehicleMeasurement

    /// A value directly observed in the stock app and useful only as a correlation anchor
    /// until its raw transport/DP source and semantics are physically verified.
    case stockAppCorrelationAnchor

    /// Deterministic software/Simulator evidence. Useful for QA, never physical ES80 proof.
    case simulationFixture

    /// A derived/estimated semantic value. It must never be stored as measured telemetry.
    case derivedEstimate

    /// A presentation-only value such as an animated/intermediate display frame.
    case presentationOnly
}

/// Whether the observation follows continuously from prior evidence in the same process
/// or is the first value after an interval Nembra did not observe.
public enum BatteryEvidenceContinuity: String, Codable, Sendable {
    case continuous
    case afterUnobservedInterval
}

/// One normalized battery observation with explicit truth/provenance boundaries.
public struct BatteryEvidenceObservation: Equatable, Codable, Sendable {
    public let value: BatterySemanticValue
    public let role: BatteryEvidenceRole
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let continuity: BatteryEvidenceContinuity

    public init(
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws {
        guard receivedAtDate.timeIntervalSinceReferenceDate.isFinite else {
            throw BatteryEvidenceValidationError.invalidTimestamp
        }

        self.value = value
        self.role = role
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtDate = receivedAtDate
        self.continuity = continuity
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case role
        case receivedAtUptimeNanoseconds
        case receivedAtDate
        case continuity
    }

    /// Persisted/imported observations re-enter through the same validation boundary as
    /// live construction. Codable conformance is not allowed to bypass timestamp truth.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decode(BatterySemanticValue.self, forKey: .value)
        let role = try container.decode(BatteryEvidenceRole.self, forKey: .role)
        let receivedAtUptimeNanoseconds = try container.decode(UInt64.self, forKey: .receivedAtUptimeNanoseconds)
        let receivedAtDate = try container.decode(Date.self, forKey: .receivedAtDate)
        let continuity = try container.decode(BatteryEvidenceContinuity.self, forKey: .continuity)

        do {
            try self.init(
                value: value,
                role: role,
                receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
                receivedAtDate: receivedAtDate,
                continuity: continuity
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .receivedAtDate,
                in: container,
                debugDescription: "Persisted battery evidence observation violates timestamp invariants."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
        try container.encode(role, forKey: .role)
        try container.encode(receivedAtUptimeNanoseconds, forKey: .receivedAtUptimeNanoseconds)
        try container.encode(receivedAtDate, forKey: .receivedAtDate)
        try container.encode(continuity, forKey: .continuity)
    }

    /// Only physically verified target-vehicle measurements cross this boundary.
    /// Stock-app observations, Simulator fixtures, estimates, and display frames do not.
    public var isAuthoritativeVehicleMeasurement: Bool {
        role == .verifiedVehicleMeasurement
    }

    /// Eligibility of a single SoC anchor for the adaptive-range domain.
    /// A higher layer must still reject windows with incomplete distance coverage,
    /// unobserved transport intervals, insufficient consumption, or other policy failures.
    public var isAdaptiveRangeSOCEvidence: Bool {
        isAuthoritativeVehicleMeasurement && value.field == .stateOfChargePercent
    }

    /// Electrical values may enter a production telemetry/electrical domain only after
    /// their target-vehicle semantics are physically verified.
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
