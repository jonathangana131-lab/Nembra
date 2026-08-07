import Testing
@testable import NembraCore

@Suite("Tuya DP cross-session reference retention")
struct TuyaCandidateDPCrossSessionReferenceRetentionTests {
    private func stream() throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P",
            serviceIdentifier: "S",
            characteristicIdentifier: "C"
        )
    }

    private func marker(time: UInt64, displayed: String) throws -> TuyaCandidateDPStockAppMarker {
        try TuyaCandidateDPStockAppMarker(
            receiptUptimeNanoseconds: time,
            displayedReference: displayed
        )
    }

    private func observation(
        time: UInt64,
        generation: UInt64,
        value: [UInt8]
    ) throws -> TuyaCandidateDPMessageObservation {
        let streamIdentity = try stream()
        let record = TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 4 + value.count,
            identifier: 9,
            rawType: TuyaCandidateDPKnownType.value.rawValue,
            knownType: .value,
            declaredValueLength: value.count,
            valueBytes: value,
            shapeFinding: .fixedLengthKnownType(.value, allowedLengths: [value.count])
        )
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: streamIdentity,
            continuityGeneration: generation,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: time,
            lastReceiptUptimeNanoseconds: time
        )
        let payload = TuyaCandidateDPPayload(
            dataLengthWidth: .twoByteBigEndian,
            sourceByteCount: 4 + value.count,
            records: [record]
        )
        return TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: payload
        )
    }

    private func numericReport(
        generation: UInt64,
        displayed: [String],
        references: [Double],
        rawValuesByMarkerIndex: [Int: [UInt8]]
    ) throws -> TuyaCandidateDPNumericHypothesisReport {
        let base = generation * 1_000
        let times = displayed.indices.map { base + UInt64(($0 + 1) * 100) }
        let markers = try zip(times, displayed).map { item in
            try marker(time: item.0, displayed: item.1)
        }
        let observations = try rawValuesByMarkerIndex.keys.sorted().map { index in
            try observation(
                time: times[index],
                generation: generation,
                value: rawValuesByMarkerIndex[index]!
            )
        }
        let scope = try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: "Voltage",
            streamIdentity: stream(),
            continuityGeneration: generation,
            dataLengthWidth: .twoByteBigEndian
        )
        let correlationPolicy = try TuyaCandidateDPMarkerCorrelationPolicy(
            maximumMarkerDistanceNanoseconds: 0,
            maximumMarkerCount: 8,
            maximumObservationCount: 8,
            maximumCandidateOccurrenceCount: 16
        )
        let parent = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope,
            markers: markers,
            observations: observations,
            policy: correlationPolicy
        )
        let numericReferences = try references.enumerated().map { index, value in
            try TuyaCandidateDPNumericReference(markerIndex: index, value: value)
        }
        let transform = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "explicit /10",
            scale: 0.1
        )
        let numericPolicy = try TuyaCandidateDPNumericHypothesisPolicy(
            maximumReferenceCount: 8,
            maximumHypothesisCount: 2,
            absoluteTolerance: 0.01
        )
        return try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: numericReferences,
            hypotheses: [transform],
            policy: numericPolicy
        )
    }

    @Test("unused caller values remain retained and count as reference variation")
    func retainsUnusedReferenceValues() throws {
        let first = try numericReport(
            generation: 1,
            displayed: ["41.3 V", "99.9 V"],
            references: [41.3, 99.9],
            rawValuesByMarkerIndex: [0: [0x01, 0x9D]]
        )
        let second = try numericReport(
            generation: 2,
            displayed: ["41.2 V"],
            references: [41.2],
            rawValuesByMarkerIndex: [0: [0x01, 0x9C]]
        )
        let transform = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "explicit /10",
            scale: 0.1
        )
        let policy = try TuyaCandidateDPCrossSessionConsistencyPolicy(maximumSessionCount: 4)
        let result = try #require(
            TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "reference-retention-experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "capture-a", report: first),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "capture-b", report: second)
                ],
                hypothesis: transform,
                policy: policy
            )
        )

        #expect(result.totalEvaluableSampleCount == 2)
        #expect(result.distinctNumericReferenceValueCount == 3)
        #expect(result.sessions[0].numericReferenceCount == 2)
        #expect(result.sessions[0].numericReferences.map(\.value) == [41.3, 99.9])
        #expect(result.sessions[0].unusedReferenceMarkerIndices == [1])
        #expect(result.sessions[0].samples.map(\.numericReferenceValue) == [41.3])
        #expect(result.sessions[1].numericReferences.map(\.value) == [41.2])
    }
}
