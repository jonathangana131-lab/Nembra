import Foundation
import Testing
@testable import NembraCore

@Suite("Ride location authorization truth")
struct RideLocationAuthorizationTests {
    @Test("reduced-accuracy location is rejected as route evidence without advancing the baseline")
    func reducedAccuracyIsRejectedTransactionally() throws {
        let policy = try RideLocationQualityPolicy(
            maximumHorizontalAccuracyMeters: 20,
            maximumMeasurementAgeSeconds: 5,
            maximumFutureMeasurementSkewSeconds: 1,
            maximumContinuityGapNanoseconds: 5_000_000_000,
            maximumImpliedSpeedMetersPerSecond: 25,
            allowsSoftwareSimulatedLocations: false
        )
        var screen = RideLocationQualityScreen(policy: policy)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try RideLocationSample(
            latitude: 45.638700,
            longitude: -122.661500,
            sourceMeasurementDate: baseDate,
            receivedAtDate: baseDate,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            horizontalAccuracyMeters: 4,
            isAccuracyLimited: false,
            isSimulatedBySoftware: false
        )
        _ = screen.screen(first)

        let reducedAccuracy = try RideLocationSample(
            latitude: 45.700000,
            longitude: -122.600000,
            sourceMeasurementDate: baseDate.addingTimeInterval(1),
            receivedAtDate: baseDate.addingTimeInterval(1),
            receivedAtUptimeNanoseconds: 2_000_000_000,
            horizontalAccuracyMeters: 4,
            isAccuracyLimited: true,
            isSimulatedBySoftware: false
        )
        #expect(screen.screen(reducedAccuracy) == .rejected(.reducedAccuracyAuthorization))

        let nearby = try RideLocationSample(
            latitude: 45.638790,
            longitude: -122.661500,
            sourceMeasurementDate: baseDate.addingTimeInterval(2),
            receivedAtDate: baseDate.addingTimeInterval(2),
            receivedAtUptimeNanoseconds: 3_000_000_000,
            horizontalAccuracyMeters: 4,
            isAccuracyLimited: false,
            isSimulatedBySoftware: false
        )

        guard case let .accepted(accepted) = screen.screen(nearby) else {
            return Issue.record("Reduced-accuracy evidence must not replace the last precise accepted baseline.")
        }
        let delta = try #require(accepted.distanceDeltaMeters)
        #expect(delta > 9)
        #expect(delta < 11)
        #expect(!accepted.startsNewRouteSegment)
    }
}
