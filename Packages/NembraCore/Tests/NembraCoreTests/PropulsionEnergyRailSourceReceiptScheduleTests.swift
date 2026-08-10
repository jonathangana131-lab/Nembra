import Testing
@testable import NembraCore

@Suite("Source-receipt Energy Rail display scheduling")
struct PropulsionEnergyRailSourceReceiptScheduleTests {
    @Test("strictly newer source receipt drives bounded interpolation then quiesces")
    func newerReceiptUsesBoundedDisplayClock() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(freshnessNanoseconds: 5_000_000_000)
        let firstUptime: UInt64 = 1_000_000_000
        let secondUptime = firstUptime + 100_000_000

        #expect(runtime.acceptLiveSource(
            watts: 100,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: firstUptime,
            continuityGeneration: 1
        ))
        #expect(runtime.acceptLiveSource(
            watts: 500,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: secondUptime,
            continuityGeneration: 1
        ))

        let moving = runtime.displaySchedule(atUptimeNanoseconds: secondUptime)
        #expect(moving.requiresContinuousFrames)
        #expect(moving.nextTransitionUptimeNanoseconds == secondUptime + 220_000_000)

        let settled = runtime.displaySchedule(
            atUptimeNanoseconds: secondUptime + 220_000_001
        )
        #expect(!settled.requiresContinuousFrames)
        #expect(settled.nextTransitionUptimeNanoseconds != nil)
    }

    @Test("fresh equal watts refresh semantic currentness without fake motion")
    func equalWattsRefreshCurrentnessWithoutInterpolation() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(freshnessNanoseconds: 1_000_000_000)
        let firstUptime: UInt64 = 2_000_000_000
        let secondUptime = firstUptime + 900_000_000

        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: firstUptime,
            continuityGeneration: 4
        ))
        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: secondUptime,
            continuityGeneration: 4
        ))

        let schedule = runtime.displaySchedule(atUptimeNanoseconds: secondUptime)
        #expect(!schedule.requiresContinuousFrames)
        #expect(runtime.projection(
            atUptimeNanoseconds: firstUptime + 1_500_000_000
        ).currentness == .live)
    }

    @Test("explicit retained source is immediately static and has no display wake")
    func retainedSourceIsImmediatelyQuiescent() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        let uptime: UInt64 = 3_000_000_000

        #expect(runtime.acceptLiveSource(
            watts: 240,
            receiptSequenceNumber: 3,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 2
        ))
        #expect(runtime.retainSource(
            watts: 240,
            receiptSequenceNumber: 3,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 2
        ))

        let projection = runtime.projection(atUptimeNanoseconds: uptime + 1)
        #expect(projection.currentness == .retained)
        #expect(projection.acceptedWatts == 240)
        #expect(projection.displayWatts == 240)
        #expect(projection.railFraction == nil)
        #expect(!projection.allowsLiveMotion)

        let schedule = runtime.displaySchedule(atUptimeNanoseconds: uptime + 1)
        #expect(!schedule.requiresContinuousFrames)
        #expect(schedule.nextTransitionUptimeNanoseconds == nil)
    }

    @Test("new continuity generation may restart sequence and uptime after retention")
    func newerGenerationRestartsSourceEpoch() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 300,
            receiptSequenceNumber: 12,
            receivedAtUptimeNanoseconds: 9_000_000_000,
            continuityGeneration: 9
        ))
        #expect(runtime.retainSource(
            watts: 300,
            receiptSequenceNumber: 12,
            receivedAtUptimeNanoseconds: 9_000_000_000,
            continuityGeneration: 9
        ))
        #expect(runtime.acceptLiveSource(
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 10
        ))

        let projection = runtime.projection(atUptimeNanoseconds: 101)
        #expect(projection.currentness == .live)
        #expect(projection.acceptedMeasurement?.continuityGeneration == 10)
        #expect(projection.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(projection.acceptedMeasurement?.receivedAtUptimeNanoseconds == 100)
    }
}
