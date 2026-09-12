import Foundation
import Testing
@testable import NembraBluetoothCapture

struct TuyaAuthenticatedRawFD50AcceptanceTests {
    private func authenticatedSnapshot(
        generation: UInt64 = 7,
        authenticatedAt: UInt64 = 1_000,
        latestObserved: UInt64 = 46_000_000_000,
        hasActiveCallbackAuthority: Bool = true
    ) -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 500,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: latestObserved,
            applicationPayloadCount: 0,
            latestApplicationPayloadUptimeNanoseconds: nil,
            connectionGeneration: generation,
            hasActiveCallbackAuthority: hasActiveCallbackAuthority
        )
    }

    private func payload(_ count: Int, byte: UInt8 = 0xA5) -> Data {
        Data(repeating: byte, count: count)
    }

    @Test("authenticated SDK survival alone cannot close physical GO")
    func sdkOnlyIsBlocked() {
        let verdict = TuyaAuthenticatedRawFD50Acceptance.verdict(
            authenticatedSnapshot: authenticatedSnapshot(),
            observations: []
        )
        #expect(verdict != .accepted)
    }

    @Test("two same-generation raw notifies including one after 30 seconds close physical acceptance")
    func acceptedRawPrefix() {
        let authenticatedAt: UInt64 = 1_000
        let snapshot = authenticatedSnapshot(authenticatedAt: authenticatedAt)
        let observations = [
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID.lowercased(),
                observedAtUptimeNanoseconds: authenticatedAt + 2_000_000_000,
                payload: payload(8, byte: 0x11)
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 30_000_000_001,
                payload: payload(12, byte: 0x22)
            )
        ]

        #expect(observations[0].payload == payload(8, byte: 0x11))
        #expect(observations[1].payload == payload(12, byte: 0x22))
        #expect(
            TuyaAuthenticatedRawFD50Acceptance.verdict(
                authenticatedSnapshot: snapshot,
                observations: observations
            ) == .accepted
        )
    }

    @Test("retired authenticated callback authority cannot close physical acceptance")
    func retiredCallbackAuthorityIsBlocked() {
        let authenticatedAt: UInt64 = 1_000
        let snapshot = authenticatedSnapshot(
            authenticatedAt: authenticatedAt,
            hasActiveCallbackAuthority: false
        )
        let observations = [
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 2_000_000_000,
                payload: payload(8)
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 30_000_000_001,
                payload: payload(12)
            )
        ]

        #expect(
            TuyaAuthenticatedRawFD50Acceptance.verdict(
                authenticatedSnapshot: snapshot,
                observations: observations
            ) == .blocked(reason: "Authenticated generation no longer has live callback authority.")
        )
    }

    @Test("a raw receipt at the authentication transition cannot qualify as post-auth evidence")
    func authenticationBoundaryReceiptIsBlocked() {
        let authenticatedAt: UInt64 = 1_000
        let snapshot = authenticatedSnapshot(authenticatedAt: authenticatedAt)
        let observations = [
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt,
                payload: payload(8)
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 31_000_000_000,
                payload: payload(12)
            )
        ]

        #expect(
            TuyaAuthenticatedRawFD50Acceptance.verdict(
                authenticatedSnapshot: snapshot,
                observations: observations
            ) != .accepted
        )
    }

    @Test("replaying one retained raw notify cannot counterfeit the two-receipt prefix")
    func replayedObservationIsBlocked() {
        let authenticatedAt: UInt64 = 1_000
        let snapshot = authenticatedSnapshot(authenticatedAt: authenticatedAt)
        let receipt = TuyaAuthenticatedRawFD50Acceptance.Observation(
            connectionGeneration: snapshot.connectionGeneration,
            characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
            observedAtUptimeNanoseconds: authenticatedAt + 31_000_000_000,
            payload: payload(12)
        )

        #expect(
            TuyaAuthenticatedRawFD50Acceptance.verdict(
                authenticatedSnapshot: snapshot,
                observations: [receipt, receipt]
            ) != .accepted
        )
    }

    @Test("wrong generation, empty bytes, wrong characteristic, and boundary-equal packets cannot qualify")
    func rejectsCounterfeitCustody() {
        let authenticatedAt: UInt64 = 1_000
        let snapshot = authenticatedSnapshot(authenticatedAt: authenticatedAt)
        let observations = [
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration + 1,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 31_000_000_000,
                payload: payload(8)
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 31_000_000_000,
                payload: Data()
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: "00000001-0000-1001-8001-00805F9B07D0",
                observedAtUptimeNanoseconds: authenticatedAt + 31_000_000_000,
                payload: payload(8)
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 1_000_000_000,
                payload: payload(8)
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: snapshot.connectionGeneration,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedRawFD50Acceptance.historicalRejectionBoundaryNanoseconds,
                payload: payload(8)
            )
        ]

        #expect(
            TuyaAuthenticatedRawFD50Acceptance.verdict(
                authenticatedSnapshot: snapshot,
                observations: observations
            ) != .accepted
        )
    }
}
