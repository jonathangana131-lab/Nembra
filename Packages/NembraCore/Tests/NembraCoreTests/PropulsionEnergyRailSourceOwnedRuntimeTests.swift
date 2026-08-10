import Testing
@testable import NembraCore

@Suite("Energy Rail source-owned Simulator runtime")
struct PropulsionEnergyRailSourceOwnedRuntimeTests {
    @Test("source retention is immediate and preserves exact accepted receipt")
    func sourceRetentionIsImmediate() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 30_000_000_000
        )

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 240,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))
        let live = runtime.projection(atUptimeNanoseconds: 10_001)
        #expect(live.currentness == .live)
        #expect(live.acceptedWatts == 240)
        #expect(live.acceptedMeasurement?.receiptSequenceNumber == 7)
        #expect(live.acceptedMeasurement?.continuityGeneration == 3)

        #expect(runtime.observeSource(
            currentness: .retained,
            watts: 240,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))

        let retained = runtime.projection(atUptimeNanoseconds: 10_002)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 240)
        #expect(retained.acceptedMeasurement == live.acceptedMeasurement)
        #expect(retained.displayWatts == 240)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedTargetFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.allowsLiveMotion == false)
        #expect(retained.accessibilityPresentation.currentness == .retained)
        #expect(retained.accessibilityPresentation.acceptedRevision
            == live.accessibilityPresentation.acceptedRevision)
    }

    @Test("retained receipt cannot be relabeled live without newer source evidence")
    func retainedReceiptCannotReopenLive() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 4
        ))
        #expect(runtime.observeSource(
            currentness: .retained,
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 4
        ))

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 4
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 101).currentness == .retained)

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 50,
            continuityGeneration: 5
        ))
        let recovered = runtime.projection(atUptimeNanoseconds: 50)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 5)
        #expect(recovered.acceptedMeasurement?.receiptSequenceNumber == 1)
    }

    @Test("new equal-watt source receipt remains distinct accepted evidence")
    func equalWattsAdvanceExactSourceReceipt() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 0,
            receiptSequenceNumber: 10,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 8
        ))
        let first = runtime.projection(atUptimeNanoseconds: 1_000)

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 0,
            receiptSequenceNumber: 11,
            receivedAtUptimeNanoseconds: 1_100,
            continuityGeneration: 8
        ))
        let second = runtime.projection(atUptimeNanoseconds: 1_100)

        #expect(first.acceptedWatts == 0)
        #expect(second.acceptedWatts == 0)
        #expect(first.acceptedMeasurement?.receiptSequenceNumber == 10)
        #expect(second.acceptedMeasurement?.receiptSequenceNumber == 11)
        #expect(first.accessibilityPresentation.acceptedRevision
            != second.accessibilityPresentation.acceptedRevision)
    }

    @Test("stale source receipt cannot erase newer live evidence")
    func staleReceiptIsRejectedWithoutDemotion() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 120,
            receiptSequenceNumber: 4,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 2
        ))
        #expect(runtime.observeSource(
            currentness: .live,
            watts: 260,
            receiptSequenceNumber: 5,
            receivedAtUptimeNanoseconds: 1_100,
            continuityGeneration: 2
        ))

        #expect(runtime.observeSource(
            currentness: .retained,
            watts: 120,
            receiptSequenceNumber: 4,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 2
        ) == false)

        let projection = runtime.projection(atUptimeNanoseconds: 1_100)
        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 260)
        #expect(projection.acceptedMeasurement?.receiptSequenceNumber == 5)
    }

    @Test("source unavailable retires generation and requires newer generation")
    func unavailableFencesGeneration() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 180,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 4_000,
            continuityGeneration: 6
        ))
        #expect(runtime.observeSource(currentness: .unavailable) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 4_001).currentness == .unavailable)

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 190,
            receiptSequenceNumber: 3,
            receivedAtUptimeNanoseconds: 4_100,
            continuityGeneration: 6
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 4_100).currentness == .unavailable)

        #expect(runtime.observeSource(
            currentness: .live,
            watts: 190,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 7
        ))
        let recovered = runtime.projection(atUptimeNanoseconds: 100)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedWatts == 190)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 7)
    }
}
