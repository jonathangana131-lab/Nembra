import Testing
@testable import NembraCore

@Suite("Tuya DP numeric hypothesis evaluation")
struct TuyaCandidateDPNumericHypothesisTests {
    private func stream() throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P",
            serviceIdentifier: "S",
            characteristicIdentifier: "C"
        )
    }

    private func scope(field: String = "Voltage") throws -> TuyaCandidateDPMarkerCorrelationScope {
        try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: field,
            streamIdentity: stream(),
            continuityGeneration: 7,
            dataLengthWidth: .twoByteBigEndian
        )
    }

    private func correlationPolicy(distance: UInt64 = 20) throws -> TuyaCandidateDPMarkerCorrelationPolicy {
        try TuyaCandidateDPMarkerCorrelationPolicy(
            maximumMarkerDistanceNanoseconds: distance,
            maximumMarkerCount: 32,
            maximumObservationCount: 64,
            maximumCandidateOccurrenceCount: 256
        )
    }

    private func numericPolicy(tolerance: Double = 0) throws -> TuyaCandidateDPNumericHypothesisPolicy {
        try TuyaCandidateDPNumericHypothesisPolicy(
            maximumReferenceCount: 32,
            maximumHypothesisCount: 8,
            absoluteTolerance: tolerance
        )
    }

    private func marker(_ time: UInt64, _ displayed: String) throws -> TuyaCandidateDPStockAppMarker {
        try TuyaCandidateDPStockAppMarker(
            receiptUptimeNanoseconds: time,
            displayedReference: displayed
        )
    }

    private func record(
        id: UInt8 = 9,
        type: UInt8 = TuyaCandidateDPKnownType.value.rawValue,
        value: [UInt8]
    ) -> TuyaCandidateDPRecord {
        let known = TuyaCandidateDPKnownType(rawValue: type)
        let finding: TuyaCandidateDPShapeFinding
        if let known {
            finding = .fixedLengthKnownType(known, allowedLengths: [value.count])
        } else {
            finding = .unknownType(rawType: type)
        }
        return TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 4 + value.count,
            identifier: id,
            rawType: type,
            knownType: known,
            declaredValueLength: value.count,
            valueBytes: value,
            shapeFinding: finding
        )
    }

    private func observation(
        time: UInt64,
        record: TuyaCandidateDPRecord
    ) throws -> TuyaCandidateDPMessageObservation {
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
        let payload = TuyaCandidateDPPayload(
            dataLengthWidth: .twoByteBigEndian,
            sourceByteCount: 4 + record.valueBytes.count,
            records: [record]
        )
        return TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: payload
        )
    }

    private func report(
        displayed: [String],
        rawValues: [[UInt8]],
        type: UInt8 = TuyaCandidateDPKnownType.value.rawValue,
        distance: UInt64 = 0
    ) throws -> TuyaCandidateDPMarkerCorrelationReport {
        let markerTimes = displayed.indices.map { UInt64(($0 + 1) * 100) }
        let markers = try zip(markerTimes, displayed).map { try marker($0.0, $0.1) }
        let observations = try zip(markerTimes, rawValues).map {
            try observation(time: $0.0, record: record(type: type, value: $0.1))
        }
        return try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: markers,
            observations: observations,
            policy: correlationPolicy(distance: distance)
        )
    }

    @Test("caller-supplied tenths hypothesis matches raw 413/412 without replacing raw evidence")
    func explicitTenthsHypothesis() throws {
        let parent = try report(
            displayed: ["41.3 V", "41.2 V"],
            rawValues: [[0x01, 0x9D], [0x01, 0x9C]]
        )
        let references = [
            try TuyaCandidateDPNumericReference(markerIndex: 0, value: 41.3),
            try TuyaCandidateDPNumericReference(markerIndex: 1, value: 41.2)
        ]
        let identity = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "identity",
            scale: 1
        )
        let tenths = try TuyaCandidateDPNumericTransformHypothesis(
            identifier: "explicit /10",
            scale: 0.1
        )

        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: references,
            hypotheses: [identity, tenths],
            policy: numericPolicy(tolerance: 0.000_001)
        )

        #expect(result.correlationScope.fieldLabel == "Voltage")
        #expect(result.candidate.identifier == 9)
        #expect(result.evidence.count == 2)
        #expect(result.evidence[0].hypothesis.identifier == "explicit /10")
        #expect(result.evidence[0].matchedWithinToleranceCount == 2)
        #expect(result.evidence[0].samples.map(\.rawUnsignedMagnitude) == [413, 412])
        #expect(result.evidence[0].samples.map(\.valueBytes) == [[0x01, 0x9D], [0x01, 0x9C]])
        #expect(result.evidence[1].hypothesis.identifier == "identity")
        #expect(result.evidence[1].matchedWithinToleranceCount == 0)
    }

    @Test("display strings remain provenance and are never parsed into numeric references")
    func displayedTextDoesNotCreateNumbers() throws {
        let parent = try report(displayed: ["forty one point three volts"], rawValues: [[0x01, 0x9D]])
        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [],
            hypotheses: [try TuyaCandidateDPNumericTransformHypothesis(identifier: "explicit /10", scale: 0.1)],
            policy: numericPolicy()
        )

        let evidence = try #require(result.evidence.first)
        #expect(result.numericReferenceCount == 0)
        #expect(evidence.candidateHitCount == 1)
        #expect(evidence.referencedCandidateHitCount == 0)
        #expect(evidence.samples.isEmpty)
    }

    @Test("raw/string/unknown candidate bytes are never coerced to scalar magnitudes")
    func opaqueCandidateStaysNonNumeric() throws {
        let parent = try report(
            displayed: ["anchor"],
            rawValues: [[0x01, 0x9D]],
            type: TuyaCandidateDPKnownType.raw.rawValue
        )
        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [try TuyaCandidateDPNumericReference(markerIndex: 0, value: 41.3)],
            hypotheses: [try TuyaCandidateDPNumericTransformHypothesis(identifier: "explicit /10", scale: 0.1)],
            policy: numericPolicy()
        )

        let evidence = try #require(result.evidence.first)
        #expect(evidence.referencedCandidateHitCount == 1)
        #expect(evidence.nonNumericReferencedHitCount == 1)
        #expect(evidence.samples.isEmpty)
        #expect(evidence.meanAbsoluteError == nil)
    }

    @Test("malformed boolean value remains nonnumeric")
    func malformedBooleanStaysNonNumeric() throws {
        let parent = try report(
            displayed: ["anchor"],
            rawValues: [[2]],
            type: TuyaCandidateDPKnownType.boolean.rawValue
        )
        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [try TuyaCandidateDPNumericReference(markerIndex: 0, value: 1)],
            hypotheses: [try TuyaCandidateDPNumericTransformHypothesis(identifier: "identity", scale: 1)],
            policy: numericPolicy()
        )
        #expect(result.evidence.first?.nonNumericReferencedHitCount == 1)
        #expect(result.evidence.first?.samples.isEmpty == true)
    }

    @Test("numeric references without a candidate hit remain explicit unused evidence")
    func unusedReferenceIsVisible() throws {
        let markers = [try marker(100, "41.3 V"), try marker(300, "41.2 V")]
        let observations = [try observation(time: 100, record: record(value: [0x01, 0x9D]))]
        let parent = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: markers,
            observations: observations,
            policy: correlationPolicy(distance: 0)
        )
        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [
                try TuyaCandidateDPNumericReference(markerIndex: 0, value: 41.3),
                try TuyaCandidateDPNumericReference(markerIndex: 1, value: 41.2)
            ],
            hypotheses: [try TuyaCandidateDPNumericTransformHypothesis(identifier: "explicit /10", scale: 0.1)],
            policy: numericPolicy()
        )
        #expect(result.unusedReferenceMarkerIndices == [1])
        #expect(result.evidence.first?.evaluableReferenceCount == 1)
    }

    @Test("temporally ambiguous parent markers cannot become numeric support")
    func parentAmbiguityRemainsAmbiguous() throws {
        let parent = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(100, "anchor")],
            observations: [
                try observation(time: 95, record: record(value: [0x01, 0x9D])),
                try observation(time: 105, record: record(value: [0x01, 0x9C]))
            ],
            policy: correlationPolicy(distance: 5)
        )
        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [try TuyaCandidateDPNumericReference(markerIndex: 0, value: 41.3)],
            hypotheses: [try TuyaCandidateDPNumericTransformHypothesis(identifier: "explicit /10", scale: 0.1)],
            policy: numericPolicy()
        )
        #expect(result.ambiguousReferenceMarkerIndices == [0])
        #expect(result.unusedReferenceMarkerIndices.isEmpty)
        #expect(result.evidence.first?.samples.isEmpty == true)
    }

    @Test("exact parent timing provenance survives numeric evaluation")
    func preservesTemporalProvenance() throws {
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: try stream(),
            continuityGeneration: 7,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 2,
            firstReceiptUptimeNanoseconds: 100,
            lastReceiptUptimeNanoseconds: 110
        )
        let parsed = TuyaCandidateDPPayload(
            dataLengthWidth: .twoByteBigEndian,
            sourceByteCount: 6,
            records: [record(value: [0x01, 0x9D])]
        )
        let parent = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(105, "41.3 V")],
            observations: [TuyaCandidateDPMessageObservation(reassembledMessage: message, parsedPayload: parsed)],
            policy: correlationPolicy(distance: 5)
        )
        let result = try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: [try TuyaCandidateDPNumericReference(markerIndex: 0, value: 41.3)],
            hypotheses: [try TuyaCandidateDPNumericTransformHypothesis(identifier: "explicit /10", scale: 0.1)],
            policy: numericPolicy(tolerance: 0.000_001)
        )
        let sample = try #require(result.evidence.first?.samples.first)
        #expect(sample.observationFirstReceiptUptimeNanoseconds == 100)
        #expect(sample.observationLastReceiptUptimeNanoseconds == 110)
        #expect(sample.temporalDistanceNanoseconds == 5)
        #expect(sample.temporalRelation == .messageAfterMarker)
    }

    @Test("duplicate and out-of-range numeric marker identities fail closed")
    func validatesReferenceIdentity() throws {
        let parent = try report(displayed: ["anchor"], rawValues: [[7]])
        let one = try TuyaCandidateDPNumericReference(markerIndex: 0, value: 7)
        #expect(throws: TuyaCandidateDPNumericHypothesisError.duplicateNumericReferenceMarkerIndex(0)) {
            try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
                report: parent,
                candidateIndex: 0,
                numericReferences: [one, one],
                hypotheses: [],
                policy: numericPolicy()
            )
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidMarkerIndex(1)) {
            try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
                report: parent,
                candidateIndex: 0,
                numericReferences: [try TuyaCandidateDPNumericReference(markerIndex: 1, value: 7)],
                hypotheses: [],
                policy: numericPolicy()
            )
        }
    }

    @Test("candidate selection fails closed instead of falling back to a different candidate")
    func validatesCandidateIndex() throws {
        let parent = try report(displayed: ["anchor"], rawValues: [[7]])
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidCandidateIndex(1)) {
            try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
                report: parent,
                candidateIndex: 1,
                numericReferences: [],
                hypotheses: [],
                policy: numericPolicy()
            )
        }
    }

    @Test("numeric input and transform policy rejects nonfinite or implicit-constant assumptions")
    func validatesNumericInputs() throws {
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidMarkerIndex(-1)) {
            try TuyaCandidateDPNumericReference(markerIndex: -1, value: 1)
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidNumericReference(markerIndex: 0)) {
            try TuyaCandidateDPNumericReference(markerIndex: 0, value: .nan)
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidHypothesisIdentifier) {
            try TuyaCandidateDPNumericTransformHypothesis(identifier: " ", scale: 1)
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidHypothesisScale) {
            try TuyaCandidateDPNumericTransformHypothesis(identifier: "constant", scale: 0, offset: 41.3)
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidHypothesisOffset) {
            try TuyaCandidateDPNumericTransformHypothesis(identifier: "bad", scale: 1, offset: .infinity)
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidAbsoluteTolerance) {
            try TuyaCandidateDPNumericHypothesisPolicy(
                maximumReferenceCount: 1,
                maximumHypothesisCount: 1,
                absoluteTolerance: -1
            )
        }
    }

    @Test("resource ceilings are caller-owned and enforced before evaluation")
    func validatesResourceBounds() throws {
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidMaximumReferenceCount) {
            try TuyaCandidateDPNumericHypothesisPolicy(
                maximumReferenceCount: 0,
                maximumHypothesisCount: 1,
                absoluteTolerance: 0
            )
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.invalidMaximumHypothesisCount) {
            try TuyaCandidateDPNumericHypothesisPolicy(
                maximumReferenceCount: 1,
                maximumHypothesisCount: 0,
                absoluteTolerance: 0
            )
        }

        let parent = try report(displayed: ["anchor"], rawValues: [[7]])
        let tiny = try TuyaCandidateDPNumericHypothesisPolicy(
            maximumReferenceCount: 1,
            maximumHypothesisCount: 1,
            absoluteTolerance: 0
        )
        #expect(throws: TuyaCandidateDPNumericHypothesisError.referenceCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
                report: parent,
                candidateIndex: 0,
                numericReferences: [
                    try TuyaCandidateDPNumericReference(markerIndex: 0, value: 7),
                    try TuyaCandidateDPNumericReference(markerIndex: 0, value: 7)
                ],
                hypotheses: [],
                policy: tiny
            )
        }
        #expect(throws: TuyaCandidateDPNumericHypothesisError.hypothesisCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
                report: parent,
                candidateIndex: 0,
                numericReferences: [],
                hypotheses: [
                    try TuyaCandidateDPNumericTransformHypothesis(identifier: "identity", scale: 1),
                    try TuyaCandidateDPNumericTransformHypothesis(identifier: "tenths", scale: 0.1)
                ],
                policy: tiny
            )
        }
    }
}
