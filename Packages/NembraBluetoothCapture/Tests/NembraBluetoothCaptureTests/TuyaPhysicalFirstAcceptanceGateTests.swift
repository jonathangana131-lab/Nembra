import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya physical first acceptance")
struct TuyaPhysicalFirstAcceptanceGateTests {
    private let authenticatedAt: UInt64 = 10

    @Test("generic authenticated application evidence alone cannot earn physical first acceptance")
    func genericApplicationEvidenceAloneBlocks() {
        #expect(
            TuyaPhysicalFirstAcceptanceGate.verdict(
                preflight: readyPreflight(),
                receiveEvidence: nil
            ) == .blocked(reason: "Documented authenticated device-to-app receive evidence is required.")
        )
    }

    @Test("receive evidence from a stale generation fails closed")
    func staleGenerationBlocks() {
        let evidence = TuyaAuthenticatedReceiveEvidence(
            provenance: .smartLifeDocumentedDeviceToAppReceive,
            connectionGeneration: 6,
            payloadCount: 2,
            latestPayloadUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1
        )
        #expect(
            TuyaPhysicalFirstAcceptanceGate.verdict(
                preflight: readyPreflight(generation: 7),
                receiveEvidence: evidence
            ) == .blocked(reason: "Documented receive evidence does not belong to the current authenticated connection generation.")
        )
    }

    @Test("one receive payload is insufficient")
    func repeatedReceiveEvidenceRequired() {
        let evidence = TuyaAuthenticatedReceiveEvidence(
            provenance: .smartLifeDocumentedDeviceToAppReceive,
            connectionGeneration: 7,
            payloadCount: 1,
            latestPayloadUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1
        )
        #expect(
            TuyaPhysicalFirstAcceptanceGate.verdict(
                preflight: readyPreflight(),
                receiveEvidence: evidence
            ) == .blocked(reason: "Repeated documented authenticated receive payloads are required.")
        )
    }

    @Test("receive evidence exactly at historical boundary is insufficient")
    func exactThirtySecondBoundaryBlocks() {
        let evidence = TuyaAuthenticatedReceiveEvidence(
            provenance: .smartLifeDocumentedDeviceToAppReceive,
            connectionGeneration: 7,
            payloadCount: 2,
            latestPayloadUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        )
        #expect(
            TuyaPhysicalFirstAcceptanceGate.verdict(
                preflight: readyPreflight(),
                receiveEvidence: evidence
            ) == .blocked(reason: "Documented authenticated receive payloads have not survived beyond the historical rejection window yet.")
        )
    }

    @Test("same-generation repeated documented receive payloads beyond rejection boundary earn transport first acceptance")
    func qualifyingReceiveEvidenceAccepts() {
        let evidence = TuyaAuthenticatedReceiveEvidence(
            provenance: .smartLifeDocumentedDeviceToAppReceive,
            connectionGeneration: 7,
            payloadCount: 2,
            latestPayloadUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1
        )
        #expect(
            TuyaPhysicalFirstAcceptanceGate.verdict(
                preflight: readyPreflight(),
                receiveEvidence: evidence
            ) == .readyForPhysicalFirstAcceptance
        )
    }

    private func readyPreflight(generation: UInt64 = 7) -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: 2,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt
                + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
                + 1,
            connectionGeneration: generation
        )
    }
}
