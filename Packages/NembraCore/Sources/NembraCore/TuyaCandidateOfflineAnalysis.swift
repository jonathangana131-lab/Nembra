/// Conservative offline recognition for a publicly reverse-engineered Tuya BLE
/// framing family. None of these types assert that a physical AOVOPRO ES80 uses
/// this family. Callers must keep raw capture evidence and provenance separately.
public enum TuyaCandidateOfflineAnalysisError: Error, Equatable, Sendable {
    case emptyStreamIdentityField
    case emptyFragment
    case malformedVarint
    case varintOverflow
    case firstFragmentRequired
    case unexpectedPacketIndex(expected: UInt64, actual: UInt64)
    case invalidMaximumEncryptedMessageBytes
    case invalidMaximumFragmentCount
    case declaredLengthZero
    case declaredLengthExceedsPolicy(declared: UInt64, maximum: Int)
    case fragmentCountExceedsPolicy(maximum: Int)
    case streamChanged
    case continuityGenerationChanged
    case nonMonotonicReceiptUptime
    case assembledLengthExceeded(declared: Int, actual: Int)
    case messageAlreadyComplete
    case encryptedEnvelopeTooShort
    case encryptedCiphertextNotBlockAligned
    case logicalPacketTooShort
    case logicalPacketLengthMismatch(expected: Int, actual: Int)
    case logicalPacketPaddingLengthMismatch(expected: Int, actual: Int)
    case nonZeroLogicalPacketPadding
    case logicalPacketCRCFailed(expected: UInt16, actual: UInt16)
}

/// Exact caller-supplied GATT/value-stream identity. Nembra intentionally does
/// not normalize these strings here because normalization could merge distinct
/// raw evidence before physical identity semantics are verified.
public struct TuyaCandidateValueStreamIdentity: Hashable, Sendable {
    public let peripheralIdentifier: String
    public let serviceIdentifier: String
    public let characteristicIdentifier: String

    public init(
        peripheralIdentifier: String,
        serviceIdentifier: String,
        characteristicIdentifier: String
    ) throws {
        guard !peripheralIdentifier.isEmpty,
              !serviceIdentifier.isEmpty,
              !characteristicIdentifier.isEmpty else {
            throw TuyaCandidateOfflineAnalysisError.emptyStreamIdentityField
        }
        self.peripheralIdentifier = peripheralIdentifier
        self.serviceIdentifier = serviceIdentifier
        self.characteristicIdentifier = characteristicIdentifier
    }
}

/// One immutable opaque CoreBluetooth value observation projected into offline
/// analysis. `continuityGeneration` must be advanced by the capture layer across
/// any gap that breaks byte continuity; this analyzer never guesses recovery.
public struct TuyaCandidateFragmentObservation: Equatable, Sendable {
    public let streamIdentity: TuyaCandidateValueStreamIdentity
    public let continuityGeneration: UInt64
    public let receiptUptimeNanoseconds: UInt64
    public let bytes: [UInt8]

    public init(
        streamIdentity: TuyaCandidateValueStreamIdentity,
        continuityGeneration: UInt64,
        receiptUptimeNanoseconds: UInt64,
        bytes: [UInt8]
    ) throws {
        guard !bytes.isEmpty else {
            throw TuyaCandidateOfflineAnalysisError.emptyFragment
        }
        self.streamIdentity = streamIdentity
        self.continuityGeneration = continuityGeneration
        self.receiptUptimeNanoseconds = receiptUptimeNanoseconds
        self.bytes = bytes
    }
}

/// Caller-injected resource bounds. These are analysis safety limits, not ES80
/// protocol or hardware claims, so no guessed device-specific defaults exist.
public struct TuyaCandidateFragmentReassemblyPolicy: Equatable, Sendable {
    public let maximumEncryptedMessageBytes: Int
    public let maximumFragmentCount: Int

    public init(maximumEncryptedMessageBytes: Int, maximumFragmentCount: Int) throws {
        guard maximumEncryptedMessageBytes > 0 else {
            throw TuyaCandidateOfflineAnalysisError.invalidMaximumEncryptedMessageBytes
        }
        guard maximumFragmentCount > 0 else {
            throw TuyaCandidateOfflineAnalysisError.invalidMaximumFragmentCount
        }
        self.maximumEncryptedMessageBytes = maximumEncryptedMessageBytes
        self.maximumFragmentCount = maximumFragmentCount
    }
}

public struct TuyaCandidateReassembledMessage: Equatable, Sendable {
    public let streamIdentity: TuyaCandidateValueStreamIdentity
    public let continuityGeneration: UInt64
    public let protocolVersionByte: UInt8
    public let protocolVersionHighNibble: UInt8
    public let encryptedBytes: [UInt8]
    public let fragmentCount: Int
    public let firstReceiptUptimeNanoseconds: UInt64
    public let lastReceiptUptimeNanoseconds: UInt64
}

public enum TuyaCandidateFragmentReassemblyProgress: Equatable, Sendable {
    case awaitingMore(nextPacketIndex: UInt64, remainingBytes: Int)
    case complete(TuyaCandidateReassembledMessage)
}

/// Stateful reconstruction for the candidate family documented by Nembra's
/// public Tuya research. A single instance is permanently bound to one exact
/// stream and one continuity generation after its first fragment.
public struct TuyaCandidateFragmentReassembler: Sendable {
    private let policy: TuyaCandidateFragmentReassemblyPolicy
    private var streamIdentity: TuyaCandidateValueStreamIdentity?
    private var continuityGeneration: UInt64?
    private var protocolVersionByte: UInt8?
    private var declaredLength: Int?
    private var encryptedBytes: [UInt8] = []
    private var nextPacketIndex: UInt64 = 0
    private var fragmentCount: Int = 0
    private var firstReceiptUptimeNanoseconds: UInt64?
    private var lastReceiptUptimeNanoseconds: UInt64?
    private var isComplete = false

    public init(policy: TuyaCandidateFragmentReassemblyPolicy) {
        self.policy = policy
    }

    public mutating func ingest(
        _ observation: TuyaCandidateFragmentObservation
    ) throws -> TuyaCandidateFragmentReassemblyProgress {
        guard !isComplete else {
            throw TuyaCandidateOfflineAnalysisError.messageAlreadyComplete
        }

        if let streamIdentity, streamIdentity != observation.streamIdentity {
            throw TuyaCandidateOfflineAnalysisError.streamChanged
        }
        if let continuityGeneration, continuityGeneration != observation.continuityGeneration {
            throw TuyaCandidateOfflineAnalysisError.continuityGenerationChanged
        }
        if let lastReceiptUptimeNanoseconds,
           observation.receiptUptimeNanoseconds <= lastReceiptUptimeNanoseconds {
            throw TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptUptime
        }
        guard fragmentCount < policy.maximumFragmentCount else {
            throw TuyaCandidateOfflineAnalysisError.fragmentCountExceedsPolicy(
                maximum: policy.maximumFragmentCount
            )
        }

        var cursor = 0
        let packetIndex = try Self.decodeCandidateVarint(observation.bytes, cursor: &cursor)
        guard packetIndex == nextPacketIndex else {
            throw TuyaCandidateOfflineAnalysisError.unexpectedPacketIndex(
                expected: nextPacketIndex,
                actual: packetIndex
            )
        }

        var firstDeclaredLength: Int?
        var firstProtocolVersionByte: UInt8?
        if packetIndex == 0 {
            guard streamIdentity == nil else {
                throw TuyaCandidateOfflineAnalysisError.firstFragmentRequired
            }
            let rawDeclaredLength = try Self.decodeCandidateVarint(observation.bytes, cursor: &cursor)
            guard rawDeclaredLength > 0 else {
                throw TuyaCandidateOfflineAnalysisError.declaredLengthZero
            }
            guard rawDeclaredLength <= UInt64(policy.maximumEncryptedMessageBytes) else {
                throw TuyaCandidateOfflineAnalysisError.declaredLengthExceedsPolicy(
                    declared: rawDeclaredLength,
                    maximum: policy.maximumEncryptedMessageBytes
                )
            }
            guard cursor < observation.bytes.count else {
                throw TuyaCandidateOfflineAnalysisError.malformedVarint
            }
            firstDeclaredLength = Int(rawDeclaredLength)
            firstProtocolVersionByte = observation.bytes[cursor]
            cursor += 1
        } else {
            guard streamIdentity != nil, declaredLength != nil, protocolVersionByte != nil else {
                throw TuyaCandidateOfflineAnalysisError.firstFragmentRequired
            }
        }

        let payload = Array(observation.bytes[cursor...])
        let targetLength = firstDeclaredLength ?? declaredLength!
        let newLength = encryptedBytes.count + payload.count
        guard newLength <= targetLength else {
            throw TuyaCandidateOfflineAnalysisError.assembledLengthExceeded(
                declared: targetLength,
                actual: newLength
            )
        }

        // Commit only after all validation above succeeds so rejection is atomic.
        if packetIndex == 0 {
            streamIdentity = observation.streamIdentity
            continuityGeneration = observation.continuityGeneration
            declaredLength = firstDeclaredLength
            protocolVersionByte = firstProtocolVersionByte
            firstReceiptUptimeNanoseconds = observation.receiptUptimeNanoseconds
        }
        encryptedBytes.append(contentsOf: payload)
        fragmentCount += 1
        nextPacketIndex += 1
        lastReceiptUptimeNanoseconds = observation.receiptUptimeNanoseconds

        if encryptedBytes.count == targetLength {
            isComplete = true
            let versionByte = protocolVersionByte!
            let message = TuyaCandidateReassembledMessage(
                streamIdentity: streamIdentity!,
                continuityGeneration: continuityGeneration!,
                protocolVersionByte: versionByte,
                protocolVersionHighNibble: versionByte >> 4,
                encryptedBytes: encryptedBytes,
                fragmentCount: fragmentCount,
                firstReceiptUptimeNanoseconds: firstReceiptUptimeNanoseconds!,
                lastReceiptUptimeNanoseconds: lastReceiptUptimeNanoseconds!
            )
            return .complete(message)
        }

        return .awaitingMore(
            nextPacketIndex: nextPacketIndex,
            remainingBytes: targetLength - encryptedBytes.count
        )
    }

    /// Candidate varint format used by the public implementations currently
    /// recorded in Nembra research: low 7 bits first, high bit means continue.
    /// The stricter reference receiver rejects encodings longer than four bytes;
    /// mirror that fail-closed bound instead of accepting a generic wider varint.
    public static func decodeCandidateVarint(
        _ bytes: [UInt8],
        cursor: inout Int
    ) throws -> UInt64 {
        let initialCursor = cursor
        guard initialCursor >= 0 else {
            throw TuyaCandidateOfflineAnalysisError.malformedVarint
        }

        var position = cursor
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var count = 0

        while count < 4 {
            guard position < bytes.count else {
                cursor = initialCursor
                throw TuyaCandidateOfflineAnalysisError.malformedVarint
            }
            let byte = bytes[position]
            position += 1
            count += 1

            let payload = UInt64(byte & 0x7F)
            result |= payload << shift

            if byte & 0x80 == 0 {
                cursor = position
                return result
            }
            shift += 7
        }

        cursor = initialCursor
        throw TuyaCandidateOfflineAnalysisError.varintOverflow
    }
}

/// Structural inspection only. It does not decrypt, authenticate, select a key,
/// or imply that the observed stream actually belongs to this Tuya family.
public struct TuyaCandidateEncryptedEnvelope: Equatable, Sendable {
    public let securityFlag: UInt8
    public let initializationVector: [UInt8]
    public let ciphertext: [UInt8]

    public static func inspect(_ bytes: [UInt8]) throws -> Self {
        // 1-byte security flag + 16-byte IV + at least one 16-byte CBC block.
        guard bytes.count >= 33 else {
            throw TuyaCandidateOfflineAnalysisError.encryptedEnvelopeTooShort
        }
        let ciphertextCount = bytes.count - 17
        guard ciphertextCount % 16 == 0 else {
            throw TuyaCandidateOfflineAnalysisError.encryptedCiphertextNotBlockAligned
        }
        return Self(
            securityFlag: bytes[0],
            initializationVector: Array(bytes[1..<17]),
            ciphertext: Array(bytes[17...])
        )
    }
}

public enum TuyaCandidateLogicalPaddingPolicy: Equatable, Sendable {
    /// Caller supplies exactly header + data + CRC bytes.
    case exact
    /// Caller supplies the public-family zero padding used before AES-CBC.
    case zeroPaddedTo16ByteBoundary
}

/// Decoded logical packet for the public candidate family only. Command `code`
/// and `data` remain opaque; this type assigns no ES80 DP or telemetry semantics.
public struct TuyaCandidateLogicalPacket: Equatable, Sendable {
    public let sequenceNumber: UInt32
    public let responseTo: UInt32
    public let code: UInt16
    public let data: [UInt8]
    public let crc16: UInt16
    public let paddingByteCount: Int

    public static func parse(
        _ bytes: [UInt8],
        paddingPolicy: TuyaCandidateLogicalPaddingPolicy
    ) throws -> Self {
        guard bytes.count >= 14 else {
            throw TuyaCandidateOfflineAnalysisError.logicalPacketTooShort
        }

        let sequenceNumber = readBE32(bytes, at: 0)
        let responseTo = readBE32(bytes, at: 4)
        let code = readBE16(bytes, at: 8)
        let dataLength = Int(readBE16(bytes, at: 10))
        let rawLength = 12 + dataLength + 2
        guard rawLength >= 14 else {
            throw TuyaCandidateOfflineAnalysisError.logicalPacketTooShort
        }

        let expectedTotalLength: Int
        switch paddingPolicy {
        case .exact:
            expectedTotalLength = rawLength
            guard bytes.count == expectedTotalLength else {
                throw TuyaCandidateOfflineAnalysisError.logicalPacketLengthMismatch(
                    expected: expectedTotalLength,
                    actual: bytes.count
                )
            }
        case .zeroPaddedTo16ByteBoundary:
            let remainder = rawLength % 16
            expectedTotalLength = remainder == 0 ? rawLength : rawLength + (16 - remainder)
            guard bytes.count == expectedTotalLength else {
                throw TuyaCandidateOfflineAnalysisError.logicalPacketPaddingLengthMismatch(
                    expected: expectedTotalLength,
                    actual: bytes.count
                )
            }
            if rawLength < bytes.count,
               bytes[rawLength...].contains(where: { $0 != 0 }) {
                throw TuyaCandidateOfflineAnalysisError.nonZeroLogicalPacketPadding
            }
        }

        let crcOffset = 12 + dataLength
        let expectedCRC = crc16A001(Array(bytes[0..<crcOffset]))
        let actualCRC = readBE16(bytes, at: crcOffset)
        guard expectedCRC == actualCRC else {
            throw TuyaCandidateOfflineAnalysisError.logicalPacketCRCFailed(
                expected: expectedCRC,
                actual: actualCRC
            )
        }

        return Self(
            sequenceNumber: sequenceNumber,
            responseTo: responseTo,
            code: code,
            data: Array(bytes[12..<crcOffset]),
            crc16: actualCRC,
            paddingByteCount: bytes.count - rawLength
        )
    }

    /// CRC16 used by the public candidate family: initial 0xFFFF, reflected
    /// polynomial 0xA001. This is not promoted to ES80 truth by this function.
    public static func crc16A001(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                let carry = crc & 1
                crc >>= 1
                if carry != 0 {
                    crc ^= 0xA001
                }
            }
        }
        return crc
    }

    private static func readBE16(_ bytes: [UInt8], at index: Int) -> UInt16 {
        (UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1])
    }

    private static func readBE32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        (UInt32(bytes[index]) << 24)
            | (UInt32(bytes[index + 1]) << 16)
            | (UInt32(bytes[index + 2]) << 8)
            | UInt32(bytes[index + 3])
    }
}
