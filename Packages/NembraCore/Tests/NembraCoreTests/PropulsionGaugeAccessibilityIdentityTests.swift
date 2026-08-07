import Testing
@testable import NembraCore

@Suite("Propulsion gauge accessibility identity")
struct PropulsionGaugeAccessibilityIdentityTests {
    private func policy() throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 500_000_000,
            fallSettlingDurationNanoseconds: 200_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
    }

    private func snapshot(
        identity: PropulsionGaugeIdentity,
        scaleIdentity: PropulsionGaugeIdentity? = nil,
        watts: Double = 320,
        receipt: UInt64 = 7,
        uptime: UInt64 = 1_000
    ) throws -> PropulsionGaugeAccessibilitySnapshot {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try model.accept(.simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: 3
        ))

        return model.accessibilitySnapshot(
            atUptimeNanoseconds: uptime,
            scale: try .simulator(
                identity: scaleIdentity ?? identity,
                ceilingWatts: 500
            )
        )
    }

    @Test("otherwise identical accessibility evidence remains distinct across confirmed modes")
    func confirmedModeIdentityCannotBeDetached() throws {
        let sport = try PropulsionGaugeIdentity(vehicleID: "shared-es80", modeKey: "sport")
        let eco = try PropulsionGaugeIdentity(vehicleID: "shared-es80", modeKey: "eco")

        let sportSnapshot = try snapshot(identity: sport)
        let ecoSnapshot = try snapshot(identity: eco)

        #expect(sportSnapshot.identity == sport)
        #expect(ecoSnapshot.identity == eco)
        #expect(sportSnapshot.latestAcceptedWatts == ecoSnapshot.latestAcceptedWatts)
        #expect(sportSnapshot.latestAcceptedReceiptSequenceNumber == ecoSnapshot.latestAcceptedReceiptSequenceNumber)
        #expect(sportSnapshot.latestAcceptedUptimeNanoseconds == ecoSnapshot.latestAcceptedUptimeNanoseconds)
        #expect(sportSnapshot.latestAuthority == ecoSnapshot.latestAuthority)
        #expect(sportSnapshot.acceptedObservedScaleFraction == ecoSnapshot.acceptedObservedScaleFraction)
        #expect(sportSnapshot.scaleOrigin == ecoSnapshot.scaleOrigin)
        #expect(sportSnapshot != ecoSnapshot)
    }

    @Test("foreign scale rejection cannot relabel the accepted accessibility scope")
    func foreignScaleDoesNotReplaceMeasurementIdentity() throws {
        let sport = try PropulsionGaugeIdentity(vehicleID: "shared-es80", modeKey: "sport")
        let eco = try PropulsionGaugeIdentity(vehicleID: "shared-es80", modeKey: "eco")

        let snapshot = try snapshot(identity: sport, scaleIdentity: eco)

        #expect(snapshot.identity == sport)
        #expect(snapshot.availability == .live)
        #expect(snapshot.latestAcceptedWatts == 320)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 7)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }

    @Test("unavailable accessibility state keeps session scope without inventing telemetry")
    func unavailableStateRetainsOnlyContextIdentity() throws {
        let identity = try PropulsionGaugeIdentity(vehicleID: "es80-unavailable", modeKey: "sport")
        let model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        let snapshot = model.accessibilitySnapshot(
            atUptimeNanoseconds: 1_000,
            scale: try .simulator(identity: identity, ceilingWatts: 500)
        )

        #expect(snapshot.identity == identity)
        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.latestAcceptedWatts == nil)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == nil)
        #expect(snapshot.latestAcceptedUptimeNanoseconds == nil)
        #expect(snapshot.latestAuthority == nil)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
        #expect(snapshot.scaleOrigin == nil)
    }
}