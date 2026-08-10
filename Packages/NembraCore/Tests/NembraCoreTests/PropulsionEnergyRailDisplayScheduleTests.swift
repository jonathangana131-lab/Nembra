import Testing
@testable import NembraCore

@Suite("Energy Rail display scheduling")
struct PropulsionEnergyRailDisplayScheduleTests {
    @Test("continuous frames stop exactly when canonical interpolation settles")
    func continuousFramesStopAtSettlement() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 100,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 1_000
        ))

        let first = runtime.displaySchedule(atUptimeNanoseconds: 1_000)
        #expect(first.requiresContinuousFrames == false)
        #expect(first.nextTransitionUptimeNanoseconds == 2_000_001_001)

        #expect(runtime.observe(
            connected: true,
            watts: 400,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 10_000_000
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

        #expect(runtime.observe(
            connected: true,
            watts: 400,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 1_000
        ))
        #expect(runtime.observe(
            connected: true,
            watts: 100,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 10_000_000
        ))

        let moving = runtime.displaySchedule(atUptimeNanoseconds: 10_000_000)
        #expect(moving.requiresContinuousFrames)
        #expect(moving.nextTransitionUptimeNanoseconds == 160_000_000)

        let settled = runtime.displaySchedule(atUptimeNanoseconds: 160_000_000)
        #expect(settled.requiresContinuousFrames == false)
        #expect(settled.nextTransitionUptimeNanoseconds == 2_000_001_001)
    }

    @Test("equal watts cannot refresh measurement or presentation deadlines")
    func duplicatePowerDoesNotRefreshSchedule() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 356,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 100
        ))
        let original = runtime.displaySchedule(atUptimeNanoseconds: 100)
        let accepted = runtime.projection(atUptimeNanoseconds: 100).acceptedMeasurement

        #expect(runtime.observe(
            connected: true,
            watts: 356,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 500_000_000
        ))
        let duplicate = runtime.displaySchedule(atUptimeNanoseconds: 500_000_000)
        let stillAccepted = runtime.projection(
            atUptimeNanoseconds: 500_000_000
        ).acceptedMeasurement

        #expect(original.nextTransitionUptimeNanoseconds == 2_000_000_101)
        #expect(duplicate.nextTransitionUptimeNanoseconds == 2_000_000_101)
        #expect(accepted == stillAccepted)
    }

    @Test("disconnect and freshness expiry leave no background display schedule")
    func unavailableAndRetainedAreQuiescent() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.observe(
            connected: true,
            watts: 250,
            modeKey: "eco",
            receivedAtUptimeNanoseconds: 10_000
        ))

        let liveBoundary = runtime.displaySchedule(atUptimeNanoseconds: 11_000)
        #expect(liveBoundary.requiresContinuousFrames == false)
        #expect(liveBoundary.nextTransitionUptimeNanoseconds == 11_001)

        let retained = runtime.displaySchedule(atUptimeNanoseconds: 11_001)
        #expect(retained.requiresContinuousFrames == false)
        #expect(retained.nextTransitionUptimeNanoseconds == nil)
        #expect(runtime.projection(atUptimeNanoseconds: 11_001).currentness == .retained)

        #expect(runtime.observe(
            connected: false,
            watts: nil,
            modeKey: "eco",
            receivedAtUptimeNanoseconds: 12_000
        ) == false)
        let unavailable = runtime.displaySchedule(atUptimeNanoseconds: 12_000)
        #expect(unavailable.requiresContinuousFrames == false)
        #expect(unavailable.nextTransitionUptimeNanoseconds == nil)
    }
}
