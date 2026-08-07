import Testing
@testable import NembraCore

@Suite("Propulsion cockpit identity provenance")
struct PropulsionGaugeCockpitIdentityProvenanceTests {
    private func identity(
        vehicleID: String,
        modeKey: String? = nil
    ) throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: vehicleID, modeKey: modeKey)
    }

    private func model(
        identity: PropulsionGaugeIdentity
    ) throws -> PropulsionGaugeDisplayModel {
        PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 500_000_000,
                fallSettlingDurationNanoseconds: 250_000_000,
                acceptedPeakHoldNanoseconds: 750_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: 2_000_000_000
            )
        )
    }

    private func sample(
        identity: PropulsionGaugeIdentity,
        watts: Double = 640,
        receipt: UInt64 = 7,
        uptime: UInt64 = 1_000_000_000
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 1
        )
    }

    @Test("unavailable snapshots remain bound to exact vehicle identity")
    func unavailableSnapshotsKeepVehicleIdentity() throws {
        let firstIdentity = try identity(vehicleID: "es80-a")
        let secondIdentity = try identity(vehicleID: "es80-b")
        let first = try model(identity: firstIdentity).cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: nil
        )
        let second = try model(identity: secondIdentity).cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: nil
        )

        #expect(first.measurement == .unavailable)
        #expect(second.measurement == .unavailable)
        #expect(first.identity == firstIdentity)
        #expect(second.identity == secondIdentity)
        #expect(first != second)
    }

    @Test("detached accepted measurements cannot compare equal across vehicles")
    func acceptedMeasurementsKeepVehicleIdentity() throws {
        let firstIdentity = try identity(vehicleID: "es80-a")
        let secondIdentity = try identity(vehicleID: "es80-b")
        var firstModel = try model(identity: firstIdentity)
        var secondModel = try model(identity: secondIdentity)

        try firstModel.accept(sample(identity: firstIdentity))
        try secondModel.accept(sample(identity: secondIdentity))

        let first = firstModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: try .simulator(identity: firstIdentity, ceilingWatts: 800)
        )
        let second = secondModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: try .simulator(identity: secondIdentity, ceilingWatts: 800)
        )

        guard case let .live(firstMeasurement) = first.measurement,
              case let .live(secondMeasurement) = second.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(firstMeasurement.identity == firstIdentity)
        #expect(secondMeasurement.identity == secondIdentity)
        #expect(firstMeasurement.watts == secondMeasurement.watts)
        #expect(firstMeasurement.receiptSequenceNumber == secondMeasurement.receiptSequenceNumber)
        #expect(firstMeasurement.receivedAtUptimeNanoseconds == secondMeasurement.receivedAtUptimeNanoseconds)
        #expect(firstMeasurement.authority == secondMeasurement.authority)
        #expect(firstMeasurement != secondMeasurement)
        #expect(first != second)
    }

    @Test("confirmed mode remains part of cockpit identity")
    func acceptedMeasurementsKeepModeIdentity() throws {
        let ecoIdentity = try identity(vehicleID: "es80-a", modeKey: "eco")
        let sportIdentity = try identity(vehicleID: "es80-a", modeKey: "sport")
        var ecoModel = try model(identity: ecoIdentity)
        var sportModel = try model(identity: sportIdentity)

        try ecoModel.accept(sample(identity: ecoIdentity))
        try sportModel.accept(sample(identity: sportIdentity))

        let eco = ecoModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        )
        let sport = sportModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        )

        guard case let .live(ecoMeasurement) = eco.measurement,
              case let .live(sportMeasurement) = sport.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(eco.identity == ecoIdentity)
        #expect(sport.identity == sportIdentity)
        #expect(ecoMeasurement.identity == ecoIdentity)
        #expect(sportMeasurement.identity == sportIdentity)
        #expect(ecoMeasurement != sportMeasurement)
    }

    @Test("retained numeric evidence keeps its originating identity")
    func retainedMeasurementKeepsIdentity() throws {
        let sourceIdentity = try identity(vehicleID: "es80-retained", modeKey: "drive")
        var sourceModel = try model(identity: sourceIdentity)
        try sourceModel.accept(sample(identity: sourceIdentity, watts: 510))

        let snapshot = sourceModel.cockpitSnapshot(
            atUptimeNanoseconds: 3_000_000_001,
            scale: nil
        )

        guard case let .retained(measurement) = snapshot.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(snapshot.identity == sourceIdentity)
        #expect(measurement.identity == sourceIdentity)
        #expect(measurement.watts == 510)
    }
}