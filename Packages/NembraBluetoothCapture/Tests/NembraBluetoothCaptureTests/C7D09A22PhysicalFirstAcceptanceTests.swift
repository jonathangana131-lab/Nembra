import Testing
@testable import NembraBluetoothCapture

@Suite("C7D09A22 physical first acceptance")
struct C7D09A22PhysicalFirstAcceptanceTests {
    private let authenticatedAt: UInt64 = 10_000
    private let connectionGeneration: UInt64 = 7

    private func readyPreflight() -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        let latestPayload = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1
        let latestObserved = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds

        return TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1_000,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: latestObserved,
            applicationPayloadCount: TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: latestPayload,
            connectionGeneration: connectionGeneration
        )
    }

    @Test("canonical auth without raw notifications remains below physical first acceptance")
    func authenticatedStructuredEvidenceAloneIsInsufficient() {
        let evidence = C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence(
            connectionGeneration: connectionGeneration,
            rawNotifyPayloadCount: 0,
            latestRawNotifyUptimeNanoseconds: nil
        )

        #expect(
            C7D09A22PhysicalFirstAcceptance.verdict(
                preflight: readyPreflight(),
                rawNotifyEvidence: evidence
            ) == .blocked(reason: "Repeated raw application notify payload evidence is required.")
        )
    }

    @Test("raw notifications from another generation cannot cross the custody boundary")
    func staleRawNotifyGenerationIsRejected() {
        let evidence = C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence(
            connectionGeneration: connectionGeneration - 1,
            rawNotifyPayloadCount: 2,
            latestRawNotifyUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1
        )

        #expect(
            C7D09A22PhysicalFirstAcceptance.verdict(
                preflight: readyPreflight(),
                rawNotifyEvidence: evidence
            ) == .blocked(reason: "Raw notify evidence belongs to a different Bluetooth connection generation.")
        )
    }

    @Test("raw notify exactly at historical boundary is still insufficient")
    func exactThirtySecondBoundaryIsRejected() {
        let evidence = C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence(
            connectionGeneration: connectionGeneration,
            rawNotifyPayloadCount: 2,
            latestRawNotifyUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        )

        #expect(
            C7D09A22PhysicalFirstAcceptance.verdict(
                preflight: readyPreflight(),
                rawNotifyEvidence: evidence
            ) == .blocked(reason: "Raw application notify evidence has not survived beyond the historical rejection window yet.")
        )
    }

    @Test("repeated same-generation raw notify evidence beyond rejection window earns transport acceptance only")
    func qualifyingRawNotifyEvidenceIsAccepted() {
        let evidence = C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence(
            connectionGeneration: connectionGeneration,
            rawNotifyPayloadCount: 2,
            latestRawNotifyUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1
        )

        #expect(
            C7D09A22PhysicalFirstAcceptance.verdict(
                preflight: readyPreflight(),
                rawNotifyEvidence: evidence
            ) == .acceptedRawNotifyTransport
        )
    }
}
