import Testing
@testable import NembraCore

@Suite("Energy Rail Simulator runtime")
struct PropulsionEnergyRailSimulatorRuntimeTests {
    @Test("connected simulator power is sealed as simulator authority")
    func connectedPowerStaysSimulatorOnly() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 30_000_000_000
        )

        let admitted = runtime.observe(
            connected: true,
            watts: 356,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_000
        )
        #expect(admitted)

        let projection = runtime.projection(atUptimeNanoseconds: 1_000)
        #expect(projection.currentness == .live)
        #expect(projection.acceptedWatts == 356)
        #expect(projection.acceptedMeasurement?.authority == .simulator)
        #expect(projection.acceptedMeasurement?.continuityGeneration == 1)
        #expect(projection.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(projection.scaleOrigin == .simulator)
        #expect(projection.acceptedTargetFraction == 356.0 / 650.0)
    }

    @Test("render polling with unchanged watts does not mint accepted receipts")
    func unchangedPowerDoesNotBecomeDisplayClockTelemetry() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        let firstAdmission = runtime.observe(
            connected: true,
            watts: 356,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_000
        )
        #expect(firstAdmission)
        let first = runtime.projection(atUptimeNanoseconds: 1_000)

        let duplicateAdmission = runtime.observe(
            connected: true,
            watts: 356,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 2_000
        )
        #expect(duplicateAdmission)
        let second = runtime.projection(atUptimeNanoseconds: 2_000)

        #expect(first.acceptedMeasurement == second.acceptedMeasurement)
        #expect(first.accessibilityPresentation.acceptedRevision
            == second.accessibilityPresentation.acceptedRevision)
        #expect(first.accessibilityPresentation.semanticRevision
            == second.accessibilityPresentation.semanticRevision)
    }

    @Test("disconnect makes legacy projection unavailable without manufacturing zero")
    func disconnectIsUnavailableNotMeasuredZero() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        let admitted = runtime.observe(
            connected: true,
            watts: 356,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_000
        )
        #expect(admitted)
        let disconnectedAdmission = runtime.observe(
            connected: false,
            watts: 0,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 2_000
        )
        #expect(disconnectedAdmission == false)

        let projection = runtime.projection(atUptimeNanoseconds: 2_000)
        #expect(projection.currentness == .unavailable)
        #expect(projection.acceptedWatts == nil)
        #expect(projection.displayWatts == nil)
        #expect(projection.railFraction == nil)
        #expect(projection.acceptedPeakMarkerFraction == nil)
        #expect(projection.allowsLiveMotion == false)
    }

    @Test("static accepted simulator power becomes retained after synthetic QA freshness window")
    func syntheticFreshnessDemotesToRetainedWithoutChangingWatts() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        let admitted = runtime.observe(
            connected: true,
            watts: 250,
            modeKey: "eco",
            receivedAtUptimeNanoseconds: 10_000
        )
        #expect(admitted)

        let retained = runtime.projection(atUptimeNanoseconds: 11_001)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 250)
        #expect(retained.displayWatts == 250)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedTargetFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.allowsLiveMotion == false)
        #expect(retained.acceptedMeasurement?.authority == .simulator)
    }

    @Test("source retained lowers currentness without changing accepted receipt")
    func sourceRetainedPreservesExactAcceptedReceiptAndAccessibilityRevision() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 356,
            modeKey: nil,
            sourceObservationRevision: 1,
            receivedAtUptimeNanoseconds: 1_000
        ))
        let live = runtime.projection(atUptimeNanoseconds: 1_000)
        #expect(live.currentness == .live)

        #expect(runtime.retain(sourceObservationRevision: 1))
        let retained = runtime.projection(atUptimeNanoseconds: 1_001)

        #expect(retained.currentness == .retained)
        #expect(retained.acceptedWatts == 356)
        #expect(retained.displayWatts == 356)
        #expect(retained.acceptedMeasurement == live.acceptedMeasurement)
        #expect(retained.accessibilityPresentation.acceptedRevision
            == live.accessibilityPresentation.acceptedRevision)
        #expect(retained.accessibilityPresentation.currentness == .retained)
        #expect(retained.accessibilityPresentation.semanticRevision
            != live.accessibilityPresentation.semanticRevision)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedTargetFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.scaleOrigin == nil)
        #expect(retained.allowsLiveMotion == false)
        let schedule = runtime.displaySchedule(atUptimeNanoseconds: 1_001)
        #expect(schedule.requiresContinuousFrames == false)
        #expect(schedule.nextTransitionUptimeNanoseconds == nil)
    }

    @Test("exact replay cannot promote a retained source receipt")
    func exactSourceReplayKeepsRetainedCurrentness() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            sourceObservationRevision: 4,
            receivedAtUptimeNanoseconds: 10_000
        ))
        #expect(runtime.retain(sourceObservationRevision: 4))

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            sourceObservationRevision: 4,
            receivedAtUptimeNanoseconds: 10_000
        ))
        #expect(runtime.projection(atUptimeNanoseconds: 20_000).currentness == .retained)
    }

    @Test("wrong source revision cannot retain a newer live measurement")
    func wrongSourceRevisionCannotDemoteLiveMeasurement() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 275,
            modeKey: nil,
            sourceObservationRevision: 7,
            receivedAtUptimeNanoseconds: 7_000
        ))
        let before = runtime.projection(atUptimeNanoseconds: 7_000)

        #expect(runtime.retain(sourceObservationRevision: 6) == false)
        let after = runtime.projection(atUptimeNanoseconds: 7_000)
        #expect(after == before)
        #expect(after.currentness == .live)
    }

    @Test("new equal-watt source receipt after retained starts a fresh local generation")
    func newerEqualWattsAfterRetainedCannotInterpolateAcrossGap() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            sourceObservationRevision: 1,
            receivedAtUptimeNanoseconds: 1_000
        ))
        let first = runtime.projection(atUptimeNanoseconds: 1_000)
        #expect(runtime.retain(sourceObservationRevision: 1))

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            sourceObservationRevision: 2,
            receivedAtUptimeNanoseconds: 2_000
        ))
        let recovered = runtime.projection(atUptimeNanoseconds: 2_000)

        #expect(first.acceptedMeasurement?.continuityGeneration == 1)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedWatts == 300)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 2)
        #expect(recovered.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(recovered.acceptedMeasurement?.authority == .simulator)
        #expect(recovered.displayWatts == 300)
        #expect(runtime.displaySchedule(atUptimeNanoseconds: 2_000).requiresContinuousFrames == false)
    }

    @Test("stale pre-gap source receipt cannot revive after a newer source receipt")
    func staleSourceRevisionCannotEraseNewerRecoveredTruth() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            sourceObservationRevision: 1,
            receivedAtUptimeNanoseconds: 1_000
        ))
        #expect(runtime.retain(sourceObservationRevision: 1))
        #expect(runtime.observe(
            connected: true,
            watts: 320,
            modeKey: nil,
            sourceObservationRevision: 2,
            receivedAtUptimeNanoseconds: 2_000
        ))
        let newest = runtime.projection(atUptimeNanoseconds: 2_000)

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            sourceObservationRevision: 1,
            receivedAtUptimeNanoseconds: 1_000
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 2_000) == newest)
    }

    @Test("legacy no-revision caller cannot bypass an established source chronology")
    func legacyObservationCannotReviveSourceRetainedTruth() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            sourceObservationRevision: 1,
            receivedAtUptimeNanoseconds: 1_000
        ))
        #expect(runtime.retain(sourceObservationRevision: 1))

        #expect(runtime.observe(
            connected: true,
            watts: 300,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 2_000
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 2_000).currentness == .retained)
    }

    @Test("contradictory equal source revision fails closed")
    func equalSourceRevisionCannotRelabelWatts() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 200,
            modeKey: nil,
            sourceObservationRevision: 9,
            receivedAtUptimeNanoseconds: 9_000
        ))
        #expect(runtime.observe(
            connected: true,
            watts: 201,
            modeKey: nil,
            sourceObservationRevision: 9,
            receivedAtUptimeNanoseconds: 9_000
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 9_000).currentness == .unavailable)
    }

    @Test("new source sequence with non-increasing source uptime fails closed")
    func sourceSequenceCannotRedateEvidenceBackwards() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        #expect(runtime.observe(
            connected: true,
            watts: 200,
            modeKey: nil,
            sourceObservationRevision: 1,
            receivedAtUptimeNanoseconds: 10_000
        ))
        #expect(runtime.observe(
            connected: true,
            watts: 210,
            modeKey: nil,
            sourceObservationRevision: 2,
            receivedAtUptimeNanoseconds: 9_999
        ) == false)
        #expect(runtime.projection(atUptimeNanoseconds: 10_000).currentness == .unavailable)
    }

    @Test("reconnect with same watts starts newer generation")
    func reconnectStartsNewGenerationEvenWhenWattsMatch() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        let firstAdmission = runtime.observe(
            connected: true,
            watts: 300,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 100
        )
        #expect(firstAdmission)
        let first = runtime.projection(atUptimeNanoseconds: 100)

        let disconnectAdmission = runtime.observe(
            connected: false,
            watts: nil,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 200
        )
        #expect(disconnectAdmission == false)
        let reconnectAdmission = runtime.observe(
            connected: true,
            watts: 300,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 50
        )
        #expect(reconnectAdmission)
        let recovered = runtime.projection(atUptimeNanoseconds: 50)

        #expect(first.acceptedMeasurement?.continuityGeneration == 1)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedWatts == 300)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 2)
        #expect(recovered.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(recovered.acceptedMeasurement?.authority == .simulator)
    }

    @Test("mode change rebinds identity instead of carrying old normalized geometry")
    func modeChangeRebuildsIdentityAndScale() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        let ecoAdmission = runtime.observe(
            connected: true,
            watts: 200,
            modeKey: "eco",
            receivedAtUptimeNanoseconds: 1_000
        )
        #expect(ecoAdmission)
        let eco = runtime.projection(atUptimeNanoseconds: 1_000)

        let sportAdmission = runtime.observe(
            connected: true,
            watts: 200,
            modeKey: "sport",
            receivedAtUptimeNanoseconds: 500
        )
        #expect(sportAdmission)
        let sport = runtime.projection(atUptimeNanoseconds: 500)

        #expect(eco.identity.modeKey == "eco")
        #expect(sport.identity.modeKey == "sport")
        #expect(sport.currentness == .live)
        #expect(sport.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(sport.acceptedMeasurement?.continuityGeneration == 1)
        #expect(sport.acceptedMeasurement?.authority == .simulator)
        #expect(sport.acceptedTargetFraction == 200.0 / 650.0)
    }

    @Test("invalid connected power fails closed and later valid sample needs new generation")
    func invalidPowerCannotRemainLive() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime()

        let firstAdmission = runtime.observe(
            connected: true,
            watts: 120,
            modeKey: "walk",
            receivedAtUptimeNanoseconds: 100
        )
        #expect(firstAdmission)
        let invalidAdmission = runtime.observe(
            connected: true,
            watts: -Double.infinity,
            modeKey: "walk",
            receivedAtUptimeNanoseconds: 200
        )
        #expect(invalidAdmission == false)
        #expect(runtime.projection(atUptimeNanoseconds: 200).currentness == .unavailable)

        let recoveredAdmission = runtime.observe(
            connected: true,
            watts: 120,
            modeKey: "walk",
            receivedAtUptimeNanoseconds: 50
        )
        #expect(recoveredAdmission)
        let recovered = runtime.projection(atUptimeNanoseconds: 50)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 2)
        #expect(recovered.acceptedMeasurement?.receiptSequenceNumber == 1)
    }
}
