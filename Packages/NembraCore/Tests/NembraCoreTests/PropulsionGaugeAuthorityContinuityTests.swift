import Testing
@testable import NembraCore

@Suite("Propulsion gauge authority continuity")
struct PropulsionGaugeAuthorityContinuityTests {
    private let identity = try! PropulsionGaugeIdentity(vehicleID: "authority-es80")

    private func policy() throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 1_000_000_000,
            fallSettlingDurationNanoseconds: 1_000_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 1_000_000_000
        )
    }

    @Test("simulator peak cannot survive a transition into verified measurement authority")
    func simulatorPeakDoesNotCrossIntoVerifiedAuthority() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.simulator(
            identity: identity,
            watts: 900,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))

        try model.accept(.verifiedVehicleMeasurement(
            identity: identity,
            watts: 200,
            receiptSequenceNumber: 2_000,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 1
        ))

        let verifiedScale = try PropulsionGaugeScale.verifiedObservedEnvelope(
            identity: identity,
            ceilingWatts: 1_000
        )
        let frame = model.frame(atUptimeNanoseconds: 2_000, scale: verifiedScale)

        #expect(frame.latestAuthority == .verifiedVehicleMeasurement)
        #expect(frame.origin == .acceptedMeasurement)
        #expect(frame.displayWatts == 200)
        #expect(frame.normalizedPropulsion == 0.2)
        #expect(frame.acceptedPeakNormalized == 0.2)
    }

    @Test("verified peak cannot survive a transition into simulator authority")
    func verifiedPeakDoesNotCrossIntoSimulatorAuthority() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.verifiedVehicleMeasurement(
            identity: identity,
            watts: 900,
            receiptSequenceNumber: 1_000,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))

        try model.accept(.simulator(
            identity: identity,
            watts: 100,
            receiptSequenceNumber: 2_000,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 1
        ))

        let simulatorScale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: 1_000
        )
        let frame = model.frame(atUptimeNanoseconds: 2_000, scale: simulatorScale)

        #expect(frame.latestAuthority == .simulator)
        #expect(frame.origin == .acceptedMeasurement)
        #expect(frame.displayWatts == 100)
        #expect(frame.normalizedPropulsion == 0.1)
        #expect(frame.acceptedPeakNormalized == 0.1)
    }
}
