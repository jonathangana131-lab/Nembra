import Testing
@testable import NembraCore

@Suite("Energy Rail display scheduling")
struct PropulsionEnergyRailDisplayScheduleTests {
    @Test("continuous frames stop exactly when canonical interpolation settles")
    func continuousFramesStopAtSettlement() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 100,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))

        let first = runtime.displaySchedule(atUptimeNanoseconds: 1_000)
        #expect(first.requiresContinuousFrames == false)
        #expect(first.nextTransitionUptimeNanoseconds == 2_000_001_001)

        #expect(runtime.acceptLiveSource(
            watts: 400,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 10_000_000,
            continuityGeneration: 1
        ))

        let moving = runtime.displaySchedule(atUptimeNanoseconds: 10_000_000)
        #expect(moving.requiresContinuousFrames)
        #expect(moving.nextTransitionUptimeNanoseconds == 230_000_000)

        let settled = runtime.displaySchedule(atUptimeNanoseconds: 230_000_000)
        #expect(settled.requiresContinuousFrames == false)
        #expect(settled.nextTransitionUptimeNanoseconds == 2_010_000_001)

        let afterPeak = runtime.displaySchedule(atUptimeNanoseconds: 2_010_000_001)
        #expect(afterPeak.requiresContinuousFrames == false)
        #expect(afterPeak.nextTransitionUptimeNanoseconds == 30_010_000_001)

        let retained = runtime.displaySchedule(atUptimeNanoseconds: 30_010_000_001)
        #expect(retained.requiresContinuousFrames == false)
        #expect(retained.nextTransitionUptimeNanoseconds == nil)
        #expect(runtime.projection(
            atUptimeNanoseconds: 30_010_000_001
        ).currentness == .retained)
    }

    @Test("falling power uses the shorter canonical release deadline")
    func fallingPowerUsesReleaseDeadline() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 400,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))
        #expect(runtime.acceptLiveSource(
            watts: 100,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 10_000_000,
            continuityGeneration: 1
        ))

        let moving = runtime.displaySchedule(atUptimeNanoseconds: 10_000_000)
        #expect(moving.requiresContinuousFrames)
        #expect(moving.nextTransitionUptimeNanoseconds == 160_000_000)

        let settled = runtime.displaySchedule(atUptimeNanoseconds: 160_000_000)
        #expect(settled.requiresContinuousFrames == false)
        #expect(settled.nextTransitionUptimeNanoseconds == 2_000_001_001)
    }

    @Test("only a genuine newer equal-watt receipt refreshes presentation deadlines")
    func equalWattsRespectSourceReceiptClock() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 1
        ))
        let original = runtime.displaySchedule(atUptimeNanoseconds: 100)
        let accepted = runtime.projection(atUptimeNanoseconds: 100).acceptedMeasurement

        // Exact replay is idempotent and cannot refresh presentation currentness.
        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 1
        ))
        let replay = runtime.displaySchedule(atUptimeNanoseconds: 500_000_000)
        #expect(replay.nextTransitionUptimeNanoseconds == original.nextTransitionUptimeNanoseconds)
        #expect(runtime.projection(
            atUptimeNanoseconds: 500_000_000
        ).acceptedMeasurement == accepted)

        // A genuine equal-watt source receipt is new measurement evidence and may
        // refresh currentness without inventing a visual delta.
        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 500_000_000,
            continuityGeneration: 1
        ))
        let refreshed = runtime.displaySchedule(atUptimeNanoseconds: 500_000_000)
        let refreshedMeasurement = runtime.projection(
            atUptimeNanoseconds: 500_000_000
        ).acceptedMeasurement

        #expect(refreshed.nextTransitionUptimeNanoseconds == 2_500_000_001)
        #expect(refreshedMeasurement?.receiptSequenceNumber == 2)
        #expect(refreshedMeasurement?.watts == 356)
    }

    @Test("source-retained and unavailable states leave no background display schedule")
    func retainedAndUnavailableAreQuiescent() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.acceptLiveSource(
            watts: 250,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 1
        ))

        let liveBoundary = runtime.displaySchedule(atUptimeNanoseconds: 11_000)
        #expect(liveBoundary.requiresContinuousFrames == false)
        #expect(liveBoundary.nextTransitionUptimeNanoseconds == 11_001)

        // Source custody can demote currentness immediately; render time does not
        // need to wait for the synthetic freshness threshold.
        #expect(runtime.retainSource(
            watts: 250,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 1
        ))
        let retained = runtime.displaySchedule(atUptimeNanoseconds: 10_100)
        #expect(retained.requiresContinuousFrames == false)
        #expect(retained.nextTransitionUptimeNanoseconds == nil)
        #expect(runtime.projection(atUptimeNanoseconds: 10_100).currentness == .retained)

        runtime.markUnavailable()
        let unavailable = runtime.displaySchedule(atUptimeNanoseconds: 12_000)
        #expect(unavailable.requiresContinuousFrames == false)
        #expect(unavailable.nextTransitionUptimeNanoseconds == nil)
        #expect(runtime.projection(atUptimeNanoseconds: 12_000).currentness == .unavailable)
    }
}
