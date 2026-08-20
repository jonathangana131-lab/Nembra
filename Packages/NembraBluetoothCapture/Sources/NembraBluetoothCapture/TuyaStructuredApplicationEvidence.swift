import CryptoKit
import Foundation

/// The only application-level source represented by this evidence schema.
///
/// This is an official Tuya SDK callback, not a CoreBluetooth packet callback. Values carried by
/// this source must never be described as raw FD50 bytes or accepted as decoded scooter telemetry.
public enum TuyaStructuredApplicationEvidenceSource: String, Codable, Sendable {
    case tuyaSDKDPUpdate
}

/// The interpretation boundary attached to every structured Tuya application observation.
///
/// An observation can support later protocol research. It does not establish that a DP key means
/// speed, battery, power, odometer, mode, light, lock, an error, or a writable command.
public enum TuyaStructuredApplicationEvidenceInterpretation: String, Codable, Sendable {
    case unmappedApplicationObservation
}

public enum TuyaStructuredApplicationEvidenceValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidPseudonymousSessionID
    case invalidConnectionGeneration(UInt64)
    case invalidDeliverySequence(UInt64)
    case invalidMonotonicReceipt(UInt64)
    case invalidWallClock
    case emptyApplicationUpdate
    case invalidKey(path: String)
    case duplicateKey(path: String)
    case nonFiniteDecimal(path: String)
    case nestingLimitExceeded(path: String)
    case collectionLimitExceeded(path: String)
    case rawTransportBytesClaimed
    case unexpectedInterpretation(TuyaStructuredApplicationEvidenceInterpretation)
    case mixedPseudonymousSessions(eventIndex: Int)
    case connectionGenerationRegressed(eventIndex: Int)
    case duplicateOrReplayedEvent(eventIndex: Int)
    case malformedJSON
    case inputByteLimitExceeded(byteCount: Int, maximum: Int)
    case duplicateWireField(String)
    case nonCanonicalJSON
}

/// A random, non-device session correlation value.
///
/// The package deliberately accepts only RFC 4122 version-4 UUIDs. Callers must mint a fresh value
/// for the capture session; Bluetooth peripheral UUIDs, Tuya device IDs, account IDs, and other
/// stable identifiers do not belong in the event's session-metadata identity fields. Structured
/// callback payload strings remain exact and may independently contain identifier-shaped values.
public struct TuyaStructuredApplicationSessionID: Hashable, Codable, Sendable {
    private let canonicalValue: String

    public var value: String { canonicalValue }

    public static func makeRandom() -> Self {
        // Foundation UUID() is an RFC 4122 version-4 UUID. Keep the defensive precondition here so
        // a future platform behavior change cannot silently weaken the pseudonymous-ID boundary.
        guard let value = try? Self(pseudonymousUUID: UUID()) else {
            preconditionFailure("Foundation failed to mint an RFC 4122 version-4 UUID")
        }
        return value
    }

    public init(pseudonymousUUID: UUID) throws {
        let canonical = pseudonymousUUID.uuidString.lowercased()
        guard Self.isRFC4122Version4(canonical) else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .invalidPseudonymousSessionID
        }
        self.canonicalValue = canonical
    }

    private init(canonicalValue: String) throws {
        guard canonicalValue == canonicalValue.lowercased(),
              let uuid = UUID(uuidString: canonicalValue),
              uuid.uuidString.lowercased() == canonicalValue,
              Self.isRFC4122Version4(canonicalValue) else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .invalidPseudonymousSessionID
        }
        self.canonicalValue = canonicalValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(canonicalValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalValue)
    }

    private static func isRFC4122Version4(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count == 36 else { return false }
        guard bytes[14] == 0x34 else { return false }
        return [UInt8(0x38), 0x39, 0x61, 0x62].contains(bytes[19])
    }
}

/// Lossless typed identity for one Tuya DP dictionary key.
///
/// A textual `"1"`, signed integer `1`, and unsigned integer `1` remain three distinct keys. The
/// app adapter must classify the SDK key before constructing this value; `String(describing:)` is
/// intentionally not part of this package boundary.
public enum TuyaStructuredApplicationDPKey: Hashable, Codable, Sendable, Comparable {
    case string(String)
    case signedInteger(Int64)
    case unsignedInteger(UInt64)

    private enum Kind: String, Codable {
        case string
        case signedInteger
        case unsignedInteger
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let lhsRank = lhs.sortRank
        let rhsRank = rhs.sortRank
        guard lhsRank == rhsRank else { return lhsRank < rhsRank }

        switch (lhs, rhs) {
        case let (.string(lhsValue), .string(rhsValue)):
            return lhsValue.utf8.lexicographicallyPrecedes(rhsValue.utf8)
        case let (.signedInteger(lhsValue), .signedInteger(rhsValue)):
            return lhsValue < rhsValue
        case let (.unsignedInteger(lhsValue), .unsignedInteger(rhsValue)):
            return lhsValue < rhsValue
        default:
            return false
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .signedInteger:
            self = .signedInteger(try container.decode(Int64.self, forKey: .value))
        case .unsignedInteger:
            self = .unsignedInteger(try container.decode(UInt64.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .signedInteger(value):
            try container.encode(Kind.signedInteger, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .unsignedInteger(value):
            try container.encode(Kind.unsignedInteger, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    private var sortRank: Int {
        switch self {
        case .string: 0
        case .signedInteger: 1
        case .unsignedInteger: 2
        }
    }
}

public struct TuyaStructuredApplicationEntry: Equatable, Codable, Sendable {
    public let key: TuyaStructuredApplicationDPKey
    public let value: TuyaStructuredApplicationValue

    public init(key: TuyaStructuredApplicationDPKey, value: TuyaStructuredApplicationValue) {
        self.key = key
        self.value = value
    }
}

/// Closed recursive representation of values delivered by the Tuya SDK application callback.
///
/// Opaque bytes are deliberately absent. The accepted SDK callback currently supplies structured
/// application values, while raw FD50 bytes are unavailable under the SDK-owned BLE session.
public indirect enum TuyaStructuredApplicationValue: Equatable, Codable, Sendable {
    case null
    case bool(Bool)
    case signedInteger(Int64)
    case unsignedInteger(UInt64)
    case finiteDecimal(Decimal)
    case string(String)
    case array([Self])
    case object([TuyaStructuredApplicationEntry])

    private enum Kind: String, Codable {
        case null
        case bool
        case signedInteger
        case unsignedInteger
        case finiteDecimal
        case string
        case array
        case object
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .null:
            self = .null
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .signedInteger:
            self = .signedInteger(try container.decode(Int64.self, forKey: .value))
        case .unsignedInteger:
            self = .unsignedInteger(try container.decode(UInt64.self, forKey: .value))
        case .finiteDecimal:
            let encoded = try container.decode(String.self, forKey: .value)
            guard let decimal = Self.decimal(fromCanonical: encoded) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Finite decimal was not canonical."
                )
            }
            self = .finiteDecimal(decimal)
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .array:
            self = .array(try container.decode([Self].self, forKey: .value))
        case .object:
            self = .object(
                try container.decode([TuyaStructuredApplicationEntry].self, forKey: .value)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(Kind.null, forKey: .kind)
        case let .bool(value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .signedInteger(value):
            try container.encode(Kind.signedInteger, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .unsignedInteger(value):
            try container.encode(Kind.unsignedInteger, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .finiteDecimal(value):
            guard let canonical = Self.canonicalDecimalString(value) else {
                throw EncodingError.invalidValue(
                    value,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "Only finite decimal values can be encoded."
                    )
                )
            }
            try container.encode(Kind.finiteDecimal, forKey: .kind)
            try container.encode(canonical, forKey: .value)
        case let .string(value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .array(value):
            try container.encode(Kind.array, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .object(value):
            try container.encode(Kind.object, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    fileprivate static func canonicalDecimalString(_ value: Decimal) -> String? {
        guard !value.isNaN else { return nil }
        let string = NSDecimalNumber(decimal: value).stringValue
        guard decimal(fromCanonical: string) != nil else { return nil }
        return string
    }

    private static func decimal(fromCanonical string: String) -> Decimal? {
        guard string != "NaN",
              let decimal = Decimal(
                string: string,
                locale: Locale(identifier: "en_US_POSIX")
              ),
              !decimal.isNaN,
              NSDecimalNumber(decimal: decimal).stringValue == string else {
            return nil
        }
        return decimal
    }
}

/// One lossless, type-preserving Tuya SDK application callback observation.
///
/// The event owns no device/account identity metadata and accepts only a random pseudonymous
/// session ID. Payload strings are preserved exactly because the private source artifact must not
/// destroy legitimate protocol evidence that happens to resemble an identifier or credential.
/// Consequently, an encoded event is sensitive capture evidence and **must not be committed**.
/// A separate, explicitly derived sanitizer must produce reviewed repository-safe fixtures.
public struct TuyaStructuredApplicationEvidenceEvent: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let source: TuyaStructuredApplicationEvidenceSource
    public let interpretation: TuyaStructuredApplicationEvidenceInterpretation
    public let pseudonymousSessionID: TuyaStructuredApplicationSessionID
    public let connectionGeneration: UInt64
    public let deliverySequence: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtWallClock: Date
    public let entries: [TuyaStructuredApplicationEntry]

    /// The SDK callback exposes structured application values, never raw FD50 transport bytes.
    public let rawTransportBytesAvailable: Bool

    /// Unmapped application observations cannot authorize production telemetry semantics.
    public var authorizesProductionTelemetry: Bool { false }

    private let receivedAtWallClockUnixMilliseconds: Int64

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case source
        case interpretation
        case pseudonymousSessionID
        case connectionGeneration
        case deliverySequence
        case receivedAtUptimeNanoseconds
        case receivedAtWallClockUnixMilliseconds
        case entries
        case rawTransportBytesAvailable
    }

    public init(
        pseudonymousSessionID: TuyaStructuredApplicationSessionID,
        connectionGeneration: UInt64,
        deliverySequence: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtWallClock: Date,
        entries: [TuyaStructuredApplicationEntry]
    ) throws {
        let wallClockMilliseconds = try Self.wallClockMilliseconds(receivedAtWallClock)
        try self.init(
            pseudonymousSessionID: pseudonymousSessionID,
            connectionGeneration: connectionGeneration,
            deliverySequence: deliverySequence,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            receivedAtWallClockUnixMilliseconds: wallClockMilliseconds,
            entries: entries
        )
    }

    private init(
        pseudonymousSessionID: TuyaStructuredApplicationSessionID,
        connectionGeneration: UInt64,
        deliverySequence: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtWallClockUnixMilliseconds: Int64,
        entries: [TuyaStructuredApplicationEntry]
    ) throws {
        guard connectionGeneration > 0 else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .invalidConnectionGeneration(connectionGeneration)
        }
        guard deliverySequence > 0 else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .invalidDeliverySequence(deliverySequence)
        }
        guard receivedAtUptimeNanoseconds > 0 else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .invalidMonotonicReceipt(receivedAtUptimeNanoseconds)
        }
        guard receivedAtWallClockUnixMilliseconds > 0 else {
            throw TuyaStructuredApplicationEvidenceValidationError.invalidWallClock
        }
        guard !entries.isEmpty else {
            throw TuyaStructuredApplicationEvidenceValidationError.emptyApplicationUpdate
        }

        self.schemaVersion = Self.currentSchemaVersion
        self.source = .tuyaSDKDPUpdate
        self.interpretation = .unmappedApplicationObservation
        self.pseudonymousSessionID = pseudonymousSessionID
        self.connectionGeneration = connectionGeneration
        self.deliverySequence = deliverySequence
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.receivedAtWallClockUnixMilliseconds = receivedAtWallClockUnixMilliseconds
        self.receivedAtWallClock = Date(
            timeIntervalSince1970: Double(receivedAtWallClockUnixMilliseconds) / 1_000
        )
        self.entries = try TuyaStructuredApplicationEvidenceValidator.canonicalEntries(
            entries,
            path: "entries",
            depth: 0
        )
        self.rawTransportBytesAvailable = false
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .unsupportedSchemaVersion(schemaVersion)
        }

        let source = try container.decode(
            TuyaStructuredApplicationEvidenceSource.self,
            forKey: .source
        )
        guard source == .tuyaSDKDPUpdate else {
            throw DecodingError.dataCorruptedError(
                forKey: .source,
                in: container,
                debugDescription: "Unsupported application evidence source."
            )
        }

        let interpretation = try container.decode(
            TuyaStructuredApplicationEvidenceInterpretation.self,
            forKey: .interpretation
        )
        guard interpretation == .unmappedApplicationObservation else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .unexpectedInterpretation(interpretation)
        }

        let rawTransportBytesAvailable = try container.decode(
            Bool.self,
            forKey: .rawTransportBytesAvailable
        )
        guard !rawTransportBytesAvailable else {
            throw TuyaStructuredApplicationEvidenceValidationError.rawTransportBytesClaimed
        }

        try self.init(
            pseudonymousSessionID: container.decode(
                TuyaStructuredApplicationSessionID.self,
                forKey: .pseudonymousSessionID
            ),
            connectionGeneration: container.decode(UInt64.self, forKey: .connectionGeneration),
            deliverySequence: container.decode(UInt64.self, forKey: .deliverySequence),
            receivedAtUptimeNanoseconds: container.decode(
                UInt64.self,
                forKey: .receivedAtUptimeNanoseconds
            ),
            receivedAtWallClockUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .receivedAtWallClockUnixMilliseconds
            ),
            entries: container.decode([TuyaStructuredApplicationEntry].self, forKey: .entries)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(source, forKey: .source)
        try container.encode(interpretation, forKey: .interpretation)
        try container.encode(pseudonymousSessionID, forKey: .pseudonymousSessionID)
        try container.encode(connectionGeneration, forKey: .connectionGeneration)
        try container.encode(deliverySequence, forKey: .deliverySequence)
        try container.encode(
            receivedAtUptimeNanoseconds,
            forKey: .receivedAtUptimeNanoseconds
        )
        try container.encode(
            receivedAtWallClockUnixMilliseconds,
            forKey: .receivedAtWallClockUnixMilliseconds
        )
        try container.encode(entries, forKey: .entries)
        try container.encode(false, forKey: .rawTransportBytesAvailable)
    }

    private static func wallClockMilliseconds(_ date: Date) throws -> Int64 {
        let milliseconds = date.timeIntervalSince1970 * 1_000
        guard milliseconds.isFinite,
              milliseconds > 0,
              milliseconds > Double(Int64.min),
              milliseconds < Double(Int64.max) else {
            throw TuyaStructuredApplicationEvidenceValidationError.invalidWallClock
        }
        return Int64(milliseconds.rounded(.towardZero))
    }
}

/// Deterministic exact-byte JSON boundary for private structured application evidence.
///
/// Decoding accepts only the canonical representation produced by `encode`. This rejects unknown
/// fields, alternate number spellings, reordered arrays, duplicate wire members, and parser-
/// precedence ambiguity instead of silently normalizing evidence bytes.
/// Canonical encoding does not sanitize payload values; encoded artifacts may contain sensitive
/// SDK data and must remain outside Git until a separate sanitization/fixture derivation step.
public enum TuyaStructuredApplicationEvidenceJSON {
    /// Upper bound applied before Foundation parses untrusted evidence bytes.
    public static let maximumCanonicalEventByteCount = 1_048_576

    public static func encode(_ event: TuyaStructuredApplicationEvidenceEvent) throws -> Data {
        let data = try canonicalEncoder().encode(event)
        try validateByteLimit(data)
        return data
    }

    /// SHA-256 of the exact canonical event representation, including receipt metadata.
    public static func canonicalEventSHA256(
        _ event: TuyaStructuredApplicationEvidenceEvent
    ) throws -> String {
        sha256Hex(try encode(event))
    }

    /// SHA-256 of the canonical structured payload only.
    ///
    /// This intentionally excludes pseudonymous session identity, connection generation,
    /// delivery sequence, and timestamps so a guided-action receipt can bind repeated equivalent
    /// SDK payloads independently of callback chronology. It remains evidence identity, not a DP
    /// interpretation or telemetry-authority grant.
    public static func canonicalPayloadSHA256(
        _ event: TuyaStructuredApplicationEvidenceEvent
    ) throws -> String {
        // A payload receipt is issued only for an event that can itself cross the canonical import
        // boundary. This prevents construction of an oversized, hashable but non-importable event.
        _ = try encode(event)
        return sha256Hex(
            try canonicalEncoder().encode(CanonicalPayload(entries: event.entries))
        )
    }

    public static func decode(_ data: Data) throws -> TuyaStructuredApplicationEvidenceEvent {
        try validateByteLimit(data)
        if let duplicate = PassiveBluetoothStrictJSON.duplicateTopLevelObjectKey(in: data) {
            throw TuyaStructuredApplicationEvidenceValidationError.duplicateWireField(duplicate)
        }

        let event: TuyaStructuredApplicationEvidenceEvent
        do {
            event = try JSONDecoder().decode(
                TuyaStructuredApplicationEvidenceEvent.self,
                from: data
            )
        } catch let error as TuyaStructuredApplicationEvidenceValidationError {
            throw error
        } catch {
            throw TuyaStructuredApplicationEvidenceValidationError.malformedJSON
        }

        guard try encode(event) == data else {
            throw TuyaStructuredApplicationEvidenceValidationError.nonCanonicalJSON
        }
        return event
    }

    private struct CanonicalPayload: Encodable {
        let entries: [TuyaStructuredApplicationEntry]
    }

    private static func canonicalEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func validateByteLimit(_ data: Data) throws {
        guard data.count <= maximumCanonicalEventByteCount else {
            throw TuyaStructuredApplicationEvidenceValidationError.inputByteLimitExceeded(
                byteCount: data.count,
                maximum: maximumCanonicalEventByteCount
            )
        }
    }
}

/// Cross-event validator for a single exported session timeline.
///
/// Monotonic uptime is the ordering authority. Wall time remains useful human evidence but is not
/// used for replay decisions because users and the OS can adjust wall clock during a session.
public enum TuyaStructuredApplicationEvidenceChronology {
    public static func validate(
        _ events: [TuyaStructuredApplicationEvidenceEvent]
    ) throws {
        guard let first = events.first else { return }

        var previous = first
        for (index, event) in events.enumerated().dropFirst() {
            guard event.pseudonymousSessionID == first.pseudonymousSessionID else {
                throw TuyaStructuredApplicationEvidenceValidationError
                    .mixedPseudonymousSessions(eventIndex: index)
            }
            guard event.connectionGeneration >= previous.connectionGeneration else {
                throw TuyaStructuredApplicationEvidenceValidationError
                    .connectionGenerationRegressed(eventIndex: index)
            }
            guard event.receivedAtUptimeNanoseconds >= previous.receivedAtUptimeNanoseconds else {
                throw TuyaStructuredApplicationEvidenceValidationError
                    .duplicateOrReplayedEvent(eventIndex: index)
            }
            if event.connectionGeneration == previous.connectionGeneration {
                guard event.deliverySequence > previous.deliverySequence else {
                    throw TuyaStructuredApplicationEvidenceValidationError
                        .duplicateOrReplayedEvent(eventIndex: index)
                }
            }
            previous = event
        }
    }
}

private enum TuyaStructuredApplicationEvidenceValidator {
    private static let maximumDepth = 24
    private static let maximumCollectionCount = 4_096
    private static let maximumKeyUTF8Count = 128
    private static let maximumStringUTF8Count = 4_096

    static func canonicalEntries(
        _ entries: [TuyaStructuredApplicationEntry],
        path: String,
        depth: Int
    ) throws -> [TuyaStructuredApplicationEntry] {
        guard depth <= maximumDepth else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .nestingLimitExceeded(path: path)
        }
        guard entries.count <= maximumCollectionCount else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .collectionLimitExceeded(path: path)
        }

        var seen = Set<TuyaStructuredApplicationDPKey>()
        var canonical = [TuyaStructuredApplicationEntry]()
        canonical.reserveCapacity(entries.count)

        for (index, entry) in entries.enumerated() {
            let entryPath = "\(path)[\(index)]"
            try validate(entry.key, path: "\(entryPath).key")
            guard seen.insert(entry.key).inserted else {
                throw TuyaStructuredApplicationEvidenceValidationError
                    .duplicateKey(path: "\(entryPath).key")
            }
            canonical.append(
                TuyaStructuredApplicationEntry(
                    key: entry.key,
                    value: try canonicalValue(
                        entry.value,
                        path: "\(entryPath).value",
                        depth: depth + 1
                    )
                )
            )
        }

        return canonical.sorted { $0.key < $1.key }
    }

    private static func canonicalValue(
        _ value: TuyaStructuredApplicationValue,
        path: String,
        depth: Int
    ) throws -> TuyaStructuredApplicationValue {
        guard depth <= maximumDepth else {
            throw TuyaStructuredApplicationEvidenceValidationError
                .nestingLimitExceeded(path: path)
        }

        switch value {
        case .null, .bool, .signedInteger, .unsignedInteger:
            return value
        case let .finiteDecimal(decimal):
            guard TuyaStructuredApplicationValue.canonicalDecimalString(decimal) != nil else {
                throw TuyaStructuredApplicationEvidenceValidationError
                    .nonFiniteDecimal(path: path)
            }
            return value
        case let .string(string):
            guard string.utf8.count <= maximumStringUTF8Count else {
                throw TuyaStructuredApplicationEvidenceValidationError
                    .collectionLimitExceeded(path: path)
            }
            return value
        case let .array(values):
            guard values.count <= maximumCollectionCount else {
                throw TuyaStructuredApplicationEvidenceValidationError
                    .collectionLimitExceeded(path: path)
            }
            return .array(
                try values.enumerated().map { index, value in
                    try canonicalValue(value, path: "\(path)[\(index)]", depth: depth + 1)
                }
            )
        case let .object(entries):
            return .object(
                try canonicalEntries(entries, path: "\(path).object", depth: depth + 1)
            )
        }
    }

    private static func validate(
        _ key: TuyaStructuredApplicationDPKey,
        path: String
    ) throws {
        guard case let .string(value) = key else { return }
        guard !value.isEmpty,
              value.utf8.count <= maximumKeyUTF8Count else {
            throw TuyaStructuredApplicationEvidenceValidationError.invalidKey(path: path)
        }
    }
}
