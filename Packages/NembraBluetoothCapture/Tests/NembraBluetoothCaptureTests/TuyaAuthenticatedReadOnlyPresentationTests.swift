import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only presentation")
struct TuyaAuthenticatedReadOnlyPresentationTests {
    @Test("historical-window presentation is strict at exactly 30 seconds")
    func exactBoundaryIsNotSurvival() {
        let authenticatedAt: UInt64 = 1_000
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds,
            connectionGeneration: 1
        )

        #expect(!TuyaAuthenticatedReadOnlyPresentation.applicationEvidenceSurvivedHistoricalWindow(snapshot))
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated application payloads have not survived beyond the historical rejection window yet."))
    }

    @Test("presentation agrees with canonical gate immediately after the boundary")
    func postBoundaryIsSurvival() {
        let authenticatedAt: UInt64 = 1_000
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds + 1,
            connectionGeneration: 1
        )

        #expect(TuyaAuthenticatedReadOnlyPresentation.applicationEvidenceSurvivedHistoricalWindow(snapshot))
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }
}
