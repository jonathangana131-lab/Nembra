import Testing
@testable import NembraCore

@Suite("Tuya DP marker correlation observation reuse")
struct TuyaCandidateDPMarkerCorrelationObservationReuseTests {
    private func stream() throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P-A",
            serviceIdentifier: "S-A",
            characteristicIdentifier: "C-A"
        )
    }

    private func scope() throws -> TuyaCandidateDPMarkerCorrelationScope {
        try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: "Battery",
            streamIdentity: stream(),
            continuityGeneration: 7,
            dataLengthWidth: .twoByteBigEndian
        )
    }

    private func policy(distance: UInt64) throws -> TuyaCandidateDPMarkerCorrelationPolicy {
        try TuyaCandidateDPMarkerCorrelationPolicy(
            maximumMarkerDistanceNanoseconds: distance,
            maximumMarkerCount: 8,
            maximumObservationCount: 8,
            maximumCandidateOccurrenceCount: 16
        )
    }

    private func marker(
        _ receiptUptimeNanoseconds: UInt64,
        _ displayedReference: String
    ) throws -> TuyaCandidateDPStockAppMarker {
        try TuyaCandidateDPStockAppMarker(
            receiptUptimeNanoseconds: receiptUptimeNanoseconds,
            displayedReference: displayedReference
        )
    }

    private func observation(
        completionUptimeNanoseconds: UInt64,
        value: UInt8 = 7
    ) throws -> TuyaCandidateDPMessageObservation {
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: try stream(),
            continuityGeneration: 7,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: completionUptimeNanoseconds,
            lastReceiptUptimeNanoseconds: completionUptimeNanoseconds
        )
        let record = TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 5,
            identifier: 5,
            rawType: 0x02,
            knownType: .value,
            declaredValueLength: 1,
            valueBytes: [value],
            shapeFinding: .fixedLengthKnownType(.value, allowedLengths: [1, 2, 4])
        )
        let payload = TuyaCandidateDPPayload(
            dataLengthWidth: .twoByteBigEndian,
            sourceByteCount: 5,
            records: [record]
        )
        return TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: payload
        )
    }

    @Test("one physical candidate message cannot manufacture repeated marker support")
    func oneObservationSupportsOnlyClosestMarker() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [
                try marker(99, "A"),
                try marker(110, "B")
            ],
            observations: [try observation(completionUptimeNanoseconds: 100)],
            policy: policy(distance: 20)
        )

        let evidence = try #require(report.candidates.first)
        #expect(evidence.matchedMarkerCount == 1)
        #expect(evidence.hits.map(\.markerIndex) == [0])
        #expect(evidence.sharedObservationMarkerIndices == [1])
        #expect(evidence.hits[0].temporalDistanceNanoseconds == 1)
    }

    @Test("one message equidistant from two markers supports neither marker")
    func sharedObservationTieIsAmbiguous() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [
                try marker(95, "A"),
                try marker(105, "B")
            ],
            observations: [try observation(completionUptimeNanoseconds: 100)],
            policy: policy(distance: 10)
        )

        let evidence = try #require(report.candidates.first)
        #expect(evidence.matchedMarkerCount == 0)
        #expect(evidence.sharedObservationMarkerIndices == [0, 1])
        #expect(evidence.hits.isEmpty)
    }
}
