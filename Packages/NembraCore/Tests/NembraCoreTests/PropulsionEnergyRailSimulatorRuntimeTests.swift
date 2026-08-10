import Testing
@testable import NembraCore

@Suite("Energy Rail Simulator source runtime")
struct PropulsionEnergyRailSimulatorRuntimeTests {
    @Test("live source preserves the complete source receipt tuple")
    func liveSourcePreservesExactReceipt() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))

        let projection = runtime.projection(atUptimeNanoseconds: 10_000)
        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 356)
        #expect(projection.acceptedMeasurement?.authority == .simulator)
        #expect(projection.acceptedMeasurement?.receiptSequenceNumber == 7)
        #expect(projection.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_000)
        #expect(projection.acceptedMeasurement?.continuityGeneration == 3)
        #expect(projection.scaleOrigin == .simulator)
        #expect(projection.acceptedTargetFraction == 356.0 / 650.0)
    }

    @Test("newer equal-watt source receipt refreshes currentness without fake value change")
    func newerEqualWattsRefreshCurrentness() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(freshnessNanoseconds: 1_000)

        #expect(runtime.acceptLiveSource(watts: 240, receiptSequenceNumber: 10, receivedAtUptimeNanoseconds: 10_000, continuityGeneration: 1))
        let first = runtime.projection(atUptimeNanoseconds: 10_000)
        #expect(runtime.acceptLiveSource(watts: 240, receiptSequenceNumber: 11, receivedAtUptimeNanoseconds: 10_900, continuityGeneration: 1))
        let refreshed = runtime.projection(atUptimeNanoseconds: 11_500)

        #expect(refreshed.currentness == .live)
        #expect(refreshed.acceptedWatts == 240)
        #expect(refreshed.acceptedMeasurement?.receiptSequenceNumber == 11)
        #expect(refreshed.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_900)
        #expect(first.accessibilityPresentation.acceptedRevision != refreshed.accessibilityPresentation.acceptedRevision)
    }

    @Test("identical live source replay is idempotent")
    func identicalLiveReplayDoesNotMintMeasurement() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.acceptLiveSource(watts: 180, receiptSequenceNumber: 4, receivedAtUptimeNanoseconds: 4_000, continuityGeneration: 2))
        let first = runtime.projection(atUptimeNanoseconds: 4_000)
        #expect(runtime.acceptLiveSource(watts: 180, receiptSequenceNumber: 4, receivedAtUptimeNanoseconds: 4_000, continuityGeneration: 2))
        let replay = runtime.projection(atUptimeNanoseconds: 4_500)
        #expect(replay.acceptedMeasurement == first.acceptedMeasurement)
        #expect(replay.accessibilityPresentation.acceptedRevision == first.accessibilityPresentation.acceptedRevision)
    }

    @Test("one source receipt cannot be relabeled")
    func contradictoryReceiptFailsClosed() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.acceptLiveSource(watts: 200, receiptSequenceNumber: 8, receivedAtUptimeNanoseconds: 8_000, continuityGeneration: 1))
        #expect(runtime.acceptLiveSource(watts: 201, receiptSequenceNumber: 8, receivedAtUptimeNanoseconds: 8_000, continuityGeneration: 1) == false)
        let projection = runtime.projection(atUptimeNanoseconds: 8_100)
        #expect(projection.currentness == .unavailable)
        #expect(projection.acceptedWatts == nil)
        #expect(projection.displayWatts == nil)
    }

    @Test("newer sequence with non-increasing source uptime fails closed")
    func sourceUptimeCannotMoveBackwardsWithinGeneration() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.acceptLiveSource(watts: 200, receiptSequenceNumber: 1, receivedAtUptimeNanoseconds: 10_000, continuityGeneration: 1))
        #expect(runtime.acceptLiveSource(watts: 210, receiptSequenceNumber: 2, receivedAtUptimeNanoseconds: 9_999, continuityGeneration: 1) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 10_000).currentness == .unavailable)
    }

    @Test("stale source callback cannot erase newer evidence")
    func staleCallbackIsIgnored() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.acceptLiveSource(watts: 120, receiptSequenceNumber: 20, receivedAtUptimeNanoseconds: 20_000, continuityGeneration: 2))
        #expect(runtime.acceptLiveSource(watts: 280, receiptSequenceNumber: 22, receivedAtUptimeNanoseconds: 22_000, continuityGeneration: 2))
        #expect(runtime.acceptLiveSource(watts: 999, receiptSequenceNumber: 21, receivedAtUptimeNanoseconds: 23_000, continuityGeneration: 2) == false)
        let projection = runtime.projection(atUptimeNanoseconds: 23_000)
        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 280)
        #expect(projection.acceptedMeasurement?.receiptSequenceNumber == 22)
    }

    @Test("source live to retained is immediate and preserves exact semantic revision")
    func liveToRetainedIsImmediateAndStatic() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(freshnessNanoseconds: 30_000_000_000)
        #expect(runtime.acceptLiveSource(watts: 356, receiptSequenceNumber: 9, receivedAtUptimeNanoseconds: 9_000, continuityGeneration: 4))
        let live = runtime.projection(atUptimeNanoseconds: 9_000)
        #expect(runtime.retainSource(watts: 356, receiptSequenceNumber: 9, receivedAtUptimeNanoseconds: 9_000, continuityGeneration: 4))
        let retained = runtime.projection(atUptimeNanoseconds: 9_001)

        #expect(retained.currentness == .retained)
        #expect(retained.acceptedMeasurement == live.acceptedMeasurement)
        #expect(retained.accessibilityPresentation.acceptedRevision == live.accessibilityPresentation.acceptedRevision)
        #expect(retained.accessibilityPresentation.semanticRevision != live.accessibilityPresentation.semanticRevision)
        #expect(retained.displayWatts == 356)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedTargetFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.scaleOrigin == nil)
        #expect(retained.allowsLiveMotion == false)
        let schedule = runtime.displaySchedule(atUptimeNanoseconds: 9_001)
        #expect(schedule.requiresContinuousFrames == false)
        #expect(schedule.nextTransitionUptimeNanoseconds == nil)
    }

    @Test("cold remount reconstructs exact retained source receipt")
    func coldRemountRetainedPreservesSourceTuple() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.retainSource(watts: 88, receiptSequenceNumber: 12, receivedAtUptimeNanoseconds: 55_000, continuityGeneration: 6))
        let retained = runtime.projection(atUptimeNanoseconds: 55_001)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 88)
        #expect(retained.acceptedMeasurement?.authority == .simulator)
        #expect(retained.acceptedMeasurement?.receiptSequenceNumber == 12)
        #expect(retained.acceptedMeasurement?.receivedAtUptimeNanoseconds == 55_000)
        #expect(retained.acceptedMeasurement?.continuityGeneration == 6)
        #expect(retained.accessibilityPresentation.currentness == .retained)
        #expect(retained.allowsLiveMotion == false)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 55_001).nextTransitionUptimeNanoseconds == nil)
    }

    @Test("retained receipt cannot revive live; newer source generation can")
    func retainedReceiptNeedsNewGenerationToReopenLive() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.retainSource(watts: 300, receiptSequenceNumber: 5, receivedAtUptimeNanoseconds: 5_000, continuityGeneration: 2))
        #expect(runtime.acceptLiveSource(watts: 300, receiptSequenceNumber: 5, receivedAtUptimeNanoseconds: 5_000, continuityGeneration: 2) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 5_100).currentness == .retained)
        #expect(runtime.acceptLiveSource(watts: 300, receiptSequenceNumber: 1, receivedAtUptimeNanoseconds: 100, continuityGeneration: 3))
        let reopened = runtime.projection(atUptimeNanoseconds: 100)
        #expect(reopened.currentness == .live)
        #expect(reopened.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(reopened.acceptedMeasurement?.continuityGeneration == 3)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 100).requiresContinuousFrames == false)
    }

    @Test("explicit unavailable is numeric-free and old receipt cannot reopen")
    func unavailableIsDistinctFromRetained() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.acceptLiveSource(watts: 150, receiptSequenceNumber: 3, receivedAtUptimeNanoseconds: 3_000, continuityGeneration: 1))
        runtime.markUnavailable()
        let unavailable = runtime.projection(atUptimeNanoseconds: 3_001)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)
        #expect(unavailable.displayWatts == nil)
        #expect(unavailable.railFraction == nil)
        #expect(unavailable.allowsLiveMotion == false)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 3_001).nextTransitionUptimeNanoseconds == nil)
        #expect(runtime.acceptLiveSource(watts: 150, receiptSequenceNumber: 3, receivedAtUptimeNanoseconds: 3_000, continuityGeneration: 1) == false)
    }

    @Test("live source naturally ages to retained without changing receipt")
    func freshnessDemotesLiveWithoutChangingReceipt() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(freshnessNanoseconds: 1_000)
        #expect(runtime.acceptLiveSource(watts: 250, receiptSequenceNumber: 2, receivedAtUptimeNanoseconds: 10_000, continuityGeneration: 1))
        let retained = runtime.projection(atUptimeNanoseconds: 11_001)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 250)
        #expect(retained.acceptedMeasurement?.receiptSequenceNumber == 2)
        #expect(retained.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_000)
        #expect(retained.acceptedMeasurement?.continuityGeneration == 1)
        #expect(retained.railFraction == nil)
        #expect(retained.allowsLiveMotion == false)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 11_001).nextTransitionUptimeNanoseconds == nil)
    }

    @Test("display scheduler runs only for bounded live presentation work")
    func displayScheduleIsBounded() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(freshnessNanoseconds: 30_000_000_000)
        #expect(runtime.acceptLiveSource(watts: 100, receiptSequenceNumber: 1, receivedAtUptimeNanoseconds: 1_000_000_000, continuityGeneration: 1))
        let settled = runtime.displaySchedule(atUptimeNanoseconds: 1_000_000_000)
        #expect(settled.requiresContinuousFrames == false)
        #expect(settled.nextTransitionUptimeNanoseconds != nil)

        #expect(runtime.acceptLiveSource(watts: 500, receiptSequenceNumber: 2, receivedAtUptimeNanoseconds: 1_100_000_000, continuityGeneration: 1))
        let animating = runtime.displaySchedule(atUptimeNanoseconds: 1_100_000_000)
        #expect(animating.requiresContinuousFrames)
        #expect(animating.nextTransitionUptimeNanoseconds != nil)
        #expect(animating.nextTransitionUptimeNanoseconds! > 1_100_000_000)

        #expect(runtime.retainSource(watts: 500, receiptSequenceNumber: 2, receivedAtUptimeNanoseconds: 1_100_000_000, continuityGeneration: 1))
        let retained = runtime.displaySchedule(atUptimeNanoseconds: 1_100_000_001)
        #expect(retained.requiresContinuousFrames == false)
        #expect(retained.nextTransitionUptimeNanoseconds == nil)
    }

    @Test("invalid source tuple fails closed")
    func invalidSourceTupleCannotBecomeAuthority() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()
        #expect(runtime.acceptLiveSource(watts: -Double.infinity, receiptSequenceNumber: 1, receivedAtUptimeNanoseconds: 1, continuityGeneration: 1) == false)
        #expect(runtime.retainSource(watts: 10, receiptSequenceNumber: 0, receivedAtUptimeNanoseconds: 1, continuityGeneration: 1) == false)
        #expect(runtime.retainSource(watts: 10, receiptSequenceNumber: 1, receivedAtUptimeNanoseconds: 0, continuityGeneration: 1) == false)
        #expect(runtime.retainSource(watts: 10, receiptSequenceNumber: 1, receivedAtUptimeNanoseconds: 1, continuityGeneration: 0) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 2).currentness == .unavailable)
    }
}
