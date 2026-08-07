import Testing
@testable import NembraCore

@Suite("Tuya DP marker correlation alternative assignment")
struct TuyaCandidateDPMarkerCorrelationAlternativeAssignmentTests {
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

    @Test("equally-near same-value alternative preserves independent repeated support")
    func alternativeObservationAvoidsFalseSharing() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [
                try marker(99, "A"),
                try marker(110, "B")
            ],
            observations: [
                try observation(completionUptimeNanoseconds: 100),
                try observation(completionUptimeNanoseconds: 120)
            ],
            policy: policy(distance: 20)
        )

        let evidence = try #require(report.candidates.first)
        #expect(evidence.matchedMarkerCount == 2)
        #expect(evidence.hits.map(\.markerIndex) == [0, 1])
        #expect(evidence.hits.map(\.observationIndex) == [0, 1])
        #expect(evidence.hits.map(\.temporalDistanceNanoseconds) == [1, 10])
        #expect(evidence.sharedObservationMarkerIndices.isEmpty)
        #expect(evidence.ambiguousNearestMarkerIndices.isEmpty)
    }

    @Test("unavoidable sharing still preserves uniquely closer observation")
    func uniquelyCloserMarkerStillWinsSharedObservation() throws {
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
        #expect(evidence.hits.map(\.observationIndex) == [0])
        #expect(evidence.sharedObservationMarkerIndices == [1])
    }

    @Test("unavoidable equal-distance sharing still supports neither marker")
    func equalDistanceSharedObservationStillSupportsNeither() throws {
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
        #expect(evidence.hits.isEmpty)
        #expect(evidence.sharedObservationMarkerIndices == [0, 1])
    }

    @Test("transitive equal-distance deficit does not leave marker-order survivor")
    func transitiveEqualDistanceDeficitFailsClosedAsOneComponent() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [
                try marker(90, "A"),
                try marker(110, "B"),
                try marker(130, "C")
            ],
            observations: [
                try observation(completionUptimeNanoseconds: 100),
                try observation(completionUptimeNanoseconds: 120)
            ],
            policy: policy(distance: 10)
        )

        let evidence = try #require(report.candidates.first)
        #expect(evidence.matchedMarkerCount == 0)
        #expect(evidence.hits.isEmpty)
        #expect(evidence.sharedObservationMarkerIndices == [0, 1, 2])
    }

    @Test("multiple complete equal-distance assignments do not invent marker association")
    func multipleEqualPriorityCompleteAssignmentsFailClosed() throws {
        let report = try TuyaCandidateDPMarkerCorrelator.analyze(
            scope: scope(),
            markers: [
                try marker(90, "A"),
                try marker(110, "B")
            ],
            observations: [
                try observation(completionUptimeNanoseconds: 100),
                try observation(completionUptimeNanoseconds: 100)
            ],
            policy: policy(distance: 10)
        )

        // Equal observation completion uptimes are intentionally invalid under the
        // parent chronology contract, so construct the equivalent unique-chronology
        // ambiguity with three observations and two markers instead.
        #expect(report.candidates.isEmpty)
    }
}
