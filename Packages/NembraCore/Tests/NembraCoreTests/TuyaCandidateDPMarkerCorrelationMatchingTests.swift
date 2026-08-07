import Testing
@testable import NembraCore


@Suite("Tuya DP stock-app marker correlation — matching")
struct TuyaCandidateDPMarkerCorrelationMatchingTests {

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

    @Test("repeated exact raw values can be prioritized without naming the field semantics")
    func repeatedIdentityCorrelation() throws {
        let snapshots = try [
            snapshot(marker: 1, display: "73%", reference: 73, candidate: 101, payload: payload([valueRecord(id: 17, raw: 73)])),
            snapshot(marker: 2, display: "72%", reference: 72, candidate: 102, payload: payload([valueRecord(id: 17, raw: 72)])),
            snapshot(marker: 3, display: "71%", reference: 71, candidate: 103, generation: 2, payload: payload([valueRecord(id: 17, raw: 71)]))
        ]
        let identity = try TuyaCandidateDPLinearTransformHypothesis(identifier: "raw identity", scale: 1)
        let report = try TuyaCandidateDPMarkerCorrelation.analyze(
            snapshots,
            field: "battery",
            hypotheses: [identity],
            policy: policy()
        )

        #expect(report.disposition == .analyzed)
        #expect(report.markerCount == 3)
        #expect(report.distinctReferenceValueCount == 3)
        #expect(report.representedContinuityGenerations == [1, 2])
        let evidence = try #require(report.evidence.first)
        #expect(evidence.key.identifier == 17)
        #expect(evidence.matchedWithinToleranceCount == 3)
        #expect(evidence.evaluableMarkerCount == 3)
        #expect(evidence.samples.map(\.rawUnsignedMagnitude) == [73, 72, 71])
        #expect(evidence.samples.map(\.numericReferenceValue) == [73, 72, 71])
    }

    @Test("decimal scaling occurs only when the caller supplies that hypothesis")
    func explicitScaleOnly() throws {
        let snapshots = try [
            snapshot(marker: 1, field: "Voltage", display: "41.3 V", reference: 41.3, candidate: 11, payload: payload([valueRecord(id: 9, raw: 413)])),
            snapshot(marker: 2, field: "Voltage", display: "41.2 V", reference: 41.2, candidate: 12, payload: payload([valueRecord(id: 9, raw: 412)]))
        ]
        let identity = try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)
        let tenths = try TuyaCandidateDPLinearTransformHypothesis(identifier: "caller supplied /10", scale: 0.1)
        let report = try TuyaCandidateDPMarkerCorrelation.analyze(
            snapshots,
            field: "Voltage",
            hypotheses: [identity, tenths],
            policy: policy(tolerance: 0.000_001)
        )

        #expect(report.evidence.count == 2)
        #expect(report.evidence[0].hypothesis.identifier == "caller supplied /10")
        #expect(report.evidence[0].matchedWithinToleranceCount == 2)
        #expect(report.evidence[0].samples.map(\.rawUnsignedMagnitude) == [413, 412])
        #expect(report.evidence[1].hypothesis.identifier == "identity")
        #expect(report.evidence[1].matchedWithinToleranceCount == 0)
    }

    @Test("duplicate same-key candidates inside one marker are ambiguous rather than cherry-picked")
    func duplicateCandidateIsAmbiguous() throws {
        let snapshots = try [
            snapshot(marker: 1, display: "73%", reference: 73, candidate: 1, payload: payload([
                valueRecord(id: 17, raw: 73), valueRecord(id: 17, raw: 99)
            ])),
            snapshot(marker: 2, display: "72%", reference: 72, candidate: 2, payload: payload([valueRecord(id: 17, raw: 72)]))
        ]
        let report = try TuyaCandidateDPMarkerCorrelation.analyze(
            snapshots,
            field: "Battery",
            hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)],
            policy: policy()
        )
        let evidence = try #require(report.evidence.first)
        #expect(evidence.candidatePresentMarkerCount == 2)
        #expect(evidence.ambiguousDuplicateMarkerCount == 1)
        #expect(evidence.evaluableMarkerCount == 1)
        #expect(evidence.matchedWithinToleranceCount == 1)
    }

    @Test("malformed scalar bytes remain nonnumeric evidence")
    func malformedScalarIsNotCoerced() throws {
        let snapshots = try [
            snapshot(marker: 1, display: "1", reference: 1, candidate: 1, payload: payload([malformedBooleanRecord(id: 3)]))
        ]
        let report = try TuyaCandidateDPMarkerCorrelation.analyze(
            snapshots,
            field: "Battery",
            hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)],
            policy: policy()
        )
        let evidence = try #require(report.evidence.first)
        #expect(evidence.nonNumericCandidateMarkerCount == 1)
        #expect(evidence.samples.isEmpty)
        #expect(evidence.meanAbsoluteError == nil)
    }

    @Test("missing candidate on a marker reduces coverage instead of inventing a value")
    func missingCandidateReducesCoverage() throws {
        let snapshots = try [
            snapshot(marker: 1, display: "73%", reference: 73, candidate: 1, payload: payload([valueRecord(id: 17, raw: 73)])),
            snapshot(marker: 2, display: "72%", reference: 72, candidate: 2, payload: payload([valueRecord(id: 18, raw: 72)]))
        ]
        let report = try TuyaCandidateDPMarkerCorrelation.analyze(
            snapshots,
            field: "Battery",
            hypotheses: [try TuyaCandidateDPLinearTransformHypothesis(identifier: "identity", scale: 1)],
            policy: policy()
        )
        let id17 = try #require(report.evidence.first { $0.key.identifier == 17 })
        #expect(id17.markerCount == 2)
        #expect(id17.candidatePresentMarkerCount == 1)
        #expect(id17.evaluableMarkerCount == 1)
        #expect(id17.markerCoverageFraction == 0.5)
    }
}
