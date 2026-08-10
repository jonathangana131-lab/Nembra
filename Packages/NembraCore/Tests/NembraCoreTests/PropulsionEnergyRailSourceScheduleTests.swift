import Testing
@testable import NembraCore

@Suite("Energy Rail source-receipt display scheduling")
struct PropulsionEnergyRailSourceScheduleTests {
    @Test("new live target uses localized continuous frames then settles")
    func liveRetargetSchedulesOnlyRequiredFrames() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 120,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 1
        ))
        let firstSchedule = runtime.displaySchedule(
            atUptimeNanoseconds: 1_000_000_000
        )
        #expect(!firstSchedule.requiresContinuousFrames)
        #expect(firstSchedule.nextTransitionUptimeNanoseconds != nil)

        #expect(runtime.acceptLiveSource(
            watts: 520,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 1_100_000_000,
            continuityGeneration: 1
        ))
        let movingSchedule = runtime.displaySchedule(
            atUptimeNanoseconds: 1_100_000_000
        )
        #expect(movingSchedule.requiresContinuousFrames)
        #expect(movingSchedule.nextTransitionUptimeNanoseconds != nil)

        let settledSchedule = runtime.displaySchedule(
            atUptimeNanoseconds: 1_400_000_000
        )
        #expect(!settledSchedule.requiresContinuousFrames)
        #expect(settledSchedule.nextTransitionUptimeNanoseconds != nil)
    }

    @Test("source retained state is immediately quiescent")
    func retainedSourceStopsDisplayClock() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 2_000_000_000,
            continuityGeneration: 4
        ))
        #expect(runtime.retainSource(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 2_000_000_000,
            continuityGeneration: 4
        ))

        let projection = runtime.projection(atUptimeNanoseconds: 2_000_000_001)
        #expect(projection.currentness == .retained)
        #expect(projection.acceptedWatts == 356)
        #expect(projection.acceptedMeasurement?.receiptSequenceNumber == 7)
        #expect(projection.acceptedMeasurement?.continuityGeneration == 4)

        let schedule = runtime.displaySchedule(
            atUptimeNanoseconds: 2_000_000_001
        )
        #expect(!schedule.requiresContinuousFrames)
        #expect(schedule.nextTransitionUptimeNanoseconds == nil)
    }

    @Test("unavailable source is quiescent and carries no numeric power")
    func unavailableSourceStopsDisplayClock() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 200,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            continuityGeneration: 1
        ))
        runtime.markUnavailable()

        let projection = runtime.projection(atUptimeNanoseconds: 3_000_000_001)
        #expect(projection.currentness == .unavailable)
        #expect(projection.acceptedWatts == nil)

        let schedule = runtime.displaySchedule(
            atUptimeNanoseconds: 3_000_000_001
        )
        #expect(!schedule.requiresContinuousFrames)
        #expect(schedule.nextTransitionUptimeNanoseconds == nil)
    }

    @Test("zero source uptime cannot gain live authority")
    func zeroSourceUptimeFailsClosed() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(!runtime.acceptLiveSource(
            watts: 100,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 0,
            continuityGeneration: 1
        ))
        #expect(runtime.projection(atUptimeNanoseconds: 1).currentness == .unavailable)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 1)
            == PropulsionEnergyRailDisplaySchedule(
                requiresContinuousFrames: false,
                nextTransitionUptimeNanoseconds: nil
            ))
    }
}