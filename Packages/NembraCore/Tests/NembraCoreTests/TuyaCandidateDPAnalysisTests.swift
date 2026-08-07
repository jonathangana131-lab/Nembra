import Testing
@testable import NembraCore

@Suite("Tuya public-family DP candidate analysis")
struct TuyaCandidateDPAnalysisTests {
    private func policy(
        width: TuyaCandidateDPDataLengthWidth = .twoByteBigEndian,
        maximumDatapointCount: Int = 16,
        maximumValueBytes: Int = 256
    ) throws -> TuyaCandidateDPParserPolicy {
        try TuyaCandidateDPParserPolicy(
            dataLengthWidth: width,
            maximumDatapointCount: maximumDatapointCount,
            maximumValueBytes: maximumValueBytes
        )
    }

    private func dp2(_ id: UInt8, _ type: UInt8, _ value: [UInt8]) -> [UInt8] {
        [id, type, UInt8(value.count >> 8), UInt8(value.count & 0xFF)] + value
    }

    private func dp1(_ id: UInt8, _ type: UInt8, _ value: [UInt8]) -> [UInt8] {
        [id, type, UInt8(value.count)] + value
    }

    @Test("two-byte public Bluetooth DP framing preserves ordered raw records")
    func parsesTwoByteLengthFamily() throws {
        let bytes = dp2(6, 0x01, [1])
            + dp2(7, 0x02, [0x00, 0x00, 0x10, 0x01])
            + dp2(8, 0x03, Array("ES80".utf8))
            + dp2(9, 0x04, [3])
            + dp2(10, 0x05, [0x12, 0x34])

        let payload = try TuyaCandidateDPPayloadParser.parse(bytes, policy: policy())
        #expect(payload.dataLengthWidth == .twoByteBigEndian)
        #expect(payload.sourceByteCount == bytes.count)
        #expect(payload.records.map(\.identifier) == [6, 7, 8, 9, 10])
        #expect(payload.records.map(\.knownType) == [.boolean, .value, .string, .enumeration, .bitmap])
        #expect(payload.records[0].candidateBooleanValue == true)
        #expect(payload.records[1].candidateUnsignedBigEndianMagnitude == 0x1001)
        #expect(payload.records[4].candidateUnsignedBigEndianMagnitude == 0x1234)
        #expect(payload.records[2].candidateUnsignedBigEndianMagnitude == nil)
        #expect(payload.records.last?.endByteOffsetExclusive == bytes.count)
    }

    @Test("one-byte length family is explicit rather than auto-detected")
    func parsesOneByteLengthFamilyExplicitly() throws {
        let bytes = dp1(1, 0x02, [0, 0, 0, 100]) + dp1(2, 0x04, [5])
        let payload = try TuyaCandidateDPPayloadParser.parse(bytes, policy: policy(width: .oneByte))
        #expect(payload.dataLengthWidth == .oneByte)
        #expect(payload.records.count == 2)
        #expect(payload.records[0].candidateUnsignedBigEndianMagnitude == 100)
        #expect(payload.records[1].candidateUnsignedBigEndianMagnitude == 5)

        #expect(throws: TuyaCandidateDPAnalysisError.self) {
            try TuyaCandidateDPPayloadParser.parse(bytes, policy: policy(width: .twoByteBigEndian))
        }
    }

    @Test("empty candidate data stays empty rather than inventing a field")
    func emptyPayloadIsEmpty() throws {
        let payload = try TuyaCandidateDPPayloadParser.parse([], policy: policy())
        #expect(payload.dataLengthWidth == .twoByteBigEndian)
        #expect(payload.sourceByteCount == 0)
        #expect(payload.records.isEmpty)
    }

    @Test("unknown type is retained as raw structural evidence")
    func preservesUnknownType() throws {
        let payload = try TuyaCandidateDPPayloadParser.parse(
            dp2(42, 0xFE, [0xAA, 0xBB]),
            policy: policy()
        )
        let record = try #require(payload.records.first)
        #expect(record.rawType == 0xFE)
        #expect(record.knownType == nil)
        #expect(record.shapeFinding == .unknownType(rawType: 0xFE))
        #expect(record.valueBytes == [0xAA, 0xBB])
        #expect(record.candidateUnsignedBigEndianMagnitude == nil)
    }

    @Test("known type with surprising length is reported without rewriting evidence")
    func flagsUnexpectedKnownLength() throws {
        let payload = try TuyaCandidateDPPayloadParser.parse(
            dp2(5, 0x01, [0x00, 0x01]),
            policy: policy()
        )
        let record = try #require(payload.records.first)
        #expect(record.knownType == .boolean)
        #expect(record.valueBytes == [0x00, 0x01])
        #expect(record.shapeFinding == .unexpectedKnownTypeLength(.boolean, allowedLengths: [1], actualLength: 2))
        #expect(record.candidateBooleanValue == nil)
        #expect(record.candidateUnsignedBigEndianMagnitude == nil)
    }

    @Test("boolean projection rejects non-boolean byte without coercion")
    func rejectsMalformedBooleanProjection() throws {
        let payload = try TuyaCandidateDPPayloadParser.parse(dp2(1, 0x01, [2]), policy: policy())
        let record = try #require(payload.records.first)
        #expect(record.shapeFinding == .fixedLengthKnownType(.boolean, allowedLengths: [1]))
        #expect(record.candidateBooleanValue == nil)
        #expect(record.candidateUnsignedBigEndianMagnitude == nil)
        #expect(record.valueBytes == [2])
    }

    @Test("truncated header fails with exact source offset")
    func rejectsTruncatedHeader() throws {
        let bytes = dp2(1, 0x01, [1]) + [0x02, 0x04]
        #expect(throws: TuyaCandidateDPAnalysisError.truncatedHeader(offset: 5, requiredBytes: 4, remainingBytes: 2)) {
            try TuyaCandidateDPPayloadParser.parse(bytes, policy: policy())
        }
    }

    @Test("truncated declared value fails closed")
    func rejectsTruncatedValue() throws {
        let bytes: [UInt8] = [0x01, 0x02, 0x00, 0x04, 0x00, 0x01]
        #expect(throws: TuyaCandidateDPAnalysisError.truncatedValue(offset: 0, declared: 4, remainingBytes: 2)) {
            try TuyaCandidateDPPayloadParser.parse(bytes, policy: policy())
        }
    }

    @Test("resource bounds are caller policy rather than guessed ES80 limits")
    func enforcesInjectedBounds() throws {
        #expect(throws: TuyaCandidateDPAnalysisError.invalidMaximumDatapointCount) {
            try TuyaCandidateDPParserPolicy(dataLengthWidth: .twoByteBigEndian, maximumDatapointCount: 0, maximumValueBytes: 10)
        }
        #expect(throws: TuyaCandidateDPAnalysisError.invalidMaximumValueBytes) {
            try TuyaCandidateDPParserPolicy(dataLengthWidth: .twoByteBigEndian, maximumDatapointCount: 1, maximumValueBytes: 0)
        }

        #expect(throws: TuyaCandidateDPAnalysisError.declaredValueLengthExceedsPolicy(offset: 0, declared: 4, maximum: 3)) {
            try TuyaCandidateDPPayloadParser.parse(dp2(1, 0x02, [0, 0, 0, 1]), policy: policy(maximumValueBytes: 3))
        }

        let two = dp2(1, 0x01, [1]) + dp2(2, 0x01, [0])
        #expect(throws: TuyaCandidateDPAnalysisError.datapointCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPPayloadParser.parse(two, policy: policy(maximumDatapointCount: 1))
        }
    }

    @Test("scalar magnitude preserves documented VALUE widths without assigning sign scale or units")
    func projectsOnlyGenericUnsignedMagnitude() throws {
        let bytes = dp2(1, 0x02, [0xFE])
            + dp2(2, 0x02, [0x12, 0x34])
            + dp2(3, 0x02, [0xFF, 0xFF, 0xFF, 0xFE])
            + dp2(4, 0x05, [0x01, 0x02, 0x03, 0x04])
        let payload = try TuyaCandidateDPPayloadParser.parse(bytes, policy: policy())
        #expect(payload.records.map(\.shapeFinding) == [
            .fixedLengthKnownType(.value, allowedLengths: [1, 2, 4]),
            .fixedLengthKnownType(.value, allowedLengths: [1, 2, 4]),
            .fixedLengthKnownType(.value, allowedLengths: [1, 2, 4]),
            .fixedLengthKnownType(.bitmap, allowedLengths: [1, 2, 4])
        ])
        #expect(payload.records[0].candidateUnsignedBigEndianMagnitude == 0xFE)
        #expect(payload.records[1].candidateUnsignedBigEndianMagnitude == 0x1234)
        #expect(payload.records[2].candidateUnsignedBigEndianMagnitude == 4_294_967_294)
        #expect(payload.records[3].candidateUnsignedBigEndianMagnitude == 0x01020304)
    }

    @Test("logical packet bridge ignores command code and only parses caller-selected data")
    func parsesCallerSelectedLogicalData() throws {
        let data = dp2(17, 0x02, [0, 0, 0, 73])
        let packet = TuyaCandidateLogicalPacket(
            sequenceNumber: 1,
            responseTo: 0,
            code: 0xDEAD,
            data: data,
            crc16: 0,
            paddingByteCount: 0
        )
        let payload = try TuyaCandidateDPPayloadParser.parseData(of: packet, policy: policy())
        #expect(payload.dataLengthWidth == .twoByteBigEndian)
        #expect(payload.records.count == 1)
        #expect(payload.records[0].identifier == 17)
        #expect(payload.records[0].candidateUnsignedBigEndianMagnitude == 73)
    }

    @Test("record byte offsets bind each candidate back to exact input evidence")
    func preservesExactOffsets() throws {
        let first = dp2(1, 0x01, [1])
        let second = dp2(2, 0x04, [7])
        let payload = try TuyaCandidateDPPayloadParser.parse(first + second, policy: policy())
        #expect(payload.records[0].headerByteOffset == 0)
        #expect(payload.records[0].valueByteOffset == 4)
        #expect(payload.records[0].endByteOffsetExclusive == 5)
        #expect(payload.records[1].headerByteOffset == 5)
        #expect(payload.records[1].valueByteOffset == 9)
        #expect(payload.records[1].endByteOffsetExclusive == 10)
    }

    @Test("public variable-length evidence stays distinct from caller resource policy")
    func preservesVariableLengthShapeFindings() throws {
        let rawEmpty = try TuyaCandidateDPPayloadParser.parse(dp2(1, 0x00, []), policy: policy())
        #expect(
            rawEmpty.records[0].shapeFinding
                == .unexpectedVariableKnownTypeLength(.raw, allowedLengthRange: 1...256, actualLength: 0)
        )

        let stringEmpty = try TuyaCandidateDPPayloadParser.parse(dp2(2, 0x03, []), policy: policy())
        #expect(
            stringEmpty.records[0].shapeFinding
                == .variableLengthKnownType(.string, allowedLengthRange: 0...255)
        )

        let raw256 = try TuyaCandidateDPPayloadParser.parse(
            dp2(3, 0x00, Array(repeating: 0xAA, count: 256)),
            policy: policy(maximumValueBytes: 300)
        )
        #expect(
            raw256.records[0].shapeFinding
                == .variableLengthKnownType(.raw, allowedLengthRange: 1...300)
        )
        #expect(raw256.records[0].valueBytes.count == 256)

        let raw1024 = try TuyaCandidateDPPayloadParser.parse(
            dp2(4, 0x00, Array(repeating: 0x55, count: 1_024)),
            policy: policy(maximumValueBytes: 1_024)
        )
        #expect(
            raw1024.records[0].shapeFinding
                == .variableLengthKnownType(.raw, allowedLengthRange: 1...1_024)
        )
        #expect(raw1024.records[0].valueBytes.count == 1_024)

        let oversizedString = try TuyaCandidateDPPayloadParser.parse(
            dp2(5, 0x03, Array(repeating: 0x41, count: 256)),
            policy: policy(maximumValueBytes: 300)
        )
        #expect(
            oversizedString.records[0].shapeFinding
                == .unexpectedVariableKnownTypeLength(.string, allowedLengthRange: 0...255, actualLength: 256)
        )
    }

    @Test("deterministic malformed-input stress never searches past supplied bytes")
    func deterministicMalformedInputStress() throws {
        var state: UInt64 = 0x4E454D4252414450
        func nextByte() -> UInt8 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 24)
        }

        let policies = [
            try policy(width: .oneByte, maximumDatapointCount: 32, maximumValueBytes: 512),
            try policy(width: .twoByteBigEndian, maximumDatapointCount: 32, maximumValueBytes: 512)
        ]

        for length in 0..<257 {
            for parserPolicy in policies {
                let bytes = (0..<length).map { _ in nextByte() }
                do {
                    let parsed = try TuyaCandidateDPPayloadParser.parse(bytes, policy: parserPolicy)
                    #expect(parsed.dataLengthWidth == parserPolicy.dataLengthWidth)
                    #expect(parsed.sourceByteCount == bytes.count)
                    #expect(parsed.records.count <= parserPolicy.maximumDatapointCount)
                    #expect(parsed.records.allSatisfy {
                        $0.headerByteOffset >= 0
                            && $0.valueByteOffset >= $0.headerByteOffset
                            && $0.endByteOffsetExclusive >= $0.valueByteOffset
                            && $0.endByteOffsetExclusive <= bytes.count
                            && $0.valueBytes.count == $0.declaredValueLength
                    })
                } catch is TuyaCandidateDPAnalysisError {
                    // Random bytes are expected to fail structure/resource checks.
                }
            }
        }
    }
}
