import Foundation
import Testing
@testable import NembraCore

@Suite("Ride live-distance pipeline integration")
struct RideLiveDistancePipelineIntegrationTests {
    @Test("authoritative samples survive finalization and durable aggregation without invented gap distance")
    func authoritativeSegmentFlowsIntoAggregate() throws {
        let policy = try LiveDistanceIntegrationPolicy(
            source: .scooterBluetooth,
            maximumIntegrationIntervalNanoseconds: 1_000_000_000,
            method: .trapezoidalBetweenMeasurements
        )
        var accumulator = LiveDistanceSegmentAccumulator(
            policy: policy,
            segmentStartUptimeNanoseconds: 0
        )
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: 10,
            receivedAtUptimeNanoseconds: 0,
            receivedAtDate: epoch
        )
        let second = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: 10,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            receivedAtDate: epoch.addingTimeInterval(1)
        )

        #expect(accumulator.record(first) == .anchored)
        #expect(accumulator.record(second) == .integrated(addedMeters: 10))

        let finalized = try accumulator.finalize(
            segmentEndUptimeNanoseconds: 1_000_000_000
        )
        #expect(finalized.distanceMeters == 10)
        #expect(finalized.coverage == .complete)

        let rideID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let segmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let durable = try RideLiveDistanceSegmentEvidence(
            rideSessionID: rideID,
            segmentID: segmentID,
            finalizedSegment: finalized,
            followsUnobservedInterval: false
        )
        let aggregate = try RideLiveDistanceAggregator.aggregate(
            rideSessionID: rideID,
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            records: [durable]
        )

        #expect(aggregate.distanceMeters == 10)
        #expect(aggregate.coverage == .complete)
        #expect(aggregate.uniqueSegmentCount == 1)
        #expect(aggregate.knownCoverageGapCount == 0)
    }
}
