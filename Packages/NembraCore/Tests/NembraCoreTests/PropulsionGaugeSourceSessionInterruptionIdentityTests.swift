import Testing
@testable import NembraCore

// The production source-session API intentionally requires exact source identity
// for every lifecycle callback. Keep the older generation-fencing tests concise by
// adapting their calls only inside the test target; no identity-less overload is
// available to production/package consumers.
extension PropulsionGaugeSourceSession {
    @discardableResult
    mutating func markUnavailable(
        authority: PropulsionPowerSampleAuthority,
        continuityGeneration: UInt64
    ) -> InterruptionDisposition {
        markUnavailable(
            sourceIdentity: identity,
            authority: authority,
            continuityGeneration: continuityGeneration
        )
    }
}

@Suite("Propulsion gauge source-session interruption identity")
struct PropulsionGaugeSourceSessionInterruptionIdentityTests {
    private func policy() throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 500_000_000,
            fallSettlingDurationNanoseconds: 200_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
    }

    @Test("foreign vehicle interruption cannot retire current verified source")
    func foreignVehicleInterruptionCannotMutateRetirementState() throws {
        let currentIdentity = try PropulsionGaugeIdentity(
            vehicleID: "current-es80",
            modeKey: "sport"
        )
        let foreignIdentity = try PropulsionGaugeIdentity(
            vehicleID: "previous-es80",
            modeKey: "sport"
        )
        var session = PropulsionGaugeSourceSession(
            identity: currentIdentity,
            policy: try policy()
        )

        try session.accept(.verifiedVehicleMeasurement(
            identity: currentIdentity,
            watts: 410,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 7
        ))

        #expect(session.markUnavailable(
            sourceIdentity: foreignIdentity,
            authority: .verifiedVehicleMeasurement,
            continuityGeneration: 7
        ) == .ignoredForeignIdentity)

        // Prove the foreign callback did not silently advance the retirement floor:
        // a later accepted observation from the current identity/generation remains valid.
        try session.accept(.verifiedVehicleMeasurement(
            identity: currentIdentity,
            watts: 430,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 110,
            continuityGeneration: 7
        ))

        let live = session.frame(atUptimeNanoseconds: 110, scale: nil)
        #expect(live.availability == .live)
        #expect(live.latestAcceptedWatts == 430)
        #expect(live.latestAcceptedReceiptSequenceNumber == 2)
        #expect(live.latestAuthority == .verifiedVehicleMeasurement)

        #expect(session.markUnavailable(
            sourceIdentity: currentIdentity,
            authority: .verifiedVehicleMeasurement,
            continuityGeneration: 7
        ) == .appliedToActiveAuthority)

        let unavailable = session.frame(atUptimeNanoseconds: 110, scale: nil)
        #expect(unavailable.availability == .unavailable)
        #expect(unavailable.latestAcceptedWatts == 430)

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try session.accept(.verifiedVehicleMeasurement(
                identity: currentIdentity,
                watts: 450,
                receiptSequenceNumber: 3,
                receivedAtUptimeNanoseconds: 120,
                continuityGeneration: 7
            ))
        }
    }

    @Test("same vehicle foreign mode interruption cannot poison pre-sample generation")
    func foreignModeInterruptionBeforeFirstSampleDoesNotFenceCurrentMode() throws {
        let sportIdentity = try PropulsionGaugeIdentity(
            vehicleID: "shared-es80",
            modeKey: "sport"
        )
        let ecoIdentity = try PropulsionGaugeIdentity(
            vehicleID: "shared-es80",
            modeKey: "eco"
        )
        var session = PropulsionGaugeSourceSession(
            identity: sportIdentity,
            policy: try policy()
        )

        #expect(session.markUnavailable(
            sourceIdentity: ecoIdentity,
            authority: .simulator,
            continuityGeneration: 11
        ) == .ignoredForeignIdentity)

        // The exact sport source generation was never retired by the eco callback.
        try session.accept(.simulator(
            identity: sportIdentity,
            watts: 190,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 11
        ))

        let live = session.frame(atUptimeNanoseconds: 100, scale: nil)
        #expect(live.availability == .live)
        #expect(live.latestAcceptedWatts == 190)

        #expect(session.markUnavailable(
            sourceIdentity: sportIdentity,
            authority: .simulator,
            continuityGeneration: 11
        ) == .appliedToActiveAuthority)
        #expect(session.frame(atUptimeNanoseconds: 100, scale: nil).availability == .unavailable)
    }
}
