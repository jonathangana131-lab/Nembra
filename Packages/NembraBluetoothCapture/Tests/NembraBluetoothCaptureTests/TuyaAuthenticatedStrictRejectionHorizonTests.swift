import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated strict rejection horizon")
struct TuyaAuthenticatedStrictRejectionHorizonTests {
    private func snapshot(latestPayloadOffset: UInt64) -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        let authenticatedAt: UInt64 = 10
        return TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt + latestPayloadOffset,
            connectionGeneration: 77
        )
    }

    @Test("payload one nanosecond before historical horizon fails closed")
    func beforeHorizonBlocks() {
        let snapshot = snapshot(
            latestPayloadOffset: TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds - 1
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
                == .blocked(reason: "Authenticated application payloads have not survived beyond the historical rejection window yet.")
        )
    }

    @Test("payload exactly on historical horizon still fails closed")
    func exactHorizonBlocks() {
        let snapshot = snapshot(
            latestPayloadOffset: TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        )
        #expect(
            TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot)
                == .blocked(reason: "Authenticated application payloads have not survived beyond the historical rejection window yet.")
        )
    }

    @Test("payload one nanosecond beyond historical horizon can satisfy timing limb")
    func beyondHorizonCanPass() {
        let snapshot = snapshot(
            latestPayloadOffset: TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds + 1
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }
}
