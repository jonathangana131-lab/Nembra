import Testing
@testable import NembraCore

@Suite("Tuya DP numeric hypothesis stability")
struct TuyaCandidateDPNumericHypothesisStabilityTests {
    private func stream() throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P",
            serviceIdentifier: "S",
            characteristicIdentifier: "C"
        )
    }

    private func scope() throws -> TuyaCandidateDPMarkerCorrelationScope {
        try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: "Reference",
            streamIdentity: stream(),
            continuityGeneration: 7,
            dataLengthWidth: .twoByteBigEndian
        )
    }

    private func record(_ value: [UInt8]) -> TuyaCandidateDPRecord {
        TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 4 + value.count,
            identifier: 9,
            rawType: TuyaCandidateDPKnownType.value.rawValue,
            knownType: .value,
            declaredValueLength: value.count,
            valueBytes: value,
            shapeFinding: .fixedLengthKnownType(.value, allowedLengths: [1, 2, 4])
        )
    }

    private func observation(time: UInt64, value: [UInt8]) throws -> TuyaCandidateDPMessageObservation {
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: try stream(),
            continuityGeneration: 7,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: time,
            lastReceiptUptimeNanoseconds: time
        )
        let candidate = record(value)
        let payload = TuyaCandidateDPPayload(
            dataLengthWidth: .twoByteBigEndian,
            sourceByteCount: 4 + value.count,
            records: [candidate]
        )
        return TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: payload
        )
    }

    private func marker(time: UInt64, displayed: String) throws -> TuyaCandidateDPStockAppMarker {
        try TuyaCandidateDPStockAppMarker(
            receiptUptimeNanoseconds: time,
            displayedReference: displayed
        )
    }

    private func parentReport(
        markerCount: Int,
        rawValue: [UInt8]
    ) throws -> TuyaCandidateDPMarkerCorrelationReport {
        let times = (1...markerCount).map { UInt64($0 * 100) }
        let markers = try times.enumerated().map { index, time in
            try marker(time: time, displayed: "reference-\(index)")
        }
        let observations = try times.map { time in
            try observation(time: time, value: rawValue)
        }
        return try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: markers,
            observations: observations,
            policy: try TuyaCandidateDPMarkerCorrelationPolicy(
                maximumMarkerDistanceNanoseconds: 0,
                maximumMarkerCount: 16,
                maximumObservationCount: 16,
                maximumCandidateOccurrenceCount: 64
            )
        )
    }

    private func policy(maximumReferences: Int = 16) throws -> TuyaCandidateDPNumericHypothesisPolicy {
        try TuyaCandidateDPNumericHypothesisPolicy(
            maximumReferenceCount: maximumReferences,
            maximumHypothesisCount: 8,
            absoluteTolerance: 0
        )
    }

    @Test("equally ranked duplicate labels have deterministic scale and offset tie-breaks")
    func deterministicDuplicateLabelOrdering() throws {
        let parent = try parentReport(markerCount: 1, rawValue: [1])
        let scaleTwo = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "same-label",
            scale: 2,
            offset: 0
        )
        let scaleOneOffsetOne = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "same-label",
            scale: 1,
            offset: 1
        )
        let scaleOneOffsetZero = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "same-label",
            scale: 1,
            offset: 0
        )

        let forward = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [],
            hypotheses: [scaleTwo, scaleOneOffsetOne, scaleOneOffsetZero],
            policy: policy()
        )
        let reversed = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [],
            hypotheses: [scaleOneOffsetZero, scaleOneOffsetOne, scaleTwo],
            policy: policy()
        )

        let expected = [scaleOneOffsetZero, scaleOneOffsetOne, scaleTwo]
        #expect(forward.evidence.map(\.hypothesis) == expected)
        #expect(reversed.evidence.map(\.hypothesis) == expected)
    }

    @Test("mean absolute error stays finite when a naive finite-error sum would overflow")
    func overflowSafeMean() throws {
        let parent = try parentReport(
            markerCount: 3,
            rawValue: [0xFF, 0xFF, 0xFF, 0xFF]
        )
        let references = try (0..<3).map { markerIndex in
            try TuyaCandidateDPNumericReference(markerIndex: markerIndex, value: 0)
        }
        let halfMaximumTransform = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "extreme finite",
            scale: Double.greatestFiniteMagnitude / Double(UInt32.max) / 2
        )

        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: references,
            hypotheses: [halfMaximumTransform],
            policy: policy(maximumReferences: 3)
        )
        let evidence = try #require(result.evidence.first)
        let mean = try #require(evidence.meanAbsoluteError)
        let maximum = try #require(evidence.maximumAbsoluteError)

        #expect(evidence.samples.count == 3)
        #expect(evidence.samples.allSatisfy { $0.absoluteError.isFinite })
        #expect(mean.isFinite)
        #expect(maximum.isFinite)
        #expect(mean == maximum)
    }
}
