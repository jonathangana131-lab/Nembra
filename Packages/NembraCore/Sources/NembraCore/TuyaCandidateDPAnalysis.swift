/// Conservative structural parsing for Tuya data-point payload candidates.
///
/// This layer does not decide whether a `TuyaCandidateLogicalPacket.data` field
/// actually contains DPs, and it assigns no AOVOPRO ES80 meaning to any ID or
/// value. The caller must select the candidate length-field width explicitly.
public enum TuyaCandidateDPAnalysisError: Error, Equatable, Sendable {
    case invalidMaximumDatapointCount
    case invalidMaximumValueBytes
    case truncatedHeader(offset: Int, requiredBytes: Int, remainingBytes: Int)
    case declaredValueLengthExceedsPolicy(offset: Int, declared: Int, maximum: Int)
    case truncatedValue(offset: Int, declared: Int, remainingBytes: Int)
    case datapointCountExceedsPolicy(maximum: Int)
}

/// Tuya public documentation uses different DP length-field widths in different
/// Bluetooth protocol generations. Nembra therefore requires the caller to
/// choose a candidate instead of silently auto-detecting one.
public enum TuyaCandidateDPDataLengthWidth: Equatable, Sendable {
    case oneByte
    case twoByteBigEndian

    fileprivate var headerByteCount: Int {
        switch self {
        case .oneByte: 3
        case .twoByteBigEndian: 4
        }
    }
}

/// Generic Tuya DP type identifiers from public Tuya documentation.
/// Recognition of a type does not establish product-specific field semantics.
public enum TuyaCandidateDPKnownType: UInt8, Equatable, Sendable {
    case raw = 0x00
    case boolean = 0x01
    case value = 0x02
    case string = 0x03
    case enumeration = 0x04
    case bitmap = 0x05
}

/// Structural type/length observation. Unexpected lengths are preserved as
/// evidence instead of causing the entire candidate payload to be rewritten or
/// discarded until it happens to fit a preferred interpretation.
public enum TuyaCandidateDPShapeFinding: Equatable, Sendable {
    case unknownType(rawType: UInt8)
    case variableLengthKnownType(
        TuyaCandidateDPKnownType,
        allowedLengthRange: ClosedRange<Int>
    )
    case fixedLengthKnownType(TuyaCandidateDPKnownType, allowedLengths: [Int])
    case unexpectedKnownTypeLength(
        TuyaCandidateDPKnownType,
        allowedLengths: [Int],
        actualLength: Int
    )
    case unexpectedVariableKnownTypeLength(
        TuyaCandidateDPKnownType,
        allowedLengthRange: ClosedRange<Int>,
        actualLength: Int
    )
}

/// Caller-owned resource bounds plus one explicit public-family framing
/// hypothesis. These are analysis limits, not ES80 protocol defaults.
public struct TuyaCandidateDPParserPolicy: Equatable, Sendable {
    public let dataLengthWidth: TuyaCandidateDPDataLengthWidth
    public let maximumDatapointCount: Int
    public let maximumValueBytes: Int

    public init(
        dataLengthWidth: TuyaCandidateDPDataLengthWidth,
        maximumDatapointCount: Int,
        maximumValueBytes: Int
    ) throws {
        guard maximumDatapointCount > 0 else {
            throw TuyaCandidateDPAnalysisError.invalidMaximumDatapointCount
        }
        guard maximumValueBytes > 0 else {
            throw TuyaCandidateDPAnalysisError.invalidMaximumValueBytes
        }
        self.dataLengthWidth = dataLengthWidth
        self.maximumDatapointCount = maximumDatapointCount
        self.maximumValueBytes = maximumValueBytes
    }
}

/// One ordered DP-shaped unit. Raw bytes and offsets remain available so an
/// offline correlation tool can refer back to exact evidence without assigning
/// a product meaning to the field.
public struct TuyaCandidateDPRecord: Equatable, Sendable {
    public let headerByteOffset: Int
    public let valueByteOffset: Int
    public let endByteOffsetExclusive: Int
    public let identifier: UInt8
    public let rawType: UInt8
    public let knownType: TuyaCandidateDPKnownType?
    public let declaredValueLength: Int
    public let valueBytes: [UInt8]
    public let shapeFinding: TuyaCandidateDPShapeFinding

    /// Generic boolean projection only. A value other than exactly 0 or 1 stays
    /// unavailable rather than being coerced into a Boolean meaning.
    public var candidateBooleanValue: Bool? {
        guard knownType == .boolean, valueBytes.count == 1 else { return nil }
        switch valueBytes[0] {
        case 0: return false
        case 1: return true
        default: return nil
        }
    }

    /// Generic unsigned big-endian magnitude for fixed-size public Tuya scalar
    /// shapes. This deliberately does not claim signedness, unit, scale, or ES80
    /// field meaning. Raw/string DPs are never converted here.
    public var candidateUnsignedBigEndianMagnitude: UInt32? {
        switch knownType {
        case .boolean:
            guard valueBytes.count == 1, valueBytes[0] <= 1 else { return nil }
        case .value:
            guard valueBytes.count == 4 else { return nil }
        case .enumeration:
            guard valueBytes.count == 1 else { return nil }
        case .bitmap:
            guard [1, 2, 4].contains(valueBytes.count) else { return nil }
        case .raw, .string, .none:
            return nil
        }

        var result: UInt32 = 0
        for byte in valueBytes {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }
}

public struct TuyaCandidateDPPayload: Equatable, Sendable {
    public let sourceByteCount: Int
    public let records: [TuyaCandidateDPRecord]
}

public enum TuyaCandidateDPPayloadParser {
    /// Parses exactly the caller-supplied byte slice as concatenated DP-shaped
    /// units. Empty input is a valid empty candidate payload.
    public static func parse(
        _ bytes: [UInt8],
        policy: TuyaCandidateDPParserPolicy
    ) throws -> TuyaCandidateDPPayload {
        var cursor = 0
        var records: [TuyaCandidateDPRecord] = []
        records.reserveCapacity(min(policy.maximumDatapointCount, bytes.count / 3))

        while cursor < bytes.count {
            guard records.count < policy.maximumDatapointCount else {
                throw TuyaCandidateDPAnalysisError.datapointCountExceedsPolicy(
                    maximum: policy.maximumDatapointCount
                )
            }

            let headerOffset = cursor
            let headerBytes = policy.dataLengthWidth.headerByteCount
            let remainingHeaderBytes = bytes.count - cursor
            guard remainingHeaderBytes >= headerBytes else {
                throw TuyaCandidateDPAnalysisError.truncatedHeader(
                    offset: headerOffset,
                    requiredBytes: headerBytes,
                    remainingBytes: remainingHeaderBytes
                )
            }

            let identifier = bytes[cursor]
            let rawType = bytes[cursor + 1]
            let declaredLength: Int
            switch policy.dataLengthWidth {
            case .oneByte:
                declaredLength = Int(bytes[cursor + 2])
            case .twoByteBigEndian:
                declaredLength = (Int(bytes[cursor + 2]) << 8) | Int(bytes[cursor + 3])
            }
            cursor += headerBytes

            guard declaredLength <= policy.maximumValueBytes else {
                throw TuyaCandidateDPAnalysisError.declaredValueLengthExceedsPolicy(
                    offset: headerOffset,
                    declared: declaredLength,
                    maximum: policy.maximumValueBytes
                )
            }

            let remainingValueBytes = bytes.count - cursor
            guard remainingValueBytes >= declaredLength else {
                throw TuyaCandidateDPAnalysisError.truncatedValue(
                    offset: headerOffset,
                    declared: declaredLength,
                    remainingBytes: remainingValueBytes
                )
            }

            let valueOffset = cursor
            let endOffset = cursor + declaredLength
            let value = Array(bytes[cursor..<endOffset])
            cursor = endOffset
            let knownType = TuyaCandidateDPKnownType(rawValue: rawType)

            records.append(
                TuyaCandidateDPRecord(
                    headerByteOffset: headerOffset,
                    valueByteOffset: valueOffset,
                    endByteOffsetExclusive: endOffset,
                    identifier: identifier,
                    rawType: rawType,
                    knownType: knownType,
                    declaredValueLength: declaredLength,
                    valueBytes: value,
                    shapeFinding: shapeFinding(for: knownType, rawType: rawType, length: declaredLength)
                )
            )
        }

        return TuyaCandidateDPPayload(sourceByteCount: bytes.count, records: records)
    }

    /// Convenience bridge from #219's already CRC-validated logical candidate.
    /// The caller is still responsible for establishing that this packet's data
    /// field should be tested as a DP payload; `code` is intentionally ignored.
    public static func parseData(
        of packet: TuyaCandidateLogicalPacket,
        policy: TuyaCandidateDPParserPolicy
    ) throws -> TuyaCandidateDPPayload {
        try parse(packet.data, policy: policy)
    }

    private static func shapeFinding(
        for knownType: TuyaCandidateDPKnownType?,
        rawType: UInt8,
        length: Int
    ) -> TuyaCandidateDPShapeFinding {
        guard let knownType else {
            return .unknownType(rawType: rawType)
        }

        switch knownType {
        case .raw:
            let allowed = 1...255
            guard allowed.contains(length) else {
                return .unexpectedVariableKnownTypeLength(
                    knownType,
                    allowedLengthRange: allowed,
                    actualLength: length
                )
            }
            return .variableLengthKnownType(knownType, allowedLengthRange: allowed)
        case .string:
            let allowed = 0...255
            guard allowed.contains(length) else {
                return .unexpectedVariableKnownTypeLength(
                    knownType,
                    allowedLengthRange: allowed,
                    actualLength: length
                )
            }
            return .variableLengthKnownType(knownType, allowedLengthRange: allowed)
        case .boolean, .enumeration:
            return fixedLengthFinding(for: knownType, allowed: [1], actual: length)
        case .value:
            return fixedLengthFinding(for: knownType, allowed: [4], actual: length)
        case .bitmap:
            // Public Tuya documents are not perfectly uniform here; 1/2/4-byte
            // bitmap shapes are retained as the broader documented family.
            return fixedLengthFinding(for: knownType, allowed: [1, 2, 4], actual: length)
        }
    }

    private static func fixedLengthFinding(
        for knownType: TuyaCandidateDPKnownType,
        allowed: [Int],
        actual: Int
    ) -> TuyaCandidateDPShapeFinding {
        guard allowed.contains(actual) else {
            return .unexpectedKnownTypeLength(
                knownType,
                allowedLengths: allowed,
                actualLength: actual
            )
        }
        return .fixedLengthKnownType(knownType, allowedLengths: allowed)
    }
}
