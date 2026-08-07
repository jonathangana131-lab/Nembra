import Testing
@testable import NembraCore

@Suite("Tuya DP cross-session independence boundary")
struct TuyaCandidateDPCrossSessionIndependenceTests {
    private func stream() throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P",
            serviceIdentifier: "S",
            characteristicIdentifier: "C"
        )
    }

    private func transform(
        identifier: String = "explicit /10",
        scale: Double = 0.1
    ) throws -> TuyaCandidateDPNumericTransformHypothesis {
        try TuyaCandidateDPNumericTransformHypothesis(identifier: identifier, scale: scale)
    }

    private func parentReport(
        generation: UInt64 = 7,
        receiptTime: UInt64 = 100
    ) throws -> TuyaCandidateDPMarkerCorrelationReport {
        let streamIdentity = try stream()
        let scope = try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: "Voltage",
            streamIdentity: streamIdentity,
            continuityGeneration: generation,
            dataLengthWidth: .twoByteBigEndian
        )
        let marker = try TuyaCandidateDPStockAppMarker(
            receiptUptimeNanoseconds: receiptTime,
            displayedReference: "41.3 V"
        )
        let record = TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 6,
            identifier: 9,
            rawType: TuyaCandidateDPKnownType.value.rawValue,
            knownType: .value,
            declaredValueLength: 2,
            valueBytes: [0x01, 0x9D],
            shapeFinding: .fixedLengthKnownType(.value, allowedLengths: [2])
        )
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: streamIdentity,
            continuityGeneration: generation,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: receiptTime,
            lastReceiptUptimeNanoseconds: receiptTime
        )
        let payload = TuyaCandidateDPPayload(
            dataLengthWidth: .twoByteBigEndian,
            sourceByteCount: 6,
            records: [record]
        )
        let observation = TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: payload
        )
        let policy = try TuyaCandidateDPMarkerCorrelationPolicy(
            maximumMarkerDistanceNanoseconds: 0,
            maximumMarkerCount: 4,
            maximumObservationCount: 4,
            maximumCandidateOccurrenceCount: 8
        )
        return try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope,
            markers: [marker],
            observations: [observation],
            policy: policy
        )
    }

    private func numericReport(
        generation: UInt64 = 7,
        receiptTime: UInt64 = 100,
        referenceValue: Double = 41.3,
        tolerance: Double = 0.000_001,
        hypotheses: [TuyaCandidateDPNumericTransformHypothesis]
    ) throws -> TuyaCandidateDPNumericHypothesisReport {
        let policy = try TuyaCandidateDPNumericHypothesisPolicy(
            maximumReferenceCount: 4,
            maximumHypothesisCount: 4,
            absoluteTolerance: tolerance
        )
        return try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parentReport(generation: generation, receiptTime: receiptTime),
            candidateIndex: 0,
            numericReferences: [
                try TuyaCandidateDPNumericReference(markerIndex: 0, value: referenceValue)
            ],
            hypotheses: hypotheses,
            policy: policy
        )
    }

    private func policy() throws -> TuyaCandidateDPCrossSessionConsistencyPolicy {
        try TuyaCandidateDPCrossSessionConsistencyPolicy(maximumSessionCount: 4)
    }

    @Test("one labelled session cannot masquerade as cross-session evidence")
    func rejectsSingleSession() throws {
        let selected = try transform()
        let report = try numericReport(hypotheses: [selected])
        let observation = try TuyaCandidateDPCrossSessionObservation(
            sessionIdentifier: "only-session",
            report: report
        )

        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.insufficientSessionCount(minimum: 2)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [observation],
                hypothesis: selected,
                policy: policy()
            )
        }
    }

    @Test("repackaging one selected evidence set with extra hypotheses cannot create a second session")
    func rejectsRepackagedSameEvidence() throws {
        let selected = try transform()
        let identity = try transform(identifier: "identity", scale: 1)
        let firstReport = try numericReport(hypotheses: [selected])
        let repackagedReport = try numericReport(hypotheses: [identity, selected])

        #expect(firstReport != repackagedReport)
        #expect(firstReport.absoluteTolerance == repackagedReport.absoluteTolerance)
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.duplicateSessionEvidence(firstIndex: 0, secondIndex: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "capture-a",
                        report: firstReport
                    ),
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "capture-b",
                        report: repackagedReport
                    )
                ],
                hypothesis: selected,
                policy: policy()
            )
        }
    }

    @Test("changing parent tolerance fails before it can masquerade as session independence")
    func rejectsTolerancePolicyDrift() throws {
        let selected = try transform()
        let strict = try numericReport(
            referenceValue: 40,
            tolerance: 0,
            hypotheses: [selected]
        )
        let loose = try numericReport(
            generation: 8,
            referenceValue: 40,
            tolerance: 100,
            hypotheses: [selected]
        )

        #expect(strict.absoluteTolerance == 0)
        #expect(loose.absoluteTolerance == 100)
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.absoluteToleranceMismatch(index: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "strict-policy",
                        report: strict
                    ),
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "loose-policy",
                        report: loose
                    )
                ],
                hypothesis: selected,
                policy: policy()
            )
        }
    }

    @Test("continuity generation relabel alone cannot manufacture a second session")
    func rejectsGenerationOnlyRelabeling() throws {
        let selected = try transform()
        let firstReport = try numericReport(generation: 7, receiptTime: 100, hypotheses: [selected])
        let generationRelabel = try numericReport(generation: 8, receiptTime: 100, hypotheses: [selected])

        #expect(firstReport.correlationScope.continuityGeneration == 7)
        #expect(generationRelabel.correlationScope.continuityGeneration == 8)
        #expect(firstReport != generationRelabel)
        #expect(firstReport.evidence == generationRelabel.evidence)

        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.duplicateSessionEvidence(firstIndex: 0, secondIndex: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "capture-a",
                        report: firstReport
                    ),
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "capture-b",
                        report: generationRelabel
                    )
                ],
                hypothesis: selected,
                policy: policy()
            )
        }
    }

    @Test("same values at different retained times remain distinct session evidence")
    func allowsGenuineTemporalDifference() throws {
        let selected = try transform()
        let firstReport = try numericReport(generation: 7, receiptTime: 100, hypotheses: [selected])
        let laterReport = try numericReport(generation: 8, receiptTime: 200, hypotheses: [selected])

        #expect(firstReport.numericReferences == laterReport.numericReferences)
        #expect(firstReport.evidence != laterReport.evidence)

        let result = try #require(
            TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "capture-a",
                        report: firstReport
                    ),
                    try TuyaCandidateDPCrossSessionObservation(
                        sessionIdentifier: "capture-b",
                        report: laterReport
                    )
                ],
                hypothesis: selected,
                policy: policy()
            )
        )

        #expect(result.sessionCount == 2)
        #expect(result.sessions.map(\.continuityGeneration) == [7, 8])
        #expect(result.sessions[0].samples.first?.markerReceiptUptimeNanoseconds == 100)
        #expect(result.sessions[1].samples.first?.markerReceiptUptimeNanoseconds == 200)
    }

    @Test("session labels are whitespace-normalized before duplicate checks")
    func normalizesSessionLabels() throws {
        let selected = try transform()
        let firstReport = try numericReport(generation: 7, hypotheses: [selected])
        let secondReport = try numericReport(generation: 8, hypotheses: [selected])
        let first = try TuyaCandidateDPCrossSessionObservation(
            sessionIdentifier: "  capture-a  ",
            report: firstReport
        )
        let second = try TuyaCandidateDPCrossSessionObservation(
            sessionIdentifier: "capture-a",
            report: secondReport
        )

        #expect(first.sessionIdentifier == "capture-a")
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.duplicateSessionIdentifier("capture-a")) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [first, second],
                hypothesis: selected,
                policy: policy()
            )
        }
    }
}
