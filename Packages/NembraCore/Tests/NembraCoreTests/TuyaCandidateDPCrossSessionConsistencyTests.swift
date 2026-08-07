import Testing
@testable import NembraCore

@Suite("Tuya DP cross-session consistency")
struct TuyaCandidateDPCrossSessionConsistencyTests {
    private func stream(characteristic: String = "C") throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P",
            serviceIdentifier: "S",
            characteristicIdentifier: characteristic
        )
    }

    private func scope(
        field: String = "Voltage",
        characteristic: String = "C",
        generation: UInt64
    ) throws -> TuyaCandidateDPMarkerCorrelationScope {
        try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: field,
            streamIdentity: stream(characteristic: characteristic),
            continuityGeneration: generation,
            dataLengthWidth: .twoByteBigEndian
        )
    }

    private func correlationPolicy() throws -> TuyaCandidateDPMarkerCorrelationPolicy {
        try TuyaCandidateDPMarkerCorrelationPolicy(
            maximumMarkerDistanceNanoseconds: 0,
            maximumMarkerCount: 32,
            maximumObservationCount: 64,
            maximumCandidateOccurrenceCount: 256
        )
    }

    private func numericPolicy(tolerance: Double = 0.000_001) throws -> TuyaCandidateDPNumericHypothesisPolicy {
        try TuyaCandidateDPNumericHypothesisPolicy(
            maximumReferenceCount: 32,
            maximumHypothesisCount: 8,
            absoluteTolerance: tolerance
        )
    }

    private func crossSessionPolicy(maximum: Int = 8) throws -> TuyaCandidateDPCrossSessionConsistencyPolicy {
        try TuyaCandidateDPCrossSessionConsistencyPolicy(maximumSessionCount: maximum)
    }

    private func hypothesis(
        identifier: String = "explicit /10",
        scale: Double = 0.1
    ) throws -> TuyaCandidateDPNumericTransformHypothesis {
        try TuyaCandidateDPNumericTransformHypothesis(
            identifier: identifier,
            scale: scale
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
        value: [UInt8]
    ) -> TuyaCandidateDPRecord {
        TuyaCandidateDPRecord(
            headerByteOffset: 0,
            valueByteOffset: 4,
            endByteOffsetExclusive: 4 + value.count,
            identifier: id,
            rawType: TuyaCandidateDPKnownType.value.rawValue,
            knownType: .value,
            declaredValueLength: value.count,
            valueBytes: value,
            shapeFinding: .fixedLengthKnownType(.value, allowedLengths: [value.count])
        )
    }

    private func observation(
        time: UInt64,
        characteristic: String,
        generation: UInt64,
        id: UInt8,
        value: [UInt8]
    ) throws -> TuyaCandidateDPMessageObservation {
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: try stream(characteristic: characteristic),
            continuityGeneration: generation,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: time,
            lastReceiptUptimeNanoseconds: time
        )
        let candidateRecord = record(id: id, value: value)
        let payload = TuyaCandidateDPPayload(
            dataLengthWidth: .twoByteBigEndian,
            sourceByteCount: 4 + value.count,
            records: [candidateRecord]
        )
        return TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: payload
        )
    }

    private func numericReport(
        generation: UInt64,
        characteristic: String = "C",
        field: String = "Voltage",
        candidateID: UInt8 = 9,
        displayed: [String],
        references: [Double],
        rawValues: [[UInt8]],
        hypotheses: [TuyaCandidateDPNumericTransformHypothesis]? = nil,
        tolerance: Double = 0.000_001
    ) throws -> TuyaCandidateDPNumericHypothesisReport {
        let baseTime = generation * 1_000
        let markerTimes = displayed.indices.map { baseTime + UInt64(($0 + 1) * 100) }
        let markers = try zip(markerTimes, displayed).map { pair in
            try marker(pair.0, pair.1)
        }
        let observations = try zip(markerTimes, rawValues).map { pair in
            try observation(
                time: pair.0,
                characteristic: characteristic,
                generation: generation,
                id: candidateID,
                value: pair.1
            )
        }
        let parent = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(
                field: field,
                characteristic: characteristic,
                generation: generation
            ),
            markers: markers,
            observations: observations,
            policy: correlationPolicy()
        )
        let numericReferences = try references.enumerated().map { index, value in
            try TuyaCandidateDPNumericReference(markerIndex: index, value: value)
        }
        return try TuyaCandidateDPNumericHypothesisEvaluator.evaluate(
            report: parent,
            candidateIndex: 0,
            numericReferences: numericReferences,
            hypotheses: hypotheses ?? [try hypothesis()],
            policy: numericPolicy(tolerance: tolerance)
        )
    }

    @Test("independent sessions retain provenance and common-tolerance descriptive support")
    func aggregatesIndependentSessions() throws {
        let transform = try hypothesis()
        let tolerance = 0.000_001
        let first = try numericReport(
            generation: 7,
            displayed: ["41.3 V", "41.2 V"],
            references: [41.3, 41.2],
            rawValues: [[0x01, 0x9D], [0x01, 0x9C]],
            tolerance: tolerance
        )
        let second = try numericReport(
            generation: 8,
            displayed: ["41.1 V", "41.0 V"],
            references: [41.1, 41.0],
            rawValues: [[0x01, 0x9B], [0x01, 0x9A]],
            tolerance: tolerance
        )
        let result = try #require(
            TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "caller-bound-es80-experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "capture-a", report: first),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "capture-b", report: second)
                ],
                hypothesis: transform,
                policy: crossSessionPolicy()
            )
        )

        #expect(result.subjectIdentifier == "caller-bound-es80-experiment")
        #expect(result.fieldLabel == "Voltage")
        #expect(result.candidate.identifier == 9)
        #expect(result.hypothesis == transform)
        #expect(result.absoluteTolerance == tolerance)
        #expect(result.sessionCount == 2)
        #expect(result.sessions.map(\.continuityGeneration) == [7, 8])
        #expect(result.sessionsWithEvaluableEvidenceCount == 2)
        #expect(result.sessionsWithInToleranceSupportCount == 2)
        #expect(result.sessionsWithAllEvaluableSamplesWithinToleranceCount == 2)
        #expect(result.totalEvaluableSampleCount == 4)
        #expect(result.totalMatchedWithinToleranceCount == 4)
        #expect(result.distinctNumericReferenceValueCount == 4)
        #expect(result.sessions.flatMap(\.samples).map(\.rawUnsignedMagnitude) == [413, 412, 411, 410])
    }

    @Test("contradictory session stays visible under the same exact tolerance")
    func preservesContradictorySession() throws {
        let transform = try hypothesis()
        let tolerance = 0.01
        let matching = try numericReport(
            generation: 1,
            displayed: ["41.3 V", "41.2 V"],
            references: [41.3, 41.2],
            rawValues: [[0x01, 0x9D], [0x01, 0x9C]],
            tolerance: tolerance
        )
        let contradictory = try numericReport(
            generation: 2,
            displayed: ["41.3 V", "41.2 V"],
            references: [41.3, 41.2],
            rawValues: [[0x01, 0xF4], [0x01, 0xF3]],
            tolerance: tolerance
        )
        let result = try #require(
            TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "one", report: matching),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "two", report: contradictory)
                ],
                hypothesis: transform,
                policy: crossSessionPolicy()
            )
        )

        #expect(result.absoluteTolerance == tolerance)
        #expect(result.sessionsWithEvaluableEvidenceCount == 2)
        #expect(result.sessionsWithInToleranceSupportCount == 1)
        #expect(result.sessionsWithAllEvaluableSamplesWithinToleranceCount == 1)
        #expect(result.totalEvaluableSampleCount == 4)
        #expect(result.totalMatchedWithinToleranceCount == 2)
        #expect(result.sessions[0].samples.allSatisfy { $0.isWithinTolerance })
        #expect(result.sessions[1].samples.allSatisfy { !$0.isWithinTolerance })
        #expect(result.sessions[1].samples.allSatisfy { $0.absoluteError > 8 })
    }

    @Test("different caller-owned tolerances cannot be combined")
    func rejectsMixedTolerancePolicies() throws {
        let transform = try hypothesis()
        let strict = try numericReport(
            generation: 3,
            displayed: ["41.3 V"],
            references: [41.3],
            rawValues: [[0x01, 0x9D]],
            tolerance: 0.001
        )
        let loose = try numericReport(
            generation: 4,
            displayed: ["41.2 V"],
            references: [41.2],
            rawValues: [[0x01, 0x9C]],
            tolerance: 1
        )

        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.absoluteToleranceMismatch(index: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "strict", report: strict),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "loose", report: loose)
                ],
                hypothesis: transform,
                policy: crossSessionPolicy()
            )
        }
    }

    @Test("duplicate session labels and exact report reuse fail closed")
    func rejectsDuplicateSessionClaims() throws {
        let report = try numericReport(
            generation: 5,
            displayed: ["41.3 V"],
            references: [41.3],
            rawValues: [[0x01, 0x9D]]
        )
        let first = try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "same", report: report)
        let secondSameLabel = try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "same", report: report)

        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.duplicateSessionIdentifier("same")) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [first, secondSameLabel],
                hypothesis: try hypothesis(),
                policy: crossSessionPolicy()
            )
        }

        let secondDifferentLabel = try TuyaCandidateDPCrossSessionObservation(
            sessionIdentifier: "different-label",
            report: report
        )
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.duplicateSessionEvidence(firstIndex: 0, secondIndex: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [first, secondDifferentLabel],
                hypothesis: try hypothesis(),
                policy: crossSessionPolicy()
            )
        }
    }

    @Test("mixed stream, candidate, and field scopes do not combine")
    func rejectsMixedScope() throws {
        let transform = try hypothesis()
        let baseline = try numericReport(
            generation: 6,
            displayed: ["41.3 V"],
            references: [41.3],
            rawValues: [[0x01, 0x9D]]
        )
        let first = try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "a", report: baseline)

        let otherStream = try numericReport(
            generation: 7,
            characteristic: "D",
            displayed: ["41.2 V"],
            references: [41.2],
            rawValues: [[0x01, 0x9C]]
        )
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.streamIdentityMismatch(index: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    first,
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "b", report: otherStream)
                ],
                hypothesis: transform,
                policy: crossSessionPolicy()
            )
        }

        let otherCandidate = try numericReport(
            generation: 7,
            candidateID: 10,
            displayed: ["41.2 V"],
            references: [41.2],
            rawValues: [[0x01, 0x9C]]
        )
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.candidateMismatch(index: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    first,
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "c", report: otherCandidate)
                ],
                hypothesis: transform,
                policy: crossSessionPolicy()
            )
        }

        let otherField = try numericReport(
            generation: 7,
            field: "Battery",
            displayed: ["41.2"],
            references: [41.2],
            rawValues: [[0x01, 0x9C]]
        )
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.fieldLabelMismatch(index: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    first,
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "d", report: otherField)
                ],
                hypothesis: transform,
                policy: crossSessionPolicy()
            )
        }
    }

    @Test("missing or duplicate selected transforms fail closed")
    func requiresOneExactHypothesisPerSession() throws {
        let selected = try hypothesis()
        let identity = try hypothesis(identifier: "identity", scale: 1)
        let baseline = try numericReport(
            generation: 8,
            displayed: ["41.2 V"],
            references: [41.2],
            rawValues: [[0x01, 0x9C]],
            hypotheses: [selected]
        )

        let missing = try numericReport(
            generation: 9,
            displayed: ["41.3 V"],
            references: [41.3],
            rawValues: [[0x01, 0x9D]],
            hypotheses: [identity]
        )
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.hypothesisNotFound(sessionIndex: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "baseline", report: baseline),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "missing", report: missing)
                ],
                hypothesis: selected,
                policy: crossSessionPolicy()
            )
        }

        let ambiguous = try numericReport(
            generation: 10,
            displayed: ["41.3 V"],
            references: [41.3],
            rawValues: [[0x01, 0x9D]],
            hypotheses: [selected, selected]
        )
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.hypothesisAmbiguous(sessionIndex: 1)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "baseline", report: baseline),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "ambiguous", report: ambiguous)
                ],
                hypothesis: selected,
                policy: crossSessionPolicy()
            )
        }
    }

    @Test("empty input is explicit no-report and work limits preserve the two-session invariant")
    func emptyAndResourceBounds() throws {
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.invalidMaximumSessionCount) {
            try TuyaCandidateDPCrossSessionConsistencyPolicy(maximumSessionCount: 1)
        }

        let empty = try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
            subjectIdentifier: "experiment",
            observations: [],
            hypothesis: hypothesis(),
            policy: crossSessionPolicy(maximum: 2)
        )
        #expect(empty == nil)

        let firstReport = try numericReport(
            generation: 11,
            displayed: ["41.3 V"],
            references: [41.3],
            rawValues: [[0x01, 0x9D]]
        )
        let secondReport = try numericReport(
            generation: 12,
            displayed: ["41.2 V"],
            references: [41.2],
            rawValues: [[0x01, 0x9C]]
        )
        let thirdReport = try numericReport(
            generation: 13,
            displayed: ["41.1 V"],
            references: [41.1],
            rawValues: [[0x01, 0x9B]]
        )
        #expect(throws: TuyaCandidateDPCrossSessionConsistencyError.sessionCountExceedsPolicy(maximum: 2)) {
            try TuyaCandidateDPCrossSessionConsistencyAnalyzer.analyze(
                subjectIdentifier: "experiment",
                observations: [
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "a", report: firstReport),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "b", report: secondReport),
                    try TuyaCandidateDPCrossSessionObservation(sessionIdentifier: "c", report: thirdReport)
                ],
                hypothesis: try hypothesis(),
                policy: crossSessionPolicy(maximum: 2)
            )
        }
    }
}
