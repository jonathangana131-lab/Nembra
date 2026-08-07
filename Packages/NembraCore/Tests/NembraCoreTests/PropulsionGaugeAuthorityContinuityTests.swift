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

    @Test("simulator chronology cannot poison the first verified receipt stream")
    func simulatorPeakDoesNotCrossIntoVerifiedAuthority() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.simulator(
            identity: identity,
            watts: 900,
            receiptSequenceNumber: 1_000,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))

        try model.accept(.verifiedVehicleMeasurement(
            identity: identity,
            watts: 200,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 1
        ))

        let verifiedScale = try PropulsionGaugeScale.verifiedObservedEnvelope(
            identity: identity,
            ceilingWatts: 1_000
        )
        let frame = model.frame(atUptimeNanoseconds: 2_000, scale: verifiedScale)

        #expect(frame.latestAuthority == .verifiedVehicleMeasurement)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 1)
        #expect(frame.origin == .acceptedMeasurement)
        #expect(frame.displayWatts == 200)
        #expect(frame.normalizedPropulsion == 0.2)
        #expect(frame.acceptedPeakNormalized == 0.2)
    }

    @Test("verified chronology cannot poison the first simulator receipt stream")
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
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 1
        ))

        let simulatorScale = try PropulsionGaugeScale.simulator(
            identity: identity,
            ceilingWatts: 1_000
        )
        let frame = model.frame(atUptimeNanoseconds: 2_000, scale: simulatorScale)

        #expect(frame.latestAuthority == .simulator)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 1)
        #expect(frame.origin == .acceptedMeasurement)
        #expect(frame.displayWatts == 100)
        #expect(frame.normalizedPropulsion == 0.1)
        #expect(frame.acceptedPeakNormalized == 0.1)
    }

    @Test("authority transition preserves each source domain replay high-water")
    func authorityTransitionPreservesIndependentReplayProtection() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.simulator(
            identity: identity,
            watts: 500,
            receiptSequenceNumber: 100,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 4
        ))
        try model.accept(.verifiedVehicleMeasurement(
            identity: identity,
            watts: 200,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 1
        ))

        #expect(throws: PropulsionGaugeDisplayError.nonIncreasingReceiptSequence) {
            try model.accept(.simulator(
                identity: identity,
                watts: 550,
                receiptSequenceNumber: 100,
                receivedAtUptimeNanoseconds: 3_000,
                continuityGeneration: 4
            ))
        }

        try model.accept(.simulator(
            identity: identity,
            watts: 550,
            receiptSequenceNumber: 101,
            receivedAtUptimeNanoseconds: 3_000,
            continuityGeneration: 4
        ))
        let frame = model.frame(atUptimeNanoseconds: 3_000, scale: nil)
        #expect(frame.latestAuthority == .simulator)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 101)
        #expect(frame.displayWatts == 550)
        #expect(frame.origin == .acceptedMeasurement)
    }

    @Test("retired generation floor belongs only to the authority that was interrupted")
    func retiredGenerationDoesNotCrossAuthorityDomain() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.simulator(
            identity: identity,
            watts: 420,
            receiptSequenceNumber: 70,
            receivedAtUptimeNanoseconds: 7_000,
            continuityGeneration: 7
        ))
        model.markUnavailable()

        try model.accept(.verifiedVehicleMeasurement(
            identity: identity,
            watts: 180,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 1
        ))

        let verifiedFrame = model.frame(atUptimeNanoseconds: 100, scale: nil)
        #expect(verifiedFrame.availability == .live)
        #expect(verifiedFrame.latestAuthority == .verifiedVehicleMeasurement)
        #expect(verifiedFrame.latestAcceptedWatts == 180)

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try model.accept(.simulator(
                identity: identity,
                watts: 430,
                receiptSequenceNumber: 71,
                receivedAtUptimeNanoseconds: 7_001,
                continuityGeneration: 7
            ))
        }
    }
}
