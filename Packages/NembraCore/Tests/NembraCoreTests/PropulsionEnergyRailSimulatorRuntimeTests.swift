import Testing
@testable import NembraCore

@Suite("Propulsion Energy Rail Simulator runtime")
struct PropulsionEnergyRailSimulatorRuntimeTests {
    @Test("unchanged state publications do not mint fake measurement cadence")
    func unchangedWattsDoNotRefreshAcceptedMeasurement() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 100
        )

        #expect(runtime.observe(
            connected: true,
            watts: 356,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_000
        ))

        let first = runtime.projection(atUptimeNanoseconds: 1_050)
        #expect(first.currentness == .live)
        #expect(first.acceptedMeasurement?.authority == .simulator)
        #expect(first.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(first.acceptedMeasurement?.continuityGeneration == 1)
        #expect(first.acceptedMeasurement?.receivedAtUptimeNanoseconds == 1_000)
        #expect(first.acceptedWatts == 356)
        let firstAccepted = first.acceptedMeasurement
        let firstSemanticRevision = first.accessibilityPresentation.semanticRevision

        // A later VehicleState publication with the same semantic watt value is not
        // evidence that a new power measurement arrived. The accepted receipt and
        // semantic revision therefore remain unchanged.
        #expect(runtime.observe(
            connected: true,
            watts: 356,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_075
        ))

        let repeated = runtime.projection(atUptimeNanoseconds: 1_090)
        #expect(repeated.currentness == .live)
        #expect(repeated.acceptedMeasurement == firstAccepted)
        #expect(repeated.accessibilityPresentation.semanticRevision == firstSemanticRevision)

        // Freshness is still measured from the one admitted source change. Repeated
        // equal state snapshots must not keep synthetic power looking live forever.
        let retained = runtime.projection(atUptimeNanoseconds: 1_101)
        #expect(retained.currentness == .retained)
        #expect(retained.acceptedMeasurement == firstAccepted)
        #expect(retained.acceptedWatts == 356)
        #expect(retained.displayWatts == 356)
        #expect(retained.railFraction == nil)
        #expect(retained.acceptedPeakMarkerFraction == nil)
        #expect(retained.allowsLiveMotion == false)
        #expect(retained.accessibilityPresentation.semanticRevision != firstSemanticRevision)
    }

    @Test("disconnect retires authority and recovery starts a newer generation")
    func disconnectRetiresThenRecoversInNewGeneration() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.observe(
            connected: true,
            watts: 180,
            modeKey: "sport",
            receivedAtUptimeNanoseconds: 10_000
        ))
        let live = runtime.projection(atUptimeNanoseconds: 10_100)
        let liveRevision = live.accessibilityPresentation.semanticRevision
        #expect(live.currentness == .live)
        #expect(live.acceptedMeasurement?.authority == .simulator)
        #expect(live.acceptedMeasurement?.continuityGeneration == 1)
        #expect(live.acceptedMeasurement?.receiptSequenceNumber == 1)

        #expect(runtime.observe(
            connected: false,
            watts: 180,
            modeKey: "sport",
            receivedAtUptimeNanoseconds: 10_200
        ) == false)

        let unavailable = runtime.projection(atUptimeNanoseconds: 10_200)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedMeasurement == nil)
        #expect(unavailable.acceptedWatts == nil)
        #expect(unavailable.displayWatts == nil)
        #expect(unavailable.railFraction == nil)
        #expect(unavailable.allowsLiveMotion == false)
        #expect(unavailable.accessibilityPresentation.acceptedWatts == nil)
        #expect(unavailable.accessibilityPresentation.semanticRevision != liveRevision)

        #expect(runtime.observe(
            connected: true,
            watts: 190,
            modeKey: "sport",
            receivedAtUptimeNanoseconds: 10_300
        ))

        let recovered = runtime.projection(atUptimeNanoseconds: 10_350)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedMeasurement?.authority == .simulator)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 2)
        #expect(recovered.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(recovered.acceptedMeasurement?.receivedAtUptimeNanoseconds == 10_300)
        #expect(recovered.acceptedWatts == 190)
    }

    @Test("chronology failure fails closed before a newer generation may recover")
    func nonIncreasingUptimeFailsClosed() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.observe(
            connected: true,
            watts: 240,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 5_000
        ))

        #expect(runtime.observe(
            connected: true,
            watts: 260,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 5_000
        ) == false)

        let failed = runtime.projection(atUptimeNanoseconds: 5_000)
        #expect(failed.currentness == .unavailable)
        #expect(failed.acceptedMeasurement == nil)
        #expect(failed.acceptedWatts == nil)

        // A continuity break creates a newer source generation. Uptime may restart
        // inside that new generation; generation identity prevents replay.
        #expect(runtime.observe(
            connected: true,
            watts: 260,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 100
        ))
        let recovered = runtime.projection(atUptimeNanoseconds: 150)
        #expect(recovered.currentness == .live)
        #expect(recovered.acceptedMeasurement?.continuityGeneration == 2)
        #expect(recovered.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(recovered.acceptedMeasurement?.receivedAtUptimeNanoseconds == 100)
        #expect(recovered.acceptedWatts == 260)
    }

    @Test("mode change creates a distinct simulator identity and chronology")
    func modeChangeRebuildsIdentity() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            vehicleID: "sim-vehicle",
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.observe(
            connected: true,
            watts: 100,
            modeKey: " drive ",
            receivedAtUptimeNanoseconds: 1_000
        ))
        let drive = runtime.projection(atUptimeNanoseconds: 1_050)
        #expect(drive.identity.vehicleID == "sim-vehicle")
        #expect(drive.identity.modeKey == "drive")
        #expect(drive.acceptedMeasurement?.authority == .simulator)
        #expect(drive.acceptedMeasurement?.continuityGeneration == 1)
        #expect(drive.acceptedMeasurement?.receiptSequenceNumber == 1)

        #expect(runtime.observe(
            connected: true,
            watts: 140,
            modeKey: "eco",
            receivedAtUptimeNanoseconds: 2_000
        ))
        let eco = runtime.projection(atUptimeNanoseconds: 2_050)
        #expect(eco.identity.vehicleID == "sim-vehicle")
        #expect(eco.identity.modeKey == "eco")
        #expect(eco.identity != drive.identity)
        #expect(eco.acceptedMeasurement?.identity == eco.identity)
        #expect(eco.acceptedMeasurement?.authority == .simulator)
        #expect(eco.acceptedMeasurement?.continuityGeneration == 1)
        #expect(eco.acceptedMeasurement?.receiptSequenceNumber == 1)
        #expect(eco.acceptedWatts == 140)
    }

    @Test("missing or malformed power never becomes synthetic zero evidence")
    func invalidPowerFailsClosedWithoutInventedZero() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime(
            freshnessNanoseconds: 1_000
        )

        #expect(runtime.observe(
            connected: true,
            watts: 320,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_000
        ))

        #expect(runtime.observe(
            connected: true,
            watts: nil,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_100
        ) == false)
        var unavailable = runtime.projection(atUptimeNanoseconds: 1_100)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)

        #expect(runtime.observe(
            connected: true,
            watts: -1,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_200
        ) == false)
        unavailable = runtime.projection(atUptimeNanoseconds: 1_200)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)

        #expect(runtime.observe(
            connected: true,
            watts: .nan,
            modeKey: "drive",
            receivedAtUptimeNanoseconds: 1_300
        ) == false)
        unavailable = runtime.projection(atUptimeNanoseconds: 1_300)
        #expect(unavailable.currentness == .unavailable)
        #expect(unavailable.acceptedWatts == nil)
    }
}
