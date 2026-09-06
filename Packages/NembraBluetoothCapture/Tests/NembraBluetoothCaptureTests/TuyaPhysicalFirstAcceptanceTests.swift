import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya physical first acceptance")
struct TuyaPhysicalFirstAcceptanceTests {
    @Test("accepts only non-empty canonical raw notify from the exact authenticated generation after rejection window")
    func exactGenerationRawNotifyAccepts() {
        let authenticatedAt: UInt64 = 10_000
        let notifyAt = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1
        let latest = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds

        let preflight = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1_000,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: latest,
            applicationPayloadCount: TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: notifyAt,
            connectionGeneration: 7
        )
        let notify = TuyaPhysicalNotifyEvidence(
            connectionGeneration: 7,
            characteristicUUID: TuyaPhysicalFirstAcceptance.canonicalDeviceToAppCharacteristicUUID.lowercased(),
            direction: .deviceToApp,
            receivedAtUptimeNanoseconds: notifyAt,
            payloadByteCount: 12,
            packageOwnedRawTransportEvidence: true,
            samePhysicalTransportCustodyProven: true
        )

        #expect(TuyaPhysicalFirstAcceptance.verdict(preflight: preflight, notify: notify) == .accepted)
    }

    @Test("stale generation fails closed")
    func staleGenerationIsBlocked() {
        let fixture = readyFixture()
        let stale = TuyaPhysicalNotifyEvidence(
            connectionGeneration: fixture.preflight.connectionGeneration - 1,
            characteristicUUID: TuyaPhysicalFirstAcceptance.canonicalDeviceToAppCharacteristicUUID,
            direction: .deviceToApp,
            receivedAtUptimeNanoseconds: fixture.notify.receivedAtUptimeNanoseconds,
            payloadByteCount: fixture.notify.payloadByteCount,
            packageOwnedRawTransportEvidence: true,
            samePhysicalTransportCustodyProven: true
        )

        #expect(TuyaPhysicalFirstAcceptance.verdict(preflight: fixture.preflight, notify: stale) ==
            .blocked(reason: "Notify evidence is not from the authenticated connection generation."))
    }

    @Test("exact thirty-second raw notify boundary is still blocked")
    func exactHistoricalBoundaryIsBlocked() {
        let fixture = readyFixture()
        let authenticatedAt = fixture.preflight.authenticatedAtUptimeNanoseconds!
        let boundary = TuyaPhysicalNotifyEvidence(
            connectionGeneration: fixture.preflight.connectionGeneration,
            characteristicUUID: TuyaPhysicalFirstAcceptance.canonicalDeviceToAppCharacteristicUUID,
            direction: .deviceToApp,
            receivedAtUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds,
            payloadByteCount: 1,
            packageOwnedRawTransportEvidence: true,
            samePhysicalTransportCustodyProven: true
        )

        #expect(TuyaPhysicalFirstAcceptance.verdict(preflight: fixture.preflight, notify: boundary) ==
            .blocked(reason: "Raw notify evidence has not survived beyond the historical rejection window."))
    }

    @Test("empty, wrong-direction, wrong-characteristic, or non-owned bytes never accept")
    func invalidRawEvidenceIsBlocked() {
        let fixture = readyFixture()
        let base = fixture.notify

        let variants = [
            TuyaPhysicalNotifyEvidence(
                connectionGeneration: base.connectionGeneration,
                characteristicUUID: base.characteristicUUID,
                direction: base.direction,
                receivedAtUptimeNanoseconds: base.receivedAtUptimeNanoseconds,
                payloadByteCount: 0,
                packageOwnedRawTransportEvidence: true,
                samePhysicalTransportCustodyProven: true
            ),
            TuyaPhysicalNotifyEvidence(
                connectionGeneration: base.connectionGeneration,
                characteristicUUID: base.characteristicUUID,
                direction: .appToDevice,
                receivedAtUptimeNanoseconds: base.receivedAtUptimeNanoseconds,
                payloadByteCount: 1,
                packageOwnedRawTransportEvidence: true,
                samePhysicalTransportCustodyProven: true
            ),
            TuyaPhysicalNotifyEvidence(
                connectionGeneration: base.connectionGeneration,
                characteristicUUID: "00000001-0000-1001-8001-00805F9B07D0",
                direction: .deviceToApp,
                receivedAtUptimeNanoseconds: base.receivedAtUptimeNanoseconds,
                payloadByteCount: 1,
                packageOwnedRawTransportEvidence: true,
                samePhysicalTransportCustodyProven: true
            ),
            TuyaPhysicalNotifyEvidence(
                connectionGeneration: base.connectionGeneration,
                characteristicUUID: base.characteristicUUID,
                direction: .deviceToApp,
                receivedAtUptimeNanoseconds: base.receivedAtUptimeNanoseconds,
                payloadByteCount: 1,
                packageOwnedRawTransportEvidence: false,
                samePhysicalTransportCustodyProven: true
            ),
            TuyaPhysicalNotifyEvidence(
                connectionGeneration: base.connectionGeneration,
                characteristicUUID: base.characteristicUUID,
                direction: .deviceToApp,
                receivedAtUptimeNanoseconds: base.receivedAtUptimeNanoseconds,
                payloadByteCount: 1,
                packageOwnedRawTransportEvidence: true,
                samePhysicalTransportCustodyProven: false
            )
        ]

        for variant in variants {
            #expect(TuyaPhysicalFirstAcceptance.verdict(preflight: fixture.preflight, notify: variant) != .accepted)
        }
    }

    private func readyFixture() -> (preflight: TuyaAuthenticatedReadOnlyPreflightSnapshot, notify: TuyaPhysicalNotifyEvidence) {
        let authenticatedAt: UInt64 = 1_000
        let notifyAt = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1
        let latest = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        let preflight = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 100,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: latest,
            applicationPayloadCount: TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: notifyAt,
            connectionGeneration: 9
        )
        let notify = TuyaPhysicalNotifyEvidence(
            connectionGeneration: 9,
            characteristicUUID: TuyaPhysicalFirstAcceptance.canonicalDeviceToAppCharacteristicUUID,
            direction: .deviceToApp,
            receivedAtUptimeNanoseconds: notifyAt,
            payloadByteCount: 8,
            packageOwnedRawTransportEvidence: true,
            samePhysicalTransportCustodyProven: true
        )
        return (preflight, notify)
    }
}
