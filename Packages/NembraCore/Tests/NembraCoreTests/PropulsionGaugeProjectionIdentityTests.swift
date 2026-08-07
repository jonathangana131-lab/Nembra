import Testing
@testable import NembraCore

@Suite("Propulsion gauge projection identity")
struct PropulsionGaugeProjectionIdentityTests {
    private func policy() throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 500_000_000,
            fallSettlingDurationNanoseconds: 200_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
    }

    private func simulatorModel(
        identity: PropulsionGaugeIdentity,
        watts: Double = 480,
        receipt: UInt64 = 7,
        uptime: UInt64 = 1_000,
        generation: UInt64 = 3
    ) throws -> PropulsionGaugeDisplayModel {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try model.accept(.simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        ))
        return model
    }

    @Test("same vehicle values from different confirmed modes remain distinct after projection")
    func confirmedModeIdentityCannotBeDetached() throws {
        let sport = try PropulsionGaugeIdentity(vehicleID: "shared-es80", modeKey: "sport")
        let eco = try PropulsionGaugeIdentity(vehicleID: "shared-es80", modeKey: "eco")
        let sportModel = try simulatorModel(identity: sport)
        let ecoModel = try simulatorModel(identity: eco)
        let sportScale = try PropulsionGaugeScale.simulator(identity: sport, ceilingWatts: 500)
        let ecoScale = try PropulsionGaugeScale.simulator(identity: eco, ceilingWatts: 500)
        let regionPolicy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)

        let sportCockpit = sportModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: sportScale
        )
        let ecoCockpit = ecoModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: ecoScale
        )

        #expect(sportCockpit.identity == sport)
        #expect(ecoCockpit.identity == eco)
        #expect(sportCockpit != ecoCockpit)

        guard case let .live(sportMeasurement) = sportCockpit.measurement,
              case let .live(ecoMeasurement) = ecoCockpit.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(sportMeasurement.identity == sport)
        #expect(ecoMeasurement.identity == eco)
        #expect(sportMeasurement.watts == ecoMeasurement.watts)
        #expect(sportMeasurement.receiptSequenceNumber == ecoMeasurement.receiptSequenceNumber)
        #expect(sportMeasurement.receivedAtUptimeNanoseconds == ecoMeasurement.receivedAtUptimeNanoseconds)
        #expect(sportMeasurement.authority == ecoMeasurement.authority)
        #expect(sportMeasurement != ecoMeasurement)

        let sportAccessibility = sportModel.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: sportScale
        )
        let ecoAccessibility = ecoModel.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: ecoScale
        )

        #expect(sportAccessibility.identity == sport)
        #expect(ecoAccessibility.identity == eco)
        #expect(sportAccessibility.latestAcceptedWatts == ecoAccessibility.latestAcceptedWatts)
        #expect(sportAccessibility != ecoAccessibility)

        let sportRegion = sportModel.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: sportScale,
            policy: regionPolicy
        )
        let ecoRegion = ecoModel.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: ecoScale,
            policy: regionPolicy
        )

        #expect(sportRegion.identity == sport)
        #expect(ecoRegion.identity == eco)
        #expect(sportRegion.region == .nearObservedScaleEdge)
        #expect(ecoRegion.region == .nearObservedScaleEdge)
        #expect(sportRegion.isSimulatorNearObservedScaleEdge)
        #expect(ecoRegion.isSimulatorNearObservedScaleEdge)
        #expect(sportRegion != ecoRegion)
    }

    @Test("unavailable projections retain scope without manufacturing measurement truth")
    func unavailableProjectionStillCarriesSessionScope() throws {
        let identity = try PropulsionGaugeIdentity(vehicleID: "es80-unavailable", modeKey: "sport")
        let model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        let scale = try PropulsionGaugeScale.simulator(identity: identity, ceilingWatts: 500)
        let regionPolicy = try PropulsionObservedScaleRegionPolicy(nearEdgeFraction: 0.9)

        let cockpit = model.cockpitSnapshot(atUptimeNanoseconds: 1_000, scale: scale)
        let accessibility = model.accessibilitySnapshot(atUptimeNanoseconds: 1_000, scale: scale)
        let region = model.observedScaleRegionSnapshot(
            atUptimeNanoseconds: 1_000,
            scale: scale,
            policy: regionPolicy
        )

        #expect(cockpit.identity == identity)
        #expect(cockpit.measurement == .unavailable)
        #expect(cockpit.visualPropulsionFraction == nil)

        #expect(accessibility.identity == identity)
        #expect(accessibility.availability == .unavailable)
        #expect(accessibility.latestAcceptedWatts == nil)
        #expect(accessibility.latestAuthority == nil)

        #expect(region.identity == identity)
        #expect(region.region == .unavailable)
        #expect(region.latestAcceptedWatts == nil)
        #expect(!region.permitsVerifiedNearObservedMaximumWording)
        #expect(!region.isSimulatorNearObservedScaleEdge)
    }
}