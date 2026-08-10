import Testing
@testable import NembraCore

@Suite("Energy Rail Simulator source runtime")
struct PropulsionEnergyRailSimulatorRuntimeTests {
    @Test("live source preserves exact receipt provenance")
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

    @Test("newer equal-watt source receipt refreshes accepted currentness")
    func newerEqualWattsRefreshSourceCurrentness() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.acceptLiveSource(
            watts: 240,
            receiptSequenceNumber: 10,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 1
        ))
        let first = runtime.projection(atUptimeNanoseconds: 10_000)

        #expect(runtime.acceptLiveSource(
            watts: 240,
            receiptSequenceNumber: 11,
            receivedAtUptimeNanoseconds: 10_900,
            continuityGeneration: 1
        ))
        let refreshed = runtime.projection(atUptimeNanoseconds: 11_500)

        #expect(refreshed.currentness == .live)
        #expect(refreshed.acceptedWatts == 240)
        #expect(refreshed.acceptedMeasurement?.receiptSequenceNumber == 11)
        #expect(refreshed.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_900)
        #expect(first.accessibilityPresentation.acceptedRevision
            != refreshed.accessibilityPresentation.acceptedRevision)
    }

    @Test("identical live receipt replay is idempotent")
    func identicalLiveReceiptDoesNotMintMeasurement() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 180,
            receiptSequenceNumber: 4,
            receivedAtUptimeNanoseconds: 4_000,
            continuityGeneration: 2
        ))
        let first = runtime.projection(atUptimeNanoseconds: 4_000)

        #expect(runtime.acceptLiveSource(
            watts: 180,
            receiptSequenceNumber: 4,
            receivedAtUptimeNanoseconds: 4_000,
            continuityGeneration: 2
        ))
        let replay = runtime.projection(atUptimeNanoseconds: 4_500)

        #expect(replay.acceptedMeasurement == first.acceptedMeasurement)
        #expect(replay.accessibilityPresentation.acceptedRevision
            == first.accessibilityPresentation.acceptedRevision)
    }

    @Test("one source receipt cannot be relabeled with different watts")
    func contradictoryReceiptFailsClosed() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 200,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 8_000,
            continuityGeneration: 1
        ))
        #expect(runtime.acceptLiveSource(
            watts: 201,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 8_000,
            continuityGeneration: 1
        ) == false)

        let projection = runtime.projection(atUptimeNanoseconds: 8_100)
        #expect(projection.currentness == .unavailable)
        #expect(projection.acceptedWatts == nil)
        #expect(projection.displayWatts == nil)
    }

    @Test("stale source callback cannot erase newer live evidence")
    func staleSourceCallbackIsIgnored() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 120,
            receiptSequenceNumber: 20,
            receivedAtUptimeNanoseconds: 20_000,
            continuityGeneration: 2
        ))
        #expect(runtime.acceptLiveSource(
            watts: 280,
            receiptSequenceNumber: 22,
            receivedAtUptimeNanoseconds: 22_000,
            continuityGeneration: 2
        ))

        #expect(runtime.acceptLiveSource(
            watts: 999,
            receiptSequenceNumber: 21,
            receivedAtUptimeNanoseconds: 23_000,
            continuityGeneration: 2
        ) == false)

        let projection = runtime.projection(atUptimeNanoseconds: 23_000)
        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 280)
        #expect(projection.acceptedMeasurement?.receiptSequenceNumber == 22)
    }

    @Test("source demotion becomes retained immediately without render-clock aging")
    func liveToRetainedIsImmediateAndStatic() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 30_000_000_000
        )

        #expect(runtime.acceptLiveSource(
            watts: 356,
            receiptSequenceNumber: 9,
            receivedAtUptimeNanoseconds: 9_000,
            continuityGeneration: 4
        ))
        #expect(runtime.retainSource(
            watts: 356,
            receiptSequenceNumber: 9,
            receivedAtUptimeNanoseconds: 9_000,
            continuityGeneration: 4
        ))

        // This render time is far inside the synthetic freshness window. Retained
        // state therefore comes from source currentness, not an aged display clock.
        let retained = runtime.projection(atUptimeNanoseconds: 9_001)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 356)
        #expect(retained.displayWatts == 356)
        #expect(retained.acceptedMeasurement?.receiptSequenceNumber == 9)
        #expect(retained.acceptedMeasurement?.receivedAtUptimeNanoseconds == 9_000)
        #expect(retained.acceptedMeasurement?.continuityGeneration == 4)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedTargetFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.scaleOrigin == nil)
        #expect(retained.allowsLiveMotion == false)
        #expect(retained.accessibilityPresentation.currentness == .retained)
        #expect(retained.accessibilityPresentation.acceptedWatts == 356)
    }

    @Test("cold runtime can reconstruct exact retained source receipt")
    func coldRemountRetainedPreservesSourceTuple() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.retainSource(
            watts: 88,
            receiptSequenceNumber: 12,
            receivedAtUptimeNanoseconds: 55_000,
            continuityGeneration: 6
        ))

        let retained = runtime.projection(atUptimeNanoseconds: 55_001)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 88)
        #expect(retained.acceptedMeasurement?.authority == .simulator)
        #expect(retained.acceptedMeasurement?.receiptSequenceNumber == 12)
        #expect(retained.acceptedMeasurement?.receivedAtUptimeNanoseconds == 55_000)
        #expect(retained.acceptedMeasurement?.continuityGeneration == 6)
        #expect(retained.allowsLiveMotion == false)
    }

    @Test("retained receipt cannot revive live; newer generation can")
    func retainedReceiptRequiresNewSourceGenerationToReopenLive() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.retainSource(
            watts: 300,
            receiptSequenceNumber: 5,
            receivedAtUptimeNanoseconds: 5_000,
            continuityGeneration: 2
        ))

        #expect(runtime.acceptLiveSource(
            watts: 300,
            receiptSequenceNumber: 5,
            receivedAtUptimeNanoseconds: 5_000,
            continuityGeneration: 2
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 5_100).currentness == .retained)

        #expect(runtime.acceptLiveSource(
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 3
        ))
        let reopened = runtime.projection(atUptimeNanoseconds: 100)
        #expect(reopened.currentness == .live)
        #expect(reopened.acceptedWatts == 300)
        #expect(reopened.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(reopened.acceptedMeasurement?.continuityGeneration == 3)
    }

    @Test("explicit unavailable has no numeric power and old receipt cannot reopen")
    func unavailableIsDistinctFromRetained() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: 150,
            receiptSequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3_000,
            continuityGeneration: 1
        ))
        runtime.markUnavailable()

        let unavailable = runtime.projection(atUptimeNanoseconds: 3_001)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)
        #expect(unavailable.displayWatts == nil)
        #expect(unavailable.railFraction == nil)
        #expect(unavailable.allowsLiveMotion == false)

        #expect(runtime.acceptLiveSource(
            watts: 150,
            receiptSequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3_000,
            continuityGeneration: 1
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 3_002).currentness == .unavailable)
    }

    @Test("live sample still ages to retained from accepted measurement clock")
    func freshnessDemotesLiveWithoutChangingReceipt() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.acceptLiveSource(
            watts: 250,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 1
        ))

        let retained = runtime.projection(atUptimeNanoseconds: 11_001)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 250)
        #expect(retained.displayWatts == 250)
        #expect(retained.acceptedMeasurement?.receiptSequenceNumber == 2)
        #expect(retained.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_000)
        #expect(retained.acceptedMeasurement?.continuityGeneration == 1)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedTargetFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.allowsLiveMotion == false)
    }

    @Test("invalid source tuple fails closed")
    func invalidSourceTupleCannotBecomePowerAuthority() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.acceptLiveSource(
            watts: -.infinity,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            continuityGeneration: 1
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 1).currentness == .unavailable)

        #expect(runtime.retainSource(
            watts: 10,
            receiptSequenceNumber: 0,
            receivedAtUptimeNanoseconds: 1,
            continuityGeneration: 1
        ) == false)
        #expect(runtime.retainSource(
            watts: 10,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            continuityGeneration: 0
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 2).currentness == .unavailable)
    }
}
