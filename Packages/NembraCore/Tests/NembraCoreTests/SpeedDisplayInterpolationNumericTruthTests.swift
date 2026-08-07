import Foundation
import Testing
@testable import NembraCore

@Suite("Speed display numeric truth")
struct SpeedDisplayInterpolationNumericTruthTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        metersPerSecond: Double,
        uptimeNanoseconds: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: epoch
        )
    }

    @Test("finite raw speed whose km/h conversion overflows never becomes a render frame")
    func overflowingDerivedSpeedIsRejectedBeforeFirstFrame() throws {
        var interpolator = SpeedDisplayInterpolator()
        let overflowing = try sample(
            metersPerSecond: Double.greatestFiniteMagnitude,
            uptimeNanoseconds: 1_000
        )

        #expect(overflowing.metersPerSecond.isFinite)
        #expect(!overflowing.kilometersPerHour.isFinite)
        #expect(throws: SpeedDisplayInterpolationError.nonFiniteDisplaySpeed) {
            try interpolator.accept(
                overflowing,
                transitionDurationNanoseconds: 100
            )
        }
        #expect(interpolator.frame(atUptimeNanoseconds: 1_000) == nil)
    }

    @Test("very large representable derived speed is not rejected by a guessed hardware cap")
    func veryLargeRepresentableDerivedSpeedRemainsAccepted() throws {
        var interpolator = SpeedDisplayInterpolator()
        let representable = try sample(
            metersPerSecond: Double.greatestFiniteMagnitude / 4,
            uptimeNanoseconds: 1_000
        )

        #expect(representable.kilometersPerHour.isFinite)
        try interpolator.accept(
            representable,
            transitionDurationNanoseconds: 100
        )

        let frame = try #require(
            interpolator.frame(atUptimeNanoseconds: 1_000)
        )
        #expect(frame.kilometersPerHour.isFinite)
        #expect(frame.kilometersPerHour == representable.kilometersPerHour)
        #expect(frame.latestMeasuredKilometersPerHour == representable.kilometersPerHour)
        #expect(frame.origin == .measured)
    }

    @Test("rejected derived overflow cannot replace the last valid display measurement")
    func overflowingDerivedSpeedIsTransactionalAfterValidMeasurement() throws {
        var interpolator = SpeedDisplayInterpolator()
        let valid = try sample(
            metersPerSecond: 10 / 3.6,
            uptimeNanoseconds: 1_000
        )
        try interpolator.accept(valid, transitionDurationNanoseconds: 0)
        let before = try #require(
            interpolator.frame(atUptimeNanoseconds: 1_000)
        )

        let overflowing = try sample(
            metersPerSecond: Double.greatestFiniteMagnitude,
            uptimeNanoseconds: 2_000
        )
        #expect(throws: SpeedDisplayInterpolationError.nonFiniteDisplaySpeed) {
            try interpolator.accept(
                overflowing,
                transitionDurationNanoseconds: 500
            )
        }

        let after = try #require(
            interpolator.frame(atUptimeNanoseconds: 2_000)
        )
        #expect(after == before)
        #expect(after.kilometersPerHour.isFinite)
        #expect(after.latestMeasuredKilometersPerHour.isFinite)
        #expect(after.latestMeasurementUptimeNanoseconds == 1_000)
    }

    @Test("stale overflowing sample preserves non-monotonic rejection precedence")
    func staleOverflowingSampleStillRejectsAsNonMonotonic() throws {
        var interpolator = SpeedDisplayInterpolator()
        let valid = try sample(
            metersPerSecond: 10 / 3.6,
            uptimeNanoseconds: 2_000
        )
        try interpolator.accept(valid, transitionDurationNanoseconds: 0)
        let before = try #require(
            interpolator.frame(atUptimeNanoseconds: 2_000)
        )

        let staleOverflowing = try sample(
            metersPerSecond: Double.greatestFiniteMagnitude,
            uptimeNanoseconds: 1_500
        )
        #expect(throws: SpeedDisplayInterpolationError.nonMonotonicMeasurement) {
            try interpolator.accept(
                staleOverflowing,
                transitionDurationNanoseconds: 500
            )
        }

        #expect(
            interpolator.frame(atUptimeNanoseconds: 2_100) == before
        )
    }

    @Test("fresh rejected overflow blocks older replay but permits later valid recovery")
    func rejectedOverflowAdvancesObservationChronology() throws {
        var interpolator = SpeedDisplayInterpolator()
        let firstValid = try sample(
            metersPerSecond: 10 / 3.6,
            uptimeNanoseconds: 1_000
        )
        try interpolator.accept(firstValid, transitionDurationNanoseconds: 0)
        let before = try #require(
            interpolator.frame(atUptimeNanoseconds: 1_000)
        )

        let overflowing = try sample(
            metersPerSecond: Double.greatestFiniteMagnitude,
            uptimeNanoseconds: 2_000
        )
        #expect(throws: SpeedDisplayInterpolationError.nonFiniteDisplaySpeed) {
            try interpolator.accept(
                overflowing,
                transitionDurationNanoseconds: 500
            )
        }
        #expect(
            interpolator.frame(atUptimeNanoseconds: 2_000) == before
        )

        let delayedValid = try sample(
            metersPerSecond: 12 / 3.6,
            uptimeNanoseconds: 1_500
        )
        #expect(throws: SpeedDisplayInterpolationError.nonMonotonicMeasurement) {
            try interpolator.accept(
                delayedValid,
                transitionDurationNanoseconds: 500
            )
        }
        #expect(
            interpolator.frame(atUptimeNanoseconds: 2_100) == before
        )

        let laterValid = try sample(
            metersPerSecond: 14 / 3.6,
            uptimeNanoseconds: 3_000
        )
        try interpolator.accept(
            laterValid,
            transitionDurationNanoseconds: 0
        )
        let recovered = try #require(
            interpolator.frame(atUptimeNanoseconds: 3_000)
        )
        #expect(abs(recovered.kilometersPerHour - 14) < 0.000_001)
        #expect(recovered.latestMeasurementUptimeNanoseconds == 3_000)
        #expect(recovered.origin == .measured)
    }
}
