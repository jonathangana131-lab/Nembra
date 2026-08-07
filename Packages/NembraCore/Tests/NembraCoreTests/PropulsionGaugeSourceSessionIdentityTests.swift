import Testing
@testable import NembraCore

@Suite("Propulsion gauge source-session identity boundary")
struct PropulsionGaugeSourceSessionIdentityTests {
    @Test("identity mismatch outranks this session's retirement history")
    func identityMismatchIsRejectedBeforeRetirementLookup() throws {
        let sessionIdentity = try PropulsionGaugeIdentity(vehicleID: "source-session-es80")
        let foreignIdentity = try PropulsionGaugeIdentity(vehicleID: "different-es80")
        let policy = try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 500_000_000,
            fallSettlingDurationNanoseconds: 200_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
        var session = PropulsionGaugeSourceSession(identity: sessionIdentity, policy: policy)

        #expect(session.markUnavailable(authority: .simulator, continuityGeneration: 9) == .fencedBeforeFirstMeasurement)

        #expect(throws: PropulsionGaugeDisplayError.identityMismatch) {
            try session.accept(.simulator(
                identity: foreignIdentity,
                watts: 240,
                receiptSequenceNumber: 1,
                receivedAtUptimeNanoseconds: 100,
                continuityGeneration: 9
            ))
        }

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try session.accept(.simulator(
                identity: sessionIdentity,
                watts: 240,
                receiptSequenceNumber: 1,
                receivedAtUptimeNanoseconds: 100,
                continuityGeneration: 9
            ))
        }

        try session.accept(.simulator(
            identity: sessionIdentity,
            watts: 260,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10,
            continuityGeneration: 10
        ))

        let live = session.frame(atUptimeNanoseconds: 10, scale: nil)
        #expect(live.availability == .live)
        #expect(live.latestAcceptedWatts == 260)
    }
}
