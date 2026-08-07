import Testing
@testable import NembraCore

@Suite("Propulsion gauge source-session fencing")
struct PropulsionGaugeSourceSessionTests {
    private let identity = try! PropulsionGaugeIdentity(vehicleID: "source-session-es80", modeKey: "sport")

    private func policy() throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 500_000_000,
            fallSettlingDurationNanoseconds: 200_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
    }

    @Test("older interruption cannot hide a newer accepted generation")
    func staleInterruptionCannotInvalidateNewerAcceptedGeneration() throws {
        var session = PropulsionGaugeSourceSession(identity: identity, policy: try policy())

        try session.accept(.simulator(
            identity: identity,
            watts: 180,
            receiptSequenceNumber: 90,
            receivedAtUptimeNanoseconds: 9_000,
            continuityGeneration: 4
        ))
        try session.accept(.simulator(
            identity: identity,
            watts: 420,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 5
        ))

        let disposition = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: 4
        )
        #expect(disposition == .ignoredOlderGeneration)

        let frame = session.frame(atUptimeNanoseconds: 100, scale: nil)
        #expect(frame.availability == .live)
        #expect(frame.origin == .acceptedMeasurement)
        #expect(frame.latestAcceptedWatts == 420)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 1)
        #expect(frame.latestAuthority == .simulator)
    }

    @Test("future interruption fences failed generation and hides older active evidence")
    func futureInterruptionRequiresGenerationAfterFailedAttempt() throws {
        var session = PropulsionGaugeSourceSession(identity: identity, policy: try policy())

        try session.accept(.simulator(
            identity: identity,
            watts: 320,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 800,
            continuityGeneration: 4
        ))

        let disposition = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: 5
        )
        #expect(disposition == .appliedToActiveAuthority)

        let unavailable = session.frame(atUptimeNanoseconds: 900, scale: nil)
        #expect(unavailable.availability == .unavailable)
        #expect(unavailable.origin == .unavailable)
        #expect(unavailable.displayWatts == nil)
        #expect(unavailable.latestAcceptedWatts == 320)

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try session.accept(.simulator(
                identity: identity,
                watts: 360,
                receiptSequenceNumber: 1,
                receivedAtUptimeNanoseconds: 10,
                continuityGeneration: 5
            ))
        }

        try session.accept(.simulator(
            identity: identity,
            watts: 380,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 20,
            continuityGeneration: 6
        ))

        let resumed = session.frame(atUptimeNanoseconds: 20, scale: nil)
        #expect(resumed.availability == .live)
        #expect(resumed.origin == .acceptedMeasurement)
        #expect(resumed.latestAcceptedWatts == 380)
        #expect(resumed.latestAcceptedReceiptSequenceNumber == 1)
    }

    @Test("inactive authority interruption is fenced without hiding active authority")
    func inactiveAuthorityInterruptionDoesNotHideActiveEvidence() throws {
        var session = PropulsionGaugeSourceSession(identity: identity, policy: try policy())

        try session.accept(.simulator(
            identity: identity,
            watts: 510,
            receiptSequenceNumber: 20,
            receivedAtUptimeNanoseconds: 2_000,
            continuityGeneration: 3
        ))

        let disposition = session.markUnavailable(
            authority: .verifiedVehicleMeasurement,
            continuityGeneration: 7
        )
        #expect(disposition == .fencedInactiveAuthority)

        let simulatorFrame = session.frame(atUptimeNanoseconds: 2_000, scale: nil)
        #expect(simulatorFrame.availability == .live)
        #expect(simulatorFrame.latestAuthority == .simulator)
        #expect(simulatorFrame.latestAcceptedWatts == 510)

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try session.accept(.verifiedVehicleMeasurement(
                identity: identity,
                watts: 200,
                receiptSequenceNumber: 1,
                receivedAtUptimeNanoseconds: 10,
                continuityGeneration: 7
            ))
        }

        try session.accept(.verifiedVehicleMeasurement(
            identity: identity,
            watts: 220,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 20,
            continuityGeneration: 8
        ))

        let verifiedFrame = session.frame(atUptimeNanoseconds: 20, scale: nil)
        #expect(verifiedFrame.availability == .live)
        #expect(verifiedFrame.origin == .acceptedMeasurement)
        #expect(verifiedFrame.latestAuthority == .verifiedVehicleMeasurement)
        #expect(verifiedFrame.latestAcceptedWatts == 220)
    }

    @Test("interruption before first sample retires that source generation")
    func preMeasurementInterruptionCannotBeResurrectedByDelayedSample() throws {
        var session = PropulsionGaugeSourceSession(identity: identity, policy: try policy())

        let disposition = session.markUnavailable(
            authority: .simulator,
            continuityGeneration: 11
        )
        #expect(disposition == .fencedBeforeFirstMeasurement)

        let unavailable = session.frame(atUptimeNanoseconds: 100, scale: nil)
        #expect(unavailable.availability == .unavailable)
        #expect(unavailable.latestAcceptedWatts == nil)

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try session.accept(.simulator(
                identity: identity,
                watts: 150,
                receiptSequenceNumber: 1,
                receivedAtUptimeNanoseconds: 100,
                continuityGeneration: 11
            ))
        }

        try session.accept(.simulator(
            identity: identity,
            watts: 170,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10,
            continuityGeneration: 12
        ))

        let live = session.frame(atUptimeNanoseconds: 10, scale: nil)
        #expect(live.availability == .live)
        #expect(live.latestAcceptedWatts == 170)
    }

    @Test("current interruption preserves last accepted numeric truth for accessibility")
    func currentInterruptionDoesNotManufactureAccessibleZero() throws {
        var session = PropulsionGaugeSourceSession(identity: identity, policy: try policy())

        try session.accept(.simulator(
            identity: identity,
            watts: 275,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 200,
            continuityGeneration: 2
        ))

        #expect(session.markUnavailable(authority: .simulator, continuityGeneration: 2) == .appliedToActiveAuthority)

        let snapshot = session.accessibilitySnapshot(atUptimeNanoseconds: 250, scale: nil)
        #expect(snapshot.availability == .unavailable)
        #expect(snapshot.latestAcceptedWatts == 275)
        #expect(snapshot.latestAcceptedReceiptSequenceNumber == 2)
        #expect(snapshot.latestAuthority == .simulator)
        #expect(snapshot.acceptedObservedScaleFraction == nil)
    }
}
