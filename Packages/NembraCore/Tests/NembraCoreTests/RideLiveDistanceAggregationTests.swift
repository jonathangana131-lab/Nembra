import Foundation
import Testing
@testable import NembraCore

@Suite("Ride live-distance aggregation")
struct RideLiveDistanceAggregationTests {
    private let rideID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let firstSegmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let secondSegmentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    private func finalizedSegment(
        source: SpeedTelemetrySource = .scooterBluetooth,
        distanceMeters: Double?,
        coverage: RideDistanceCoverage,
        knownGapCount: Int
    ) -> FinalizedLiveDistanceSegment {
        FinalizedLiveDistanceSegment(
            source: source,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 0,
            segmentEndUptimeNanoseconds: 1,
            firstAcceptedSampleUptimeNanoseconds: distanceMeters == nil ? nil : 0,
            lastAcceptedSampleUptimeNanoseconds: distanceMeters == nil ? nil : 1,
            distanceMeters: distanceMeters,
            coverage: coverage,
            acceptedSampleCount: distanceMeters == nil ? 0 : 2,
            integratedIntervalCount: distanceMeters == nil ? 0 : 1,
            knownCoverageGapCount: knownGapCount
        )
    }

    private func evidence(
        segmentID: UUID,
        processSegmentSequence: UInt64,
        source: SpeedTelemetrySource = .scooterBluetooth,
        distanceMeters: Double?,
        coverage: RideDistanceCoverage,
        knownGapCount: Int = 0
    ) throws -> RideLiveDistanceSegmentEvidence {
        try RideLiveDistanceSegmentEvidence(
            rideSessionID: rideID,
            segmentID: segmentID,
            processSegmentSequence: processSegmentSequence,
            finalizedSegment: finalizedSegment(
                source: source,
                distanceMeters: distanceMeters,
                coverage: coverage,
                knownGapCount: knownGapCount
            )
        )
    }

    private func aggregate(
        _ records: [RideLiveDistanceSegmentEvidence],
        source: SpeedTelemetrySource = .scooterBluetooth
    ) throws -> RideLiveDistanceAggregate {
        try RideLiveDistanceAggregator.aggregate(
            rideSessionID: rideID,
            source: source,
            method: .trapezoidalBetweenMeasurements,
            records: records
        )
    }

    @Test("one complete process segment remains complete")
    func oneCompleteSegmentRemainsComplete() throws {
        let record = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 12.5,
            coverage: .complete
        )

        let result = try aggregate([record])

        #expect(result.distanceMeters == 12.5)
        #expect(result.coverage == .complete)
        #expect(result.uniqueSegmentCount == 1)
        #expect(result.distanceEvidenceSegmentCount == 1)
        #expect(result.knownCoverageGapCount == 0)
        #expect(result.unobservedIntervalCount == 0)
    }

    @Test("new process segment automatically preserves an unobserved recovery interval")
    func processRecoveryBoundaryIsStructural() throws {
        let first = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 12.5,
            coverage: .complete
        )
        let recovered = try evidence(
            segmentID: secondSegmentID,
            processSegmentSequence: 1,
            distanceMeters: 7.5,
            coverage: .complete
        )

        let result = try aggregate([recovered, first])

        #expect(result.distanceMeters == 20)
        #expect(result.coverage == .partial)
        #expect(result.uniqueSegmentCount == 2)
        #expect(result.distanceEvidenceSegmentCount == 2)
        #expect(result.knownCoverageGapCount == 1)
        #expect(result.unobservedIntervalCount == 1)
    }

    @Test("identical durable replay is idempotent and never doubles distance")
    func duplicateReplayIsIdempotent() throws {
        let record = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 14,
            coverage: .complete
        )

        let result = try aggregate([record, record, record])

        #expect(result.distanceMeters == 14)
        #expect(result.uniqueSegmentCount == 1)
        #expect(result.duplicateRecordCount == 2)
        #expect(result.unobservedIntervalCount == 0)
    }

    @Test("same segment identity with different evidence fails closed")
    func conflictingDuplicateFailsClosed() throws {
        let first = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 14,
            coverage: .complete
        )
        let conflicting = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 15,
            coverage: .complete
        )

        #expect(throws: RideLiveDistanceAggregationError.conflictingSegment(firstSegmentID)) {
            _ = try aggregate([first, conflicting])
        }
    }

    @Test("different segment identities cannot claim the same process sequence")
    func duplicateProcessSequenceFailsClosed() throws {
        let first = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 14,
            coverage: .complete
        )
        let conflicting = try evidence(
            segmentID: secondSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 15,
            coverage: .complete
        )

        #expect(throws: RideLiveDistanceAggregationError.conflictingProcessSegmentSequence(0)) {
            _ = try aggregate([first, conflicting])
        }
    }

    @Test("missing earlier process segment fails closed instead of inventing ride chronology")
    func nonContiguousProcessSequenceFailsClosed() throws {
        let recoveredOnly = try evidence(
            segmentID: secondSegmentID,
            processSegmentSequence: 1,
            distanceMeters: 8,
            coverage: .complete
        )

        #expect(
            throws: RideLiveDistanceAggregationError.nonContiguousProcessSegmentSequence(
                expected: 0,
                actual: 1
            )
        ) {
            _ = try aggregate([recoveredOnly])
        }
    }

    @Test("unknown segment cannot silently disappear from otherwise known ride distance")
    func unknownSegmentDegradesCoverage() throws {
        let complete = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 9,
            coverage: .complete
        )
        let unknown = try evidence(
            segmentID: secondSegmentID,
            processSegmentSequence: 1,
            distanceMeters: nil,
            coverage: .unknown,
            knownGapCount: 2
        )

        let result = try aggregate([complete, unknown])

        #expect(result.distanceMeters == 9)
        #expect(result.coverage == .partial)
        #expect(result.distanceEvidenceSegmentCount == 1)
        #expect(result.knownCoverageGapCount == 3)
        #expect(result.unobservedIntervalCount == 1)
    }

    @Test("no integrated segment remains unavailable instead of fake zero")
    func noDistanceEvidenceRemainsUnknown() throws {
        let unknown = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: nil,
            coverage: .unknown,
            knownGapCount: 1
        )

        let result = try aggregate([unknown])

        #expect(result.distanceMeters == nil)
        #expect(result.coverage == .unknown)
        #expect(result.distanceEvidenceSegmentCount == 0)
        #expect(result.knownCoverageGapCount == 1)
    }

    @Test("measured zero distance remains real zero evidence")
    func zeroDistanceIsNotUnavailable() throws {
        let stopped = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 0,
            coverage: .complete
        )

        let result = try aggregate([stopped])

        #expect(result.distanceMeters == 0)
        #expect(result.coverage == .complete)
        #expect(result.distanceEvidenceSegmentCount == 1)
    }

    @Test("session and source mixing are rejected rather than averaged")
    func mixedEvidenceFailsClosed() throws {
        let otherRide = try RideLiveDistanceSegmentEvidence(
            rideSessionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            finalizedSegment: finalizedSegment(
                distanceMeters: 4,
                coverage: .complete,
                knownGapCount: 0
            )
        )
        #expect(throws: RideLiveDistanceAggregationError.mismatchedRideSession) {
            _ = try aggregate([otherRide])
        }

        let gps = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            source: .gps,
            distanceMeters: 4,
            coverage: .complete
        )
        #expect(throws: RideLiveDistanceAggregationError.mismatchedSource) {
            _ = try aggregate([gps])
        }
        #expect(throws: RideLiveDistanceAggregationError.invalidExpectedSource) {
            _ = try aggregate([], source: .motionAssist)
        }
    }

    @Test("finite segment distances cannot overflow the ride total")
    func aggregateOverflowFailsClosed() throws {
        let largeDistance = Double.greatestFiniteMagnitude * 0.75
        let first = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: largeDistance,
            coverage: .complete
        )
        let second = try evidence(
            segmentID: secondSegmentID,
            processSegmentSequence: 1,
            distanceMeters: largeDistance,
            coverage: .complete
        )

        #expect(throws: RideLiveDistanceAggregationError.distanceOverflow) {
            _ = try aggregate([first, second])
        }
    }

    @Test("durable segment Codable round trip keeps identity sequence and truth fields")
    func durableSegmentRoundTrip() throws {
        let original = try evidence(
            segmentID: firstSegmentID,
            processSegmentSequence: 0,
            distanceMeters: 5.25,
            coverage: .partial,
            knownGapCount: 2
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RideLiveDistanceSegmentEvidence.self, from: data)

        #expect(decoded == original)
        #expect(decoded.processSegmentSequence == 0)
    }

    @Test("decoded durable evidence must satisfy finalized-segment invariants")
    func decodedImpossibleEvidenceFailsClosed() {
        let json = """
        {
          "rideSessionID": "11111111-1111-1111-1111-111111111111",
          "segmentID": "22222222-2222-2222-2222-222222222222",
          "processSegmentSequence": 0,
          "source": "scooterBluetooth",
          "method": "trapezoidalBetweenMeasurements",
          "distanceMeters": 10,
          "coverage": "unknown",
          "knownCoverageGapCount": 0
        }
        """.data(using: .utf8)!

        #expect(throws: RideLiveDistanceAggregationError.invalidSegmentEvidence) {
            _ = try JSONDecoder().decode(RideLiveDistanceSegmentEvidence.self, from: json)
        }
    }
}
