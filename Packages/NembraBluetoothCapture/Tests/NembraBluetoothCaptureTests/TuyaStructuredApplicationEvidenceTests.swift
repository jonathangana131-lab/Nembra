import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Typed Tuya SDK application evidence")
struct TuyaStructuredApplicationEvidenceTests {
    private let sessionID: TuyaStructuredApplicationSessionID
    private let receivedAt = Date(timeIntervalSince1970: 1_776_666_666.123)

    init() throws {
        sessionID = try TuyaStructuredApplicationSessionID(
            pseudonymousUUID: UUID(uuidString: "01234567-89ab-4def-8123-456789abcdef")!
        )
    }

    @Test("canonical JSON round-trips nested typed values without claiming transport bytes")
    func canonicalRoundTripPreservesNestedTypesAndAuthorityBoundary() throws {
        let event = try makeEvent(
            entries: [
                .init(key: .signedInteger(2), value: .null),
                .init(key: .string("switch"), value: .bool(true)),
                .init(key: .unsignedInteger(4), value: .signedInteger(-17)),
                .init(key: .string("counter"), value: .unsignedInteger(UInt64.max)),
                .init(key: .string("ratio"), value: .finiteDecimal(decimal("12.375"))),
                .init(key: .string("label"), value: .string("eco")),
                .init(
                    key: .string("nested"),
                    value: .array([
                        .bool(false),
                        .object([
                            .init(key: .string("status"), value: .string("ready")),
                            .init(key: .signedInteger(-1), value: .signedInteger(3)),
                        ]),
                    ])
                ),
            ]
        )

        let data = try TuyaStructuredApplicationEvidenceJSON.encode(event)
        let decoded = try TuyaStructuredApplicationEvidenceJSON.decode(data)

        #expect(decoded == event)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.source == .tuyaSDKDPUpdate)
        #expect(decoded.interpretation == .unmappedApplicationObservation)
        #expect(decoded.pseudonymousSessionID == sessionID)
        #expect(decoded.connectionGeneration == 1)
        #expect(decoded.deliverySequence == 1)
        #expect(decoded.receivedAtUptimeNanoseconds == 5_000_000_000)
        #expect(decoded.receivedAtWallClock == receivedAt)
        #expect(decoded.rawTransportBytesAvailable == false)
        #expect(decoded.authorizesProductionTelemetry == false)

        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""rawTransportBytesAvailable":false"#))
        #expect(text.contains(#""interpretation":"unmappedApplicationObservation""#))
        #expect(!text.contains("base64"))
        #expect(!text.contains("telemetryValue"))
    }

    @Test("entry and nested object order normalize to identical canonical bytes")
    func orderingIsDeterministic() throws {
        let ascendingObject: [TuyaStructuredApplicationEntry] = [
            .init(key: .string("a"), value: .signedInteger(1)),
            .init(key: .string("z"), value: .signedInteger(2)),
        ]
        let ascending = try makeEvent(entries: [
            .init(key: .string("a"), value: .object(ascendingObject)),
            .init(key: .string("z"), value: .bool(true)),
            .init(key: .signedInteger(1), value: .string("signed")),
            .init(key: .unsignedInteger(1), value: .string("unsigned")),
        ])
        let descending = try makeEvent(entries: [
            .init(key: .unsignedInteger(1), value: .string("unsigned")),
            .init(key: .signedInteger(1), value: .string("signed")),
            .init(key: .string("z"), value: .bool(true)),
            .init(key: .string("a"), value: .object(ascendingObject.reversed())),
        ])

        #expect(ascending == descending)
        #expect(
            try TuyaStructuredApplicationEvidenceJSON.encode(ascending) ==
                TuyaStructuredApplicationEvidenceJSON.encode(descending)
        )
    }

    @Test("canonical event and payload digests bind the intended exact byte domains")
    func canonicalDigestsSeparateReceiptMetadataFromPayloadIdentity() throws {
        let entries: [TuyaStructuredApplicationEntry] = [
            .init(key: .string("mode"), value: .string("eco")),
            .init(key: .signedInteger(7), value: .unsignedInteger(42)),
        ]
        let event = try makeEvent(entries: entries)
        let otherSession = try TuyaStructuredApplicationSessionID(
            pseudonymousUUID: UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        )
        let metadataVariant = try makeEvent(
            session: otherSession,
            generation: 2,
            sequence: 9,
            uptime: 9_000_000_000,
            wallClock: Date(timeIntervalSince1970: 1_776_666_999),
            entries: Array(entries.reversed())
        )

        let eventBytes = try TuyaStructuredApplicationEvidenceJSON.encode(event)
        #expect(
            try TuyaStructuredApplicationEvidenceJSON.canonicalEventSHA256(event) ==
                sha256Hex(eventBytes)
        )
        #expect(
            try TuyaStructuredApplicationEvidenceJSON.canonicalEventSHA256(event) !=
                TuyaStructuredApplicationEvidenceJSON.canonicalEventSHA256(metadataVariant)
        )

        let payloadEncoder = JSONEncoder()
        payloadEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payloadBytes = try payloadEncoder.encode(CanonicalPayload(entries: event.entries))
        #expect(
            try TuyaStructuredApplicationEvidenceJSON.canonicalPayloadSHA256(event) ==
                sha256Hex(payloadBytes)
        )
        #expect(
            try TuyaStructuredApplicationEvidenceJSON.canonicalPayloadSHA256(event) ==
                TuyaStructuredApplicationEvidenceJSON.canonicalPayloadSHA256(metadataVariant)
        )
    }

    @Test("DP keys and values preserve string, signed integer, unsigned integer, bool, and decimal distinctions")
    func keyAndValueTypesRemainDistinct() throws {
        let event = try makeEvent(entries: [
            .init(key: .string("1"), value: .string("1")),
            .init(key: .signedInteger(1), value: .signedInteger(1)),
            .init(key: .unsignedInteger(1), value: .unsignedInteger(UInt64.max)),
            .init(key: .string("bool"), value: .bool(true)),
            .init(key: .string("decimal"), value: .finiteDecimal(decimal("1.5"))),
        ])
        let decoded = try TuyaStructuredApplicationEvidenceJSON.decode(
            TuyaStructuredApplicationEvidenceJSON.encode(event)
        )

        #expect(decoded.entries.map(\.key) == [
            .string("1"), .string("bool"), .string("decimal"),
            .signedInteger(1), .unsignedInteger(1),
        ])
        #expect(decoded.entries[0].value == .string("1"))
        #expect(decoded.entries[1].value == .bool(true))
        #expect(decoded.entries[2].value == .finiteDecimal(decimal("1.5")))
        #expect(decoded.entries[3].value == .signedInteger(1))
        #expect(decoded.entries[4].value == .unsignedInteger(UInt64.max))
    }

    @Test("duplicate typed DP keys fail at top level and inside nested objects")
    func duplicateKeysFailClosed() throws {
        let duplicate = TuyaStructuredApplicationEntry(
            key: .string("mode"),
            value: .string("eco")
        )

        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.duplicateKey(
                path: "entries[1].key"
            )
        ) {
            _ = try makeEvent(entries: [duplicate, duplicate])
        }

        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.duplicateKey(
                path: "entries[0].value.object[1].key"
            )
        ) {
            _ = try makeEvent(entries: [
                .init(
                    key: .string("nested"),
                    value: .object([
                        .init(key: .signedInteger(5), value: .bool(true)),
                        .init(key: .signedInteger(5), value: .bool(false)),
                    ])
                ),
            ])
        }

        // The same scalar under a differently typed key is not a duplicate.
        _ = try makeEvent(entries: [
            .init(key: .string("5"), value: .null),
            .init(key: .signedInteger(5), value: .null),
            .init(key: .unsignedInteger(5), value: .null),
        ])
    }

    @Test("chronology accepts a new generation and rejects replay or generation regression")
    func chronologyRejectsDuplicateAndReplayBoundaries() throws {
        let first = try makeEvent(generation: 1, sequence: 4, uptime: 100)
        let second = try makeEvent(generation: 1, sequence: 5, uptime: 101)
        let reconnect = try makeEvent(generation: 2, sequence: 1, uptime: 102)
        try TuyaStructuredApplicationEvidenceChronology.validate([first, second, reconnect])

        let equalUptimeRepeatedSample = try makeEvent(
            generation: 1,
            sequence: 5,
            uptime: 100
        )
        try TuyaStructuredApplicationEvidenceChronology.validate([
            first,
            equalUptimeRepeatedSample,
        ])

        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .duplicateOrReplayedEvent(eventIndex: 1)
        ) {
            try TuyaStructuredApplicationEvidenceChronology.validate([first, first])
        }

        let sequenceReplay = try makeEvent(generation: 1, sequence: 4, uptime: 102)
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .duplicateOrReplayedEvent(eventIndex: 1)
        ) {
            try TuyaStructuredApplicationEvidenceChronology.validate([first, sequenceReplay])
        }

        let generationRegression = try makeEvent(generation: 1, sequence: 6, uptime: 103)
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .connectionGenerationRegressed(eventIndex: 1)
        ) {
            try TuyaStructuredApplicationEvidenceChronology.validate([
                reconnect,
                generationRegression,
            ])
        }
    }

    @Test("mixed pseudonymous sessions cannot be validated as one timeline")
    func chronologyRejectsMixedSessions() throws {
        let otherSession = try TuyaStructuredApplicationSessionID(
            pseudonymousUUID: UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        )
        let first = try makeEvent(uptime: 100)
        let second = try makeEvent(session: otherSession, sequence: 2, uptime: 101)

        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .mixedPseudonymousSessions(eventIndex: 1)
        ) {
            try TuyaStructuredApplicationEvidenceChronology.validate([first, second])
        }
    }

    @Test("nonfinite decimal, invalid chronology scalars, and empty updates fail closed")
    func invalidValuesFailBeforeEvidenceCreation() throws {
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .nonFiniteDecimal(path: "entries[0].value")
        ) {
            _ = try makeEvent(entries: [
                .init(key: .string("ratio"), value: .finiteDecimal(.nan)),
            ])
        }
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .invalidConnectionGeneration(0)
        ) {
            _ = try makeEvent(generation: 0)
        }
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.invalidDeliverySequence(0)
        ) {
            _ = try makeEvent(sequence: 0)
        }
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.invalidMonotonicReceipt(0)
        ) {
            _ = try makeEvent(uptime: 0)
        }
        #expect(throws: TuyaStructuredApplicationEvidenceValidationError.invalidWallClock) {
            _ = try makeEvent(wallClock: Date(timeIntervalSince1970: .infinity))
        }
        #expect(throws: TuyaStructuredApplicationEvidenceValidationError.emptyApplicationUpdate) {
            _ = try makeEvent(entries: [])
        }
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .invalidKey(path: "entries[0].key")
        ) {
            _ = try makeEvent(entries: [
                .init(key: .string(""), value: .null),
            ])
        }
    }

    @Test("corrupt, truncated, noncanonical, and nonfinite JSON cannot import")
    func strictJSONDecodeRejectsInvalidArtifacts() throws {
        let canonical = try TuyaStructuredApplicationEvidenceJSON.encode(makeEvent())
        let truncated = canonical.dropLast()

        #expect(throws: TuyaStructuredApplicationEvidenceValidationError.malformedJSON) {
            _ = try TuyaStructuredApplicationEvidenceJSON.decode(Data(truncated))
        }
        #expect(throws: TuyaStructuredApplicationEvidenceValidationError.malformedJSON) {
            _ = try TuyaStructuredApplicationEvidenceJSON.decode(Data("not-json".utf8))
        }

        let oversized = Data(
            repeating: 0x20,
            count: TuyaStructuredApplicationEvidenceJSON.maximumCanonicalEventByteCount + 1
        )
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.inputByteLimitExceeded(
                byteCount: oversized.count,
                maximum: TuyaStructuredApplicationEvidenceJSON.maximumCanonicalEventByteCount
            )
        ) {
            _ = try TuyaStructuredApplicationEvidenceJSON.decode(oversized)
        }

        let maximumValue = String(repeating: "x", count: 4_096)
        let oversizedEvent = try makeEvent(
            entries: (0..<300).map { index in
                .init(key: .string("synthetic_\(index)"), value: .string(maximumValue))
            }
        )
        let unrestrictedEncoder = JSONEncoder()
        unrestrictedEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let unrestrictedBytes = try unrestrictedEncoder.encode(oversizedEvent)
        #expect(
            unrestrictedBytes.count >
                TuyaStructuredApplicationEvidenceJSON.maximumCanonicalEventByteCount
        )
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.inputByteLimitExceeded(
                byteCount: unrestrictedBytes.count,
                maximum: TuyaStructuredApplicationEvidenceJSON.maximumCanonicalEventByteCount
            )
        ) {
            _ = try TuyaStructuredApplicationEvidenceJSON.encode(oversizedEvent)
        }
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.inputByteLimitExceeded(
                byteCount: unrestrictedBytes.count,
                maximum: TuyaStructuredApplicationEvidenceJSON.maximumCanonicalEventByteCount
            )
        ) {
            _ = try TuyaStructuredApplicationEvidenceJSON
                .canonicalPayloadSHA256(oversizedEvent)
        }

        let prettyObject = try JSONSerialization.jsonObject(with: canonical)
        let pretty = try JSONSerialization.data(
            withJSONObject: prettyObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        #expect(throws: TuyaStructuredApplicationEvidenceValidationError.nonCanonicalJSON) {
            _ = try TuyaStructuredApplicationEvidenceJSON.decode(pretty)
        }

        let finiteDecimal = try TuyaStructuredApplicationEvidenceJSON.encode(
            makeEvent(entries: [
                .init(key: .string("ratio"), value: .finiteDecimal(decimal("1.5"))),
            ])
        )
        let nonfinite = Data(
            String(decoding: finiteDecimal, as: UTF8.self)
                .replacingOccurrences(of: #""value":"1.5""#, with: #""value":"NaN""#)
                .utf8
        )
        #expect(throws: TuyaStructuredApplicationEvidenceValidationError.malformedJSON) {
            _ = try TuyaStructuredApplicationEvidenceJSON.decode(nonfinite)
        }
    }

    @Test("raw-byte claims and duplicate root fields fail closed")
    func rawTransportClaimsCannotEnterEvidence() throws {
        let canonical = try TuyaStructuredApplicationEvidenceJSON.encode(makeEvent())
        let rawClaim = Data(
            String(decoding: canonical, as: UTF8.self)
                .replacingOccurrences(
                    of: #""rawTransportBytesAvailable":false"#,
                    with: #""rawTransportBytesAvailable":true"#
                )
                .utf8
        )
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError.rawTransportBytesClaimed
        ) {
            _ = try TuyaStructuredApplicationEvidenceJSON.decode(rawClaim)
        }

        let duplicateSchema = Data(
            ("{\"schemaVersion\":1," + String(decoding: canonical.dropFirst(), as: UTF8.self)).utf8
        )
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .duplicateWireField("schemaVersion")
        ) {
            _ = try TuyaStructuredApplicationEvidenceJSON.decode(duplicateSchema)
        }
    }

    @Test("private source evidence preserves identifier-shaped strings exactly")
    func privateEvidenceDoesNotDestroyLegitimateStringPayloads() throws {
        let syntheticUUID = "00000000-0000-4000-8000-000000000000"
        let syntheticHex = String(repeating: "deadbeef", count: 8)
        let syntheticTokenShape = "header000.payload00.signature"
        let event = try makeEvent(entries: [
            .init(key: .string("synthetic_uuid"), value: .string(syntheticUUID)),
            .init(key: .string("synthetic_hex"), value: .string(syntheticHex)),
            .init(key: .string("synthetic_token_shape"), value: .string(syntheticTokenShape)),
        ])
        let decoded = try TuyaStructuredApplicationEvidenceJSON.decode(
            TuyaStructuredApplicationEvidenceJSON.encode(event)
        )

        #expect(decoded.entries.map(\.value) == [
            .string(syntheticHex),
            .string(syntheticTokenShape),
            .string(syntheticUUID),
        ])
        #expect(decoded.rawTransportBytesAvailable == false)
        #expect(decoded.authorizesProductionTelemetry == false)
    }

    @Test("session IDs accept only canonical version-4 pseudonyms")
    func sessionIdentityRejectsStableOrNoncanonicalUUIDShapes() throws {
        #expect(
            throws: TuyaStructuredApplicationEvidenceValidationError
                .invalidPseudonymousSessionID
        ) {
            _ = try TuyaStructuredApplicationSessionID(
                pseudonymousUUID: UUID(uuidString: "01234567-89ab-1def-8123-456789abcdef")!
            )
        }

        let random = TuyaStructuredApplicationSessionID.makeRandom()
        #expect(UUID(uuidString: random.value) != nil)
        #expect(Array(random.value.utf8)[14] == 0x34)
    }

    private func makeEvent(
        session: TuyaStructuredApplicationSessionID? = nil,
        generation: UInt64 = 1,
        sequence: UInt64 = 1,
        uptime: UInt64 = 5_000_000_000,
        wallClock: Date? = nil,
        entries: [TuyaStructuredApplicationEntry] = [
            .init(key: .string("1"), value: .bool(true)),
        ]
    ) throws -> TuyaStructuredApplicationEvidenceEvent {
        try TuyaStructuredApplicationEvidenceEvent(
            pseudonymousSessionID: session ?? sessionID,
            connectionGeneration: generation,
            deliverySequence: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtWallClock: wallClock ?? receivedAt,
            entries: entries
        )
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct CanonicalPayload: Encodable {
        let entries: [TuyaStructuredApplicationEntry]
    }
}
