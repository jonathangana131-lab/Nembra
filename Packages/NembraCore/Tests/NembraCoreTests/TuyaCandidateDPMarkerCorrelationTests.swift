import Testing
@testable import NembraCore

@Suite("Tuya DP marker correlation")
struct TuyaCandidateDPMarkerCorrelationTests {
    private func stream(_ suffix: String = "A") throws -> TuyaCandidateValueStreamIdentity {
        try TuyaCandidateValueStreamIdentity(
            peripheralIdentifier: "P-\(suffix)",
            serviceIdentifier: "S-\(suffix)",
            characteristicIdentifier: "C-\(suffix)"
        )
    }

    private func scope(
        field: String = "Battery",
        streamIdentity: TuyaCandidateValueStreamIdentity? = nil,
        generation: UInt64 = 7,
        width: TuyaCandidateDPDataLengthWidth = .twoByteBigEndian
    ) throws -> TuyaCandidateDPMarkerCorrelationScope {
        try TuyaCandidateDPMarkerCorrelationScope(
            fieldLabel: field,
            streamIdentity: streamIdentity ?? stream(),
            continuityGeneration: generation,
            dataLengthWidth: width
        )
    }

    private func policy(
        distance: UInt64 = 20,
        markers: Int = 32,
        observations: Int = 64,
        occurrences: Int = 256
    ) throws -> TuyaCandidateDPMarkerCorrelationPolicy {
        try TuyaCandidateDPMarkerCorrelationPolicy(
            maximumMarkerDistanceNanoseconds: distance,
            maximumMarkerCount: markers,
            maximumObservationCount: observations,
            maximumCandidateOccurrenceCount: occurrences
        )
    }

    private func marker(_ time: UInt64, _ reference: String) throws -> TuyaCandidateDPStockAppMarker {
        try TuyaCandidateDPStockAppMarker(
            receiptUptimeNanoseconds: time,
            displayedReference: reference
        )
    }

    private func record(
        id: UInt8,
        type: UInt8 = 0x02,
        value: [UInt8],
        offset: Int = 0
    ) -> TuyaCandidateDPRecord {
        let known = TuyaCandidateDPKnownType(rawValue: type)
        let finding: TuyaCandidateDPShapeFinding
        if let known {
            finding = .fixedLengthKnownType(known, allowedLengths: [value.count])
        } else {
            finding = .unknownType(rawType: type)
        }
        return TuyaCandidateDPRecord(
            headerByteOffset: offset,
            valueByteOffset: offset + 4,
            endByteOffsetExclusive: offset + 4 + value.count,
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
        end: UInt64? = nil,
        streamIdentity: TuyaCandidateValueStreamIdentity? = nil,
        generation: UInt64 = 7,
        width: TuyaCandidateDPDataLengthWidth = .twoByteBigEndian,
        records: [TuyaCandidateDPRecord]
    ) throws -> TuyaCandidateDPMessageObservation {
        let identity = try streamIdentity ?? stream()
        let last = end ?? time
        let message = TuyaCandidateReassembledMessage(
            streamIdentity: identity,
            continuityGeneration: generation,
            protocolVersionByte: 0x20,
            protocolVersionHighNibble: 2,
            encryptedBytes: [0xAA],
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: time,
            lastReceiptUptimeNanoseconds: last
        )
        let payload = TuyaCandidateDPPayload(
            dataLengthWidth: width,
            sourceByteCount: records.reduce(0) {
                $0 + $1.endByteOffsetExclusive - $1.headerByteOffset
            },
            records: records
        )
        return TuyaCandidateDPMessageObservation(
            reassembledMessage: message,
            parsedPayload: payload
        )
    }

    @Test("repeated exact reference patterns prioritize a stable opaque DP candidate")
    func ranksRepeatableEqualityPattern() throws {
        let markers = [
            try marker(100, "73%"),
            try marker(300, "73%"),
            try marker(500, "72%")
        ]
        let observations = [
            try observation(time: 95, records: [
                record(id: 17, value: [73]),
                record(id: 99, value: [1], offset: 5)
            ]),
            try observation(time: 295, records: [
                record(id: 17, value: [73]),
                record(id: 99, value: [2], offset: 5)
            ]),
            try observation(time: 495, records: [
                record(id: 17, value: [72]),
                record(id: 99, value: [3], offset: 5)
            ])
        ]
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: markers,
            observations: observations,
            policy: policy()
        )

        #expect(report.candidates.map(\.candidate.identifier) == [17, 99])
        let best = try #require(report.candidates.first)
        #expect(best.matchedMarkerCount == 3)
        #expect(best.sameReferencePairCount == 1)
        #expect(best.sameReferenceSameRawValuePairCount == 1)
        #expect(best.differentReferencePairCount == 2)
        #expect(best.differentReferenceDifferentRawValuePairCount == 2)
        #expect(best.distinctDisplayedReferenceCount == 2)
        #expect(best.distinctRawValueCount == 2)
    }

    @Test("high callback rate cannot create more than one support hit per marker")
    func debiasesHighRateCandidate() throws {
        let observations = [
            try observation(time: 90, records: [record(id: 5, value: [7])]),
            try observation(time: 95, records: [record(id: 5, value: [7])]),
            try observation(time: 105, records: [record(id: 5, value: [7])]),
            try observation(time: 110, records: [record(id: 5, value: [7])])
        ]
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(100, "anchor")],
            observations: observations,
            policy: policy()
        )
        let evidence = try #require(report.candidates.first)
        #expect(report.candidateOccurrenceCount == 4)
        #expect(evidence.matchedMarkerCount == 1)
        #expect(evidence.hits.count == 1)
        #expect(evidence.hits[0].observationIndex == 1)
        #expect(evidence.hits[0].temporalDistanceNanoseconds == 5)
        #expect(evidence.hits[0].temporalRelation == .messageBeforeMarker)
    }

    @Test("equally near conflicting raw values stay ambiguous instead of cherry-picking")
    func rejectsConflictingNearestTie() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(100, "anchor")],
            observations: [
                try observation(time: 95, records: [record(id: 5, value: [1])]),
                try observation(time: 105, records: [record(id: 5, value: [2])])
            ],
            policy: policy()
        )
        let evidence = try #require(report.candidates.first)
        #expect(evidence.matchedMarkerCount == 0)
        #expect(evidence.ambiguousNearestMarkerIndices == [0])
        #expect(evidence.hits.isEmpty)
    }

    @Test("exact display strings are not normalized into fake equivalent references")
    func preservesReferenceFormattingExactly() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(field: "Voltage"),
            markers: [
                try marker(100, "41.3 V"),
                try marker(300, "41.30 V")
            ],
            observations: [
                try observation(time: 100, records: [record(id: 7, value: [0x10, 0x25])]),
                try observation(time: 300, records: [record(id: 7, value: [0x10, 0x25])])
            ],
            policy: policy(distance: 0)
        )
        let evidence = try #require(report.candidates.first)
        #expect(evidence.distinctDisplayedReferenceCount == 2)
        #expect(evidence.differentReferencePairCount == 1)
        #expect(evidence.differentReferenceDifferentRawValuePairCount == 0)
        #expect(evidence.sameReferencePairCount == 0)
    }

    @Test("correlation uses accepted message completion receipt instead of looking through the interval")
    func usesMessageCompletionReceipt() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(105, "anchor")],
            observations: [
                try observation(
                    time: 100,
                    end: 110,
                    records: [record(id: 1, value: [9])]
                )
            ],
            policy: policy(distance: 5)
        )
        let hit = try #require(report.candidates.first?.hits.first)
        #expect(hit.temporalDistanceNanoseconds == 5)
        #expect(hit.temporalRelation == .messageAfterMarker)
        #expect(hit.observationFirstReceiptUptimeNanoseconds == 100)
        #expect(hit.observationLastReceiptUptimeNanoseconds == 110)
    }

    @Test("mixed stream evidence fails closed")
    func rejectsStreamMixing() throws {
        let expected = try stream("A")
        let foreign = try stream("B")
        let observations = [
            try observation(
                time: 100,
                streamIdentity: foreign,
                records: [record(id: 1, value: [1])]
            )
        ]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.observationStreamIdentityMismatch(index: 0)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(streamIdentity: expected),
                markers: [],
                observations: observations,
                policy: policy()
            )
        }
    }

    @Test("continuity generation mixing fails closed")
    func rejectsContinuityMixing() throws {
        let observations = [
            try observation(time: 100, generation: 8, records: [record(id: 1, value: [1])])
        ]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.observationContinuityGenerationMismatch(index: 0)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(generation: 7),
                markers: [],
                observations: observations,
                policy: policy()
            )
        }
    }

    @Test("one-byte and two-byte DP hypotheses cannot be mixed")
    func rejectsLengthWidthMixing() throws {
        let observations = [
            try observation(
                time: 100,
                width: .oneByte,
                records: [record(id: 1, value: [1])]
            )
        ]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.observationLengthWidthMismatch(index: 0)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(width: .twoByteBigEndian),
                markers: [],
                observations: observations,
                policy: policy()
            )
        }
    }

    @Test("out-of-order or overlapping message intervals are not repaired by sorting")
    func rejectsObservationChronologyRepair() throws {
        let observations = [
            try observation(time: 100, end: 110, records: [record(id: 1, value: [1])]),
            try observation(time: 110, end: 120, records: [record(id: 1, value: [2])])
        ]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.nonMonotonicObservationChronology(previousIndex: 0, currentIndex: 1)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(),
                markers: [],
                observations: observations,
                policy: policy()
            )
        }
    }

    @Test("out-of-order markers are rejected instead of silently reordered")
    func rejectsMarkerChronologyRepair() throws {
        let markers = [try marker(200, "A"), try marker(100, "B")]
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.nonMonotonicMarkerChronology(previousIndex: 0, currentIndex: 1)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(),
                markers: markers,
                observations: [],
                policy: policy()
            )
        }
    }

    @Test("same DP id with different raw type remains separate structural candidates")
    func keepsTypeIdentitySeparate() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(100, "A")],
            observations: [
                try observation(time: 100, records: [
                    record(id: 4, type: 0x02, value: [1]),
                    record(id: 4, type: 0x04, value: [1], offset: 5)
                ])
            ],
            policy: policy(distance: 0)
        )
        #expect(report.candidates.count == 2)
        #expect(report.candidates.map(\.candidate.rawType) == [0x02, 0x04])
    }

    @Test("candidate ordering is deterministic when evidence is otherwise tied")
    func deterministicIdentityTieBreak() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(100, "A")],
            observations: [
                try observation(time: 100, records: [
                    record(id: 9, value: [1]),
                    record(id: 1, value: [1], offset: 5)
                ])
            ],
            policy: policy(distance: 0)
        )
        #expect(report.candidates.map(\.candidate.identifier) == [1, 9])
    }

    @Test("analysis resource ceilings fail closed")
    func enforcesResourceBounds() throws {
        let oneMarker = try marker(100, "A")
        let oneObservation = try observation(time: 100, records: [
            record(id: 1, value: [1]),
            record(id: 2, value: [2], offset: 5)
        ])

        #expect(throws: TuyaCandidateDPMarkerCorrelationError.markerCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(),
                markers: [oneMarker, try marker(200, "B")],
                observations: [],
                policy: policy(markers: 1)
            )
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.observationCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(),
                markers: [],
                observations: [
                    oneObservation,
                    try observation(time: 200, records: [])
                ],
                policy: policy(observations: 1)
            )
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.candidateOccurrenceCountExceedsPolicy(maximum: 1)) {
            try TuyaCandidateDPMarkerCorrelator.analyze(
                scope: scope(),
                markers: [],
                observations: [oneObservation],
                policy: policy(occurrences: 1)
            )
        }
    }

    @Test("invalid policy and blank human labels are rejected")
    func rejectsInvalidConfiguration() throws {
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.emptyFieldLabel) {
            try TuyaCandidateDPMarkerCorrelationScope(
                fieldLabel: "  \n",
                streamIdentity: stream(),
                continuityGeneration: 0,
                dataLengthWidth: .oneByte
            )
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.emptyDisplayedReference) {
            try TuyaCandidateDPStockAppMarker(
                receiptUptimeNanoseconds: 1,
                displayedReference: "  "
            )
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidMaximumMarkerCount) {
            try TuyaCandidateDPMarkerCorrelationPolicy(
                maximumMarkerDistanceNanoseconds: 0,
                maximumMarkerCount: 0,
                maximumObservationCount: 1,
                maximumCandidateOccurrenceCount: 1
            )
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidMaximumObservationCount) {
            try TuyaCandidateDPMarkerCorrelationPolicy(
                maximumMarkerDistanceNanoseconds: 0,
                maximumMarkerCount: 1,
                maximumObservationCount: 0,
                maximumCandidateOccurrenceCount: 1
            )
        }
        #expect(throws: TuyaCandidateDPMarkerCorrelationError.invalidMaximumCandidateOccurrenceCount) {
            try TuyaCandidateDPMarkerCorrelationPolicy(
                maximumMarkerDistanceNanoseconds: 0,
                maximumMarkerCount: 1,
                maximumObservationCount: 1,
                maximumCandidateOccurrenceCount: 0
            )
        }
    }

    @Test("no marker support produces no ranked candidate instead of a guessed mapping")
    func omitsUnsupportedCandidates() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [try marker(1_000, "A")],
            observations: [
                try observation(time: 100, records: [record(id: 1, value: [1])])
            ],
            policy: policy(distance: 10)
        )
        #expect(report.candidateOccurrenceCount == 1)
        #expect(report.candidates.isEmpty)
    }
}
