import Testing
@testable import NembraCore


@Suite("Tuya DP stock-app marker correlation — adversarial")
struct TuyaCandidateDPMarkerCorrelationAdversarialTests {

    private func valueRecord(id: UInt8, raw: UInt32, width: Int = 4) -> TuyaCandidateDPRecord {
        let bytes: [UInt8]
        switch width {
        case 1:
            bytes = [UInt8(truncatingIfNeeded: raw)]
        case 2:
            bytes = [UInt8(truncatingIfNeeded: raw >> 8), UInt8(truncatingIfNeeded: raw)]
        default:
            bytes = [
                UInt8(truncatingIfNeeded: raw >> 24),
                UInt8(truncatingIfNeeded: raw >> 16),
                UInt8(truncatingIfNeeded: raw >> 8),
                UInt8(truncatingIfNeeded: raw)
            ]
        }
        return TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 4 + bytes.count,
            identifier: id,
            rawType: TuyaCandidateDPKnownType.value.rawValue,
            knownType: .value,
            declaredValueLength: bytes.count,
            valueBytes: bytes,
            shapeFinding: .fixedLengthKnownType(.value, allowedLengths: [1, 2, 4])
        )
    }

    private func malformedBooleanRecord(id: UInt8) -> TuyaCandidateDPRecord {
        TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 5,
            identifier: id,
            rawType: TuyaCandidateDPKnownType.boolean.rawValue,
            knownType: .boolean,
            declaredValueLength: 1,
            valueBytes: [2],
            shapeFinding: .fixedLengthKnownType(.boolean, allowedLengths: [1])
        )
    }

    private func payload(
        _ records: [TuyaCandidateDPRecord],
        width: TuyaCandidateDPDataLengthWidth = .twoByteBigEndian
    ) -> TuyaCandidateDPPayload {
        TuyaCandidateDPPayload(dataLengthWidth: width, sourceByteCount: 32, records: records)
    }

    private func snapshot(
        marker: UInt64,
        field: String = "Battery",
        display: String,
        reference: Double,
        candidate: UInt64,
        stream: String = "peripheral/service/characteristic",
        generation: UInt64 = 1,
        payload: TuyaCandidateDPPayload
    ) throws -> TuyaCandidateDPMarkerSnapshot {
        try TuyaCandidateDPMarkerSnapshot(
            markerSequenceNumber: marker,
            markerField: field,
            markerDisplayedValue: display,
            numericReferenceValue: reference,
            candidateSequenceNumber: candidate,
            sourceStreamIdentity: stream,
            continuityGeneration: generation,
            payload: payload
        )
    }

    private func policy(tolerance: Double = 0) throws -> TuyaCandidateDPMarkerCorrelationPolicy {
        try TuyaCandidateDPMarkerCorrelationPolicy(
            maximumSnapshotCount: 32,
            maximumHypothesisCount: 8,
            absoluteTolerance: tolerance
        )
    }

    @Test("mixed source streams fail closed")
    func rejectsMixedStreams() throws {
        let snapshots = try [
            snapshot(marker: 1, display: "73%", reference: 73, candidate: 1, stream: "stream-a", payload: payload([valueRecord(id: 17, raw: 73)])),
            snapshot(marker: 2, display: "72%", reference: 72, candidate: 2, stream: "stream-b", payload: payload([valueRecord(id: 17, raw: 72)]))
        ]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.mixedSourceStreamIdentity) {
            try TuyaCandidateDPMarkerCorrelation.analyze(
                snapshots,
                field: "Battery",
                hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)],
                policy: policy()
            )
        }
    }

    @Test("one-byte and two-byte framing interpretations cannot be switched between markers")
    func rejectsMixedFramingWidth() throws {
        let snapshots = try [
            snapshot(marker: 1, display: "73%", reference: 73, candidate: 1, payload: payload([valueRecord(id: 17, raw: 73)], width: .oneByte)),
            snapshot(marker: 2, display: "72%", reference: 72, candidate: 2, payload: payload([valueRecord(id: 17, raw: 72)], width: .twoByteBigEndian))
        ]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.mixedDataLengthWidth) {
            try TuyaCandidateDPMarkerCorrelation.analyze(
                snapshots,
                field: "Battery",
                hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)],
                policy: policy()
            )
        }
    }

    @Test("the same human marker cannot be counted twice")
    func rejectsDuplicateMarkerIdentity() throws {
        let snapshots = try [
            snapshot(marker: 9, display: "73%", reference: 73, candidate: 1, payload: payload([valueRecord(id: 17, raw: 73)])),
            snapshot(marker: 9, display: "73%", reference: 73, candidate: 2, payload: payload([valueRecord(id: 17, raw: 73)]))
        ]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.duplicateMarkerSequenceNumber(9)) {
            try TuyaCandidateDPMarkerCorrelation.analyze(
                snapshots,
                field: "Battery",
                hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)],
                policy: policy()
            )
        }
    }

    @Test("nonfinite reference values and implicit constant transforms are rejected")
    func validatesResearchInputs() throws {
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidNumericReferenceValue(markerSequenceNumber: 1)) {
            try snapshot(marker: 1, display: "bad", reference: .nan, candidate: 1, payload: payload([]))
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidHypothesisScale) {
            try TuyaCandidateDPLinearTransformHypothesis(identifier: "constant", scale: 0, offset: 73)
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidHypothesisOffset) {
            try TuyaCandidateDPLinearTransformHypothesis(identifier: "bad", scale: 1, offset: .infinity)
        }
    }

    @Test("resource and tolerance policy is explicit and bounded")
    func validatesBounds() throws {
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidMaximumSnapshotCount) {
            try TuyaCandidateDPMarkerCorrelationPolicy(maximumSnapshotCount: 0, maximumHypothesisCount: 1, absoluteTolerance: 0)
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidMaximumHypothesisCount) {
            try TuyaCandidateDPMarkerCorrelationPolicy(maximumSnapshotCount: 1, maximumHypothesisCount: 0, absoluteTolerance: 0)
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidAbsoluteTolerance) {
            try TuyaCandidateDPMarkerCorrelationPolicy(maximumSnapshotCount: 1, maximumHypothesisCount: 1, absoluteTolerance: -1)
        }

        let one = try snapshot(marker: 1, display: "73%", reference: 73, candidate: 1, payload: payload([valueRecord(id: 17, raw: 73)]))
        let tiny = try TuyaCandidateDPMarkerCorrelationPolicy(maximumSnapshotCount: 1, maximumHypothesisCount: 1, absoluteTolerance: 0)
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.snapshotCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPMarkerCorrelation.analyze(
                [one, one],
                field: "Battery",
                hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)],
                policy: tiny
            )
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.hypothesisCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPMarkerCorrelation.analyze(
                [one],
                field: "Battery",
                hypotheses: [
                    try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1),
                    try TuyaCandidateDPLinearTransformHypothesis(identifier: "tenths", scale: 0.1)
                ],
                policy: tiny
            )
        }
    }

    @Test("missing requested field returns no-match without borrowing another marker field")
    func noMatchingFieldStaysEmpty() throws {
        let one = try snapshot(marker: 1, field: "Voltage", display: "41.3 V", reference: 41.3, candidate: 1, payload: payload([valueRecord(id: 9, raw: 413)]))
        let report = try TuyaCandidateDPMarkerCorrelation.analyze(
            [one],
            field: "Battery",
            hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "tenths", scale: 0.1)],
            policy: policy()
        )
        #expect(report.disposition == .noMatchingMarkers)
        #expect(report.markerCount == 0)
        #expect(report.sourceStreamIdentity == nil)
        #expect(report.evidence.isEmpty)
    }
}
