import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated raw FD50 chronology")
struct TuyaAuthenticatedRawFD50ChronologyTests {
    @Test("missing connection start cannot qualify raw physical evidence")
    func missingConnectionStartIsBlocked() {
        let authenticatedAt: UInt64 = 1_000
        let generation: UInt64 = 7
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: nil,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + 31_000_000_001,
            applicationPayloadCount: 0,
            connectionGeneration: generation
        )
        let observations = qualifyingObservations(generation: generation, authenticatedAt: authenticatedAt)

        #expect(
            TuyaAuthenticatedRawFD50Acceptance.verdict(
                authenticatedSnapshot: snapshot,
                observations: observations
            ) == .blocked(reason: "Authenticated connection chronology is unavailable or invalid.")
        )
    }

    @Test("authentication before connection start cannot qualify raw physical evidence")
    func reversedConnectionChronologyIsBlocked() {
        let authenticatedAt: UInt64 = 1_000
        let generation: UInt64 = 8
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: authenticatedAt + 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + 31_000_000_001,
            applicationPayloadCount: 0,
            connectionGeneration: generation
        )
        let observations = qualifyingObservations(generation: generation, authenticatedAt: authenticatedAt)

        #expect(
            TuyaAuthenticatedRawFD50Acceptance.verdict(
                authenticatedSnapshot: snapshot,
                observations: observations
            ) == .blocked(reason: "Authenticated connection chronology is unavailable or invalid.")
        )
    }

    private func qualifyingObservations(
        generation: UInt64,
        authenticatedAt: UInt64
    ) -> [TuyaAuthenticatedRawFD50Acceptance.Observation] {
        [
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: generation,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 1,
                payloadByteCount: 4
            ),
            TuyaAuthenticatedRawFD50Acceptance.Observation(
                connectionGeneration: generation,
                characteristicUUID: TuyaAuthenticatedRawFD50Acceptance.deviceToAppNotifyCharacteristicUUID,
                observedAtUptimeNanoseconds: authenticatedAt + 31_000_000_001,
                payloadByteCount: 8
            )
        ]
    }
}
