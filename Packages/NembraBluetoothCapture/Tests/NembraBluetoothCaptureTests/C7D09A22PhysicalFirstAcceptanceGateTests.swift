import Testing
@testable import NembraBluetoothCapture

struct C7D09A22PhysicalFirstAcceptanceGateTests {
    private func readyPreflight() -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 0,
            authenticatedAtUptimeNanoseconds: 1_000_000_000,
            latestObservedUptimeNanoseconds: 46_000_000_000,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: 31_000_000_000,
            connectionGeneration: 1
        )
    }

    @Test
    func sdkOnlyEvidenceCannotClaimPhysicalFirstAcceptance() {
        let evidence = C7D09A22PhysicalFirstAcceptanceGate.Evidence(
            authenticatedPreflight: readyPreflight(),
            rawNotifyPayloadCount: 0,
            rawNotifyObservedAfterAuthentication: false,
            canonicalFD50CharacteristicTupleProven: false,
            sameAuthenticatedTransportCustodyProven: false
        )

        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: evidence) != .accepted)
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesStationarySemanticMapping(for: evidence))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesTelemetrySemantics(for: evidence))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesControlWrites(for: evidence))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesPairingResetOrUnbind(for: evidence))
    }

    @Test
    func rawNotifyMustBePostAuthCanonicalAndSameTransport() {
        let incomplete = C7D09A22PhysicalFirstAcceptanceGate.Evidence(
            authenticatedPreflight: readyPreflight(),
            rawNotifyPayloadCount: 1,
            rawNotifyObservedAfterAuthentication: true,
            canonicalFD50CharacteristicTupleProven: true,
            sameAuthenticatedTransportCustodyProven: false
        )
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: incomplete) != .accepted)
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesStationarySemanticMapping(for: incomplete))

        let complete = C7D09A22PhysicalFirstAcceptanceGate.Evidence(
            authenticatedPreflight: readyPreflight(),
            rawNotifyPayloadCount: 1,
            rawNotifyObservedAfterAuthentication: true,
            canonicalFD50CharacteristicTupleProven: true,
            sameAuthenticatedTransportCustodyProven: true
        )
        #expect(C7D09A22PhysicalFirstAcceptanceGate.verdict(for: complete) == .accepted)
        #expect(C7D09A22PhysicalFirstAcceptanceGate.authorizesStationarySemanticMapping(for: complete))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesTelemetrySemantics(for: complete))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesControlWrites(for: complete))
        #expect(!C7D09A22PhysicalFirstAcceptanceGate.authorizesPairingResetOrUnbind(for: complete))
    }
}
