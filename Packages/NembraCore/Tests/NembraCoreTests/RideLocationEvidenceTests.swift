import Foundation
import Testing
@testable import NembraCore

@Suite("Ride location quality screening")
struct RideLocationEvidenceTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("raw samples reject invalid coordinates, dates, and accuracy")
    func sampleValidation() {
        #expect(throws: RideLocationEvidenceError.invalidSample) {
            _ = try RideLocationSample(
                latitude: 91,
                longitude: -122,
                sourceMeasurementDate: baseDate,
                receivedAtDate: baseDate,
                receivedAtUptimeNanoseconds: 1,
                horizontalAccuracyMeters: 4,
                isSimulatedBySoftware: false
            )
        }
        #expect(throws: RideLocationEvidenceError.invalidSample) {
            _ = try RideLocationSample(
                latitude: 45,
                longitude: -122,
                sourceMeasurementDate: Date(timeIntervalSinceReferenceDate: .infinity),
                receivedAtDate: baseDate,
                receivedAtUptimeNanoseconds: 1,
                horizontalAccuracyMeters: 4,
                isSimulatedBySoftware: false
            )
        }
        #expect(throws: RideLocationEvidenceError.invalidSample) {
            _ = try RideLocationSample(
                latitude: 45,
                longitude: -122,
                sourceMeasurementDate: baseDate,
                receivedAtDate: baseDate,
                receivedAtUptimeNanoseconds: 1,
                horizontalAccuracyMeters: -1,
                isSimulatedBySoftware: false
            )
        }
    }

    @Test("quality policy has no silently invalid thresholds")
    func policyValidation() {
        #expect(throws: RideLocationEvidenceError.invalidPolicy) {
            _ = try RideLocationQualityPolicy(
                maximumHorizontalAccuracyMeters: 0,
                maximumMeasurementAgeSeconds: 5,
                maximumFutureMeasurementSkewSeconds: 1,
                maximumContinuityGapNanoseconds: 5_000_000_000,
                maximumImpliedSpeedMetersPerSecond: 25,
                allowsSoftwareSimulatedLocations: false
            )
        }
        #expect(throws: RideLocationEvidenceError.invalidPolicy) {
            _ = try RideLocationQualityPolicy(
                maximumHorizontalAccuracyMeters: 20,
                maximumMeasurementAgeSeconds: 5,
                maximumFutureMeasurementSkewSeconds: 1,
                maximumContinuityGapNanoseconds: 0,
                maximumImpliedSpeedMetersPerSecond: 25,
                allowsSoftwareSimulatedLocations: false
            )
        }
    }

    @Test("continuous accepted samples produce only adjacent route distance")
    func continuousDistance() throws {
        var screen = RideLocationQualityScreen(policy: try policy())
        let first = try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 1_000_000_000,
            dateOffset: 0
        )
        let second = try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 2_000_000_000,
            dateOffset: 1
        )

        let firstResult = screen.screen(first)
        guard case let .accepted(firstAccepted) = firstResult else {
            Issue.record("The first valid point should be accepted.")
            return
        }
        #expect(firstAccepted.distanceDeltaMeters == nil)
        #expect(!firstAccepted.startsNewRouteSegment)

        let secondResult = screen.screen(second)
        guard case let .accepted(secondAccepted) = secondResult else {
            Issue.record("The second valid point should be accepted.")
            return
        }
        let delta = try #require(secondAccepted.distanceDeltaMeters)
        #expect(delta > 9)
        #expect(delta < 11)
        #expect(!secondAccepted.startsNewRouteSegment)
    }

    @Test("accuracy, staleness, future dates, and software simulation reject without advancing baseline")
    func basicRejectionsAreTransactional() throws {
        var screen = RideLocationQualityScreen(policy: try policy(allowsSoftwareSimulation: false))
        let first = try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 1_000_000_000,
            dateOffset: 0
        )
        _ = screen.screen(first)

        let inaccurate = try sample(
            latitude: 45.650000,
            longitude: -122.650000,
            uptime: 2_000_000_000,
            dateOffset: 1,
            accuracy: 21
        )
        #expect(screen.screen(inaccurate) == .rejected(.accuracyTooLow))

        let stale = try sample(
            latitude: 45.650000,
            longitude: -122.650000,
            uptime: 3_000_000_000,
            dateOffset: 2,
            measurementAgeSeconds: 6
        )
        #expect(screen.screen(stale) == .rejected(.staleMeasurement))

        let future = try sample(
            latitude: 45.650000,
            longitude: -122.650000,
            uptime: 4_000_000_000,
            dateOffset: 3,
            measurementAgeSeconds: -2
        )
        #expect(screen.screen(future) == .rejected(.futureDatedMeasurement))

        let simulated = try sample(
            latitude: 45.650000,
            longitude: -122.650000,
            uptime: 5_000_000_000,
            dateOffset: 4,
            simulated: true
        )
        #expect(screen.screen(simulated) == .rejected(.softwareSimulationNotAllowed))

        let nearby = try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 5_000_000_000,
            dateOffset: 4
        )
        guard case let .accepted(accepted) = screen.screen(nearby) else {
            Issue.record("Rejected samples must not replace the last accepted baseline.")
            return
        }
        let delta = try #require(accepted.distanceDeltaMeters)
        #expect(delta > 9)
        #expect(delta < 11)
    }

    @Test("non-monotonic reception and implausible jumps fail transactionally")
    func orderingAndJumpRejection() throws {
        var screen = RideLocationQualityScreen(policy: try policy())
        let first = try sample(
            latitude: 45.638700,
            longitude: -122.661500,
            uptime: 10_000_000_000,
            dateOffset: 0
        )
        _ = screen.screen(first)

        let duplicateClock = try sample(
            latitude: 45.638710,
            longitude: -122.661500,
            uptime: 10_000_000_000,
            dateOffset: 0.1
        )
        #expect(screen.screen(duplicateClock) == .rejected(.nonMonotonicReception))

        let jump = try sample(
            latitude: 45.648700,
            longitude: -122.661500,
            uptime: 11_000_000_000,
            dateOffset: 1
        )
        #expect(screen.screen(jump) == .rejected(.implausibleJump))

        let nearby = try sample(
            latitude: 45.638790,
            longitude: -122.661500,
            uptime: 12_000_000_000,
            dateOffset: 2
        )
        guard case let .accepted(accepted) = screen.screen(nearby) else {
            Issue.record("An implausible jump must not poison subsequent good evidence.")
            return
        }
        let delta = try #require(accepted.distanceDeltaMeters)
        #expect(delta > 9)
        #expect(delta < 11)
    }

    @Test("explicit known gap starts a new segment and never invents missing distance")
    func explicitGap() throws {
        var screen = RideLocationQualityScreen(policy: try policy())
        _ = screen.screen(
            try sample(
                latitude: 45.638700,
                longitude: -122.661500,
                uptime: 1_000_000_000,
                dateOffset: 0
            )
        )
        screen.markKnownCoverageGap()

        let afterGap = try sample(
            latitude: 45.650000,
            longitude: -122.650000,
            uptime: 2_000_000_000,
            dateOffset: 1
        )
        guard case let .accepted(accepted) = screen.screen(afterGap) else {
            Issue.record("A valid point after a known gap should begin a new segment.")
            return
        }
        #expect(accepted.startsNewRouteSegment)
        #expect(accepted.distanceDeltaMeters == nil)

        let next = try sample(
            latitude: 45.650090,
            longitude: -122.650000,
            uptime: 3_000_000_000,
            dateOffset: 2
        )
        guard case let .accepted(nextAccepted) = screen.screen(next) else {
            Issue.record("Continuous evidence after the new segment should resume distance accumulation.")
            return
        }
        #expect(!nextAccepted.startsNewRouteSegment)
        #expect(nextAccepted.distanceDeltaMeters != nil)
    }

    @Test("continuity timeout creates a segment boundary instead of a giant distance delta")
    func continuityTimeout() throws {
        var screen = RideLocationQualityScreen(policy: try policy())
        _ = screen.screen(
            try sample(
                latitude: 45.638700,
                longitude: -122.661500,
                uptime: 1_000_000_000,
                dateOffset: 0
            )
        )

        let afterTimeout = try sample(
            latitude: 45.700000,
            longitude: -122.600000,
            uptime: 7_000_000_001,
            dateOffset: 6
        )
        guard case let .accepted(accepted) = screen.screen(afterTimeout) else {
            Issue.record("A valid point after a continuity timeout should be retained as a new segment.")
            return
        }
        #expect(accepted.startsNewRouteSegment)
        #expect(accepted.distanceDeltaMeters == nil)
    }

    @Test("reset drops process-local continuity evidence")
    func resetStartsFresh() throws {
        var screen = RideLocationQualityScreen(policy: try policy())
        _ = screen.screen(
            try sample(
                latitude: 45.638700,
                longitude: -122.661500,
                uptime: 5_000_000_000,
                dateOffset: 0
            )
        )
        screen.reset()

        let fresh = try sample(
            latitude: 45.700000,
            longitude: -122.600000,
            uptime: 1,
            dateOffset: 1
        )
        guard case let .accepted(accepted) = screen.screen(fresh) else {
            Issue.record("A reset screen should accept a new process-local baseline.")
            return
        }
        #expect(accepted.distanceDeltaMeters == nil)
        #expect(!accepted.startsNewRouteSegment)
    }

    private func policy(
        allowsSoftwareSimulation: Bool = true
    ) throws -> RideLocationQualityPolicy {
        try RideLocationQualityPolicy(
            maximumHorizontalAccuracyMeters: 20,
            maximumMeasurementAgeSeconds: 5,
            maximumFutureMeasurementSkewSeconds: 1,
            maximumContinuityGapNanoseconds: 5_000_000_000,
            maximumImpliedSpeedMetersPerSecond: 25,
            allowsSoftwareSimulatedLocations: allowsSoftwareSimulation
        )
    }

    private func sample(
        latitude: Double,
        longitude: Double,
        uptime: UInt64,
        dateOffset: TimeInterval,
        measurementAgeSeconds: TimeInterval = 0,
        accuracy: Double = 4,
        simulated: Bool = false
    ) throws -> RideLocationSample {
        let received = baseDate.addingTimeInterval(dateOffset)
        return try RideLocationSample(
            latitude: latitude,
            longitude: longitude,
            sourceMeasurementDate: received.addingTimeInterval(-measurementAgeSeconds),
            receivedAtDate: received,
            receivedAtUptimeNanoseconds: uptime,
            horizontalAccuracyMeters: accuracy,
            isSimulatedBySoftware: simulated
        )
    }
}
