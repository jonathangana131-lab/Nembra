import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya physical first acceptance")
struct TuyaPhysicalFirstAcceptanceTests {
    @Test("legacy summary-only notify metadata can never authorize physical acceptance")
    func legacySummaryEvidenceFailsClosed() {
        let fixture = readyFixture()
        let legacy = TuyaPhysicalNotifyEvidence(
            connectionGeneration: fixture.preflight.connectionGeneration,
            characteristicUUID: TuyaPhysicalFirstAcceptance.canonicalDeviceToAppCharacteristicUUID,
            direction: .deviceToApp,
            receivedAtUptimeNanoseconds: fixture.latestNotifyAt,
            payloadByteCount: 64,
            packageOwnedRawTransportEvidence: true,
            samePhysicalTransportCustodyProven: true
        )

        #expect(
            TuyaPhysicalFirstAcceptance.verdict(preflight: fixture.preflight, notify: legacy) ==
                .blocked(
                    reason: "Legacy summary-only notify metadata cannot authorize physical acceptance; retained package-owned raw notify evidence is required."
                )
        )
    }

    @Test("authoritative compatibility path delegates to canonical retained raw notify gate")
    func canonicalRetainedRawEvidenceAccepts() {
        let fixture = readyFixture()
        let raw = C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence(
            connectionGeneration: fixture.preflight.connectionGeneration,
            rawNotifyPayloadCount: 2,
            latestRawNotifyUptimeNanoseconds: fixture.latestNotifyAt,
            retainedRawNotifyPayloads: [Data([0x01]), Data([0x02, 0x03])]
        )

        #expect(
            TuyaPhysicalFirstAcceptance.verdict(
                preflight: fixture.preflight,
                rawNotifyEvidence: raw
            ) == .accepted
        )
    }

    @Test("canonical compatibility path preserves fail-closed retained-byte requirements")
    func canonicalSummaryWithoutBytesIsBlocked() {
        let fixture = readyFixture()
        let raw = C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence(
            connectionGeneration: fixture.preflight.connectionGeneration,
            rawNotifyPayloadCount: 2,
            latestRawNotifyUptimeNanoseconds: fixture.latestNotifyAt,
            retainedRawNotifyPayloads: []
        )

        #expect(
            TuyaPhysicalFirstAcceptance.verdict(
                preflight: fixture.preflight,
                rawNotifyEvidence: raw
            ) != .accepted
        )
    }

    @Test("canonical compatibility path preserves the historical rejection boundary")
    func canonicalHistoricalBoundaryIsBlocked() {
        let fixture = readyFixture()
        let authenticatedAt = fixture.preflight.authenticatedAtUptimeNanoseconds!
        let boundary = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        let raw = C7D09A22PhysicalFirstAcceptance.RawNotifyEvidence(
            connectionGeneration: fixture.preflight.connectionGeneration,
            rawNotifyPayloadCount: 2,
            latestRawNotifyUptimeNanoseconds: boundary,
            retainedRawNotifyPayloads: [Data([0x01]), Data([0x02])]
        )

        #expect(
            TuyaPhysicalFirstAcceptance.verdict(
                preflight: fixture.preflight,
                rawNotifyEvidence: raw
            ) == .blocked(reason: "Raw application notify evidence has not survived beyond the historical rejection window yet.")
        )
    }

    private func readyFixture() -> (
        preflight: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        latestNotifyAt: UInt64
    ) {
        let authenticatedAt: UInt64 = 10_000
        let latestNotifyAt = authenticatedAt
            + TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
            + 1
        let latestObserved = max(
            latestNotifyAt,
            authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds
        )
        let preflight = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1_000,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: latestObserved,
            applicationPayloadCount: TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: latestNotifyAt,
            connectionGeneration: 7
        )
        return (preflight, latestNotifyAt)
    }
}
