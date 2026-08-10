import Testing
@testable import NembraCore

@Suite("Energy Rail source-receipt runtime")
struct PropulsionEnergyRailSourceReceiptRuntimeTests {
    @Test("live projection preserves exact source receipt identity")
    func liveProjectionPreservesExactReceipt() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime()

        #expect(runtime.ingestLive(
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
    }

    @Test("equal watts with a newer source receipt advances accepted chronology")
    func equalWattsNewReceiptAdvancesChronology() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime()

        #expect(runtime.ingestLive(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))
        let first = runtime.projection(atUptimeNanoseconds: 10_000)

        #expect(runtime.ingestLive(
            watts: 356,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 11_000,
            continuityGeneration: 3
        ))
        let second = runtime.projection(atUptimeNanoseconds: 11_000)

        #expect(second.currentness == .live)
        #expect(second.acceptedWatts == first.acceptedWatts)
        #expect(second.acceptedMeasurement?.receiptSequenceNumber == 8)
        #expect(second.acceptedMeasurement?.receivedAtUptimeNanoseconds == 11_000)
        #expect(second.accessibilityPresentation.acceptedRevision
            != first.accessibilityPresentation.acceptedRevision)
    }

    @Test("exact live replay is idempotent and does not mint a replacement receipt")
    func exactLiveReplayIsIdempotent() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime()

        #expect(runtime.ingestLive(
            watts: 200,
            receiptSequenceNumber: 4,
            receivedAtUptimeNanoseconds: 5_000,
            continuityGeneration: 2
        ))
        let first = runtime.projection(atUptimeNanoseconds: 5_000)

        #expect(runtime.ingestLive(
            watts: 200,
            receiptSequenceNumber: 4,
            receivedAtUptimeNanoseconds: 5_000,
            continuityGeneration: 2
        ))
        let replay = runtime.projection(atUptimeNanoseconds: 5_100)

        #expect(replay.acceptedMeasurement == first.acceptedMeasurement)
        #expect(replay.accessibilityPresentation.acceptedRevision
            == first.accessibilityPresentation.acceptedRevision)
    }

    @Test("source retained currentness preserves exact watts and disables live motion")
    func liveThenRetainedIsStaticLastKnown() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.ingestLive(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))
        #expect(runtime.ingestRetained(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))

        let retained = runtime.projection(atUptimeNanoseconds: 10_050)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 356)
        #expect(retained.acceptedMeasurement?.receiptSequenceNumber == 7)
        #expect(retained.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_000)
        #expect(retained.acceptedMeasurement?.continuityGeneration == 3)
        #expect(retained.displayWatts == 356)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.allowsLiveMotion == false)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 10_050) == .inactive)
    }

    @Test("fresh runtime receiving retained-only input never exposes a transient live frame")
    func retainedRemountStartsRetained() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.ingestRetained(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))

        let firstVisible = runtime.projection(atUptimeNanoseconds: 10_000)
        #expect(firstVisible.currentness == .retained)
        #expect(firstVisible.acceptedWatts == 356)
        #expect(firstVisible.acceptedMeasurement?.receiptSequenceNumber == 7)
        #expect(firstVisible.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_000)
        #expect(firstVisible.acceptedMeasurement?.continuityGeneration == 3)
        #expect(firstVisible.allowsLiveMotion == false)
        #expect(firstVisible.railFraction == nil)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 10_000) == .inactive)
    }

    @Test("same retained receipt cannot be relabeled live after reconnect")
    func sameReceiptCannotRepromoteRetained() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.ingestRetained(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))

        #expect(runtime.ingestLive(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ) == false)

        let stillRetained = runtime.projection(atUptimeNanoseconds: 10_100)
        #expect(stillRetained.currentness == .retained)
        #expect(stillRetained.acceptedWatts == 356)
    }

    @Test("new source receipt in a newer continuity generation can recover retained power")
    func newerSourceGenerationRecoversRetained() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.ingestRetained(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))
        #expect(runtime.ingestLive(
            watts: 356,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 20_000,
            continuityGeneration: 4
        ))

        let recovered = runtime.projection(atUptimeNanoseconds: 20_000)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedWatts == 356)
        #expect(recovered.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(recovered.acceptedMeasurement?.receivedAtUptimeNanoseconds == 20_000)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 4)
    }

    @Test("source unavailable removes numeric power without manufacturing zero")
    func unavailableHasNoNumericPower() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime()

        #expect(runtime.ingestLive(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ))
        runtime.ingestUnavailable()

        let unavailable = runtime.projection(atUptimeNanoseconds: 10_001)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)
        #expect(unavailable.displayWatts == nil)
        #expect(unavailable.railFraction == nil)
        #expect(unavailable.acceptedPeakMarkerFraction == nil)
        #expect(unavailable.allowsLiveMotion == false)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 10_001) == .inactive)
    }

    @Test("stale receipt inside the same generation fails closed")
    func outOfOrderReceiptFailsClosed() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime()

        #expect(runtime.ingestLive(
            watts: 250,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 11_000,
            continuityGeneration: 3
        ))
        #expect(runtime.ingestLive(
            watts: 300,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 3
        ) == false)

        let unavailable = runtime.projection(atUptimeNanoseconds: 11_001)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)
    }

    @Test("malformed source receipt identity fails closed")
    func malformedReceiptFailsClosed() throws {
        let invalidCases: [(UInt64, UInt64, UInt64)] = [
            (0, 10_000, 3),
            (7, 0, 3),
            (7, 10_000, 0)
        ]

        for (sequence, uptime, generation) in invalidCases {
            var runtime = try PropulsionEnergyRailSourceReceiptRuntime()
            #expect(runtime.ingestLive(
                watts: 356,
                receiptSequenceNumber: sequence,
                receivedAtUptimeNanoseconds: uptime,
                continuityGeneration: generation
            ) == false)
            #expect(runtime.projection(atUptimeNanoseconds: 20_000).currentness == .unavailable)
        }
    }

    @Test("display scheduling exists only while source-live presentation can change")
    func displayScheduleIsQuiescentOutsideLive() throws {
        var runtime = try PropulsionEnergyRailSourceReceiptRuntime(
            freshnessNanoseconds: 30_000_000_000
        )

        #expect(runtime.displaySchedule(atUptimeNanoseconds: 1_000) == .inactive)
        #expect(runtime.ingestLive(
            watts: 100,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))
        #expect(runtime.ingestLive(
            watts: 500,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 1
        ))

        let liveSchedule = runtime.displaySchedule(atUptimeNanoseconds: 2_000)
        #expect(liveSchedule.requiresContinuousFrames)
        #expect(liveSchedule.nextTransitionUptimeNanoseconds != nil)

        #expect(runtime.ingestRetained(
            watts: 500,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 1
        ))
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 2_100) == .inactive)
    }
}
