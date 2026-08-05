import Foundation
import Testing
@testable import NembraCore

@Suite("Render-only speed interpolation")
struct SpeedDisplayInterpolationTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func measuredSample(kph: Double, at nanoseconds: UInt64) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: kph / 3.6,
            receivedAtUptimeNanoseconds: nanoseconds,
            receivedAtDate: epoch
        )
    }

    @Test("first measurement renders immediately instead of animating from fake zero")
    func firstMeasurementIsImmediate() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 14, at: 1_000), transitionDurationNanoseconds: 100)
        let frame = try #require(model.frame(atUptimeNanoseconds: 1_000))
        #expect(abs(frame.kilometersPerHour - 14) < 0.000_001)
        #expect(frame.origin == .measured)
        #expect(frame.transitionProgress == 1)
    }

    @Test("acceleration visually traverses values without overshooting the measurement")
    func acceleratingTransition() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 14, at: 1_000), transitionDurationNanoseconds: 0)
        try model.accept(measuredSample(kph: 20, at: 2_000), transitionDurationNanoseconds: 600)

        let quarter = try #require(model.frame(atUptimeNanoseconds: 2_150))
        let half = try #require(model.frame(atUptimeNanoseconds: 2_300))
        let complete = try #require(model.frame(atUptimeNanoseconds: 2_600))

        #expect(abs(quarter.kilometersPerHour - 15.5) < 0.000_001)
        #expect(abs(half.kilometersPerHour - 17) < 0.000_001)
        #expect(quarter.origin == .visuallyInterpolated)
        #expect(complete.kilometersPerHour == 20)
        #expect(complete.origin == .measured)
    }

    @Test("deceleration moves downward with the same no-overshoot guarantee")
    func deceleratingTransition() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 20, at: 1_000), transitionDurationNanoseconds: 0)
        try model.accept(measuredSample(kph: 14, at: 2_000), transitionDurationNanoseconds: 600)

        let half = try #require(model.frame(atUptimeNanoseconds: 2_300))
        #expect(abs(half.kilometersPerHour - 17) < 0.000_001)
        #expect(half.kilometersPerHour <= 20)
        #expect(half.kilometersPerHour >= 14)
    }

    @Test("a new packet mid-animation starts from the current visual value")
    func interruptionIsContinuous() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 10, at: 1_000), transitionDurationNanoseconds: 0)
        try model.accept(measuredSample(kph: 20, at: 2_000), transitionDurationNanoseconds: 1_000)

        let beforeInterrupt = try #require(model.frame(atUptimeNanoseconds: 2_400))
        #expect(abs(beforeInterrupt.kilometersPerHour - 14) < 0.000_001)

        try model.accept(measuredSample(kph: 24, at: 2_400), transitionDurationNanoseconds: 1_000)
        let atInterrupt = try #require(model.frame(atUptimeNanoseconds: 2_400))
        let later = try #require(model.frame(atUptimeNanoseconds: 2_900))

        #expect(abs(atInterrupt.kilometersPerHour - beforeInterrupt.kilometersPerHour) < 0.000_001)
        #expect(abs(later.kilometersPerHour - 19) < 0.000_001)
    }

    @Test("interpolated frame carries measured target separately and is never raw evidence")
    func frameKeepsTruthBoundary() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 12, at: 1_000), transitionDurationNanoseconds: 0)
        try model.accept(measuredSample(kph: 18, at: 2_000), transitionDurationNanoseconds: 1_000)
        let frame = try #require(model.frame(atUptimeNanoseconds: 2_500))

        #expect(abs(frame.kilometersPerHour - 15) < 0.000_001)
        #expect(abs(frame.latestMeasuredKilometersPerHour - 18) < 0.000_001)
        #expect(frame.origin == .visuallyInterpolated)
        #expect(frame.latestMeasurementUptimeNanoseconds == 2_000)
    }

    @Test("motion-assisted estimates cannot enter the authoritative interpolator")
    func motionEstimateRejected() throws {
        var model = SpeedDisplayInterpolator()
        let motion = try SpeedTelemetrySample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            metersPerSecond: 4,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: epoch
        )

        #expect(throws: SpeedDisplayInterpolationError.nonAuthoritativeInput) {
            try model.accept(motion, transitionDurationNanoseconds: 100)
        }
        #expect(model.frame(atUptimeNanoseconds: 1_100) == nil)
    }

    @Test("out-of-order measurements cannot rewind display history")
    func outOfOrderRejected() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 10, at: 2_000), transitionDurationNanoseconds: 0)
        let old = try measuredSample(kph: 9, at: 1_500)
        #expect(throws: SpeedDisplayInterpolationError.nonMonotonicMeasurement) {
            try model.accept(old, transitionDurationNanoseconds: 100)
        }
        #expect(model.frame(atUptimeNanoseconds: 2_100)?.kilometersPerHour == 10)
    }


    @Test("zero-duration transitions snap exactly to the new measurement")
    func zeroDurationSnap() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 5, at: 1_000), transitionDurationNanoseconds: 0)
        try model.accept(measuredSample(kph: 7, at: 2_000), transitionDurationNanoseconds: 0)
        let frame = try #require(model.frame(atUptimeNanoseconds: 2_000))
        #expect(frame.kilometersPerHour == 7)
        #expect(frame.transitionProgress == 1)
        #expect(frame.origin == .measured)
    }
    @Test("repeated measured value does not create a fake visual transition")
    func repeatedValueStaysMeasured() throws {
        var model = SpeedDisplayInterpolator()
        try model.accept(measuredSample(kph: 16, at: 1_000), transitionDurationNanoseconds: 0)
        try model.accept(measuredSample(kph: 16, at: 2_000), transitionDurationNanoseconds: 1_000)
        let frame = try #require(model.frame(atUptimeNanoseconds: 2_000))
        #expect(frame.kilometersPerHour == 16)
        #expect(frame.origin == .measured)
        #expect(frame.transitionProgress == 1)
    }

}
