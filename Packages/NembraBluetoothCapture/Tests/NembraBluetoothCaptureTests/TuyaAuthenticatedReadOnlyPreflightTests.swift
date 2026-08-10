import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya authenticated read-only preflight")
struct TuyaAuthenticatedReadOnlyPreflightTests {
    @Test("missing authentication fails closed")
    func missingAuthenticationBlocks() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .waitingForAuthentication,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: nil,
            latestObservedUptimeNanoseconds: 50_000_000_001,
            applicationPayloadCount: 0,
            connectionGeneration: 1
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Tuya authentication required."))
    }

    @Test("authentication without accepted provenance fails closed")
    func provenanceRequired() {
        let authenticatedAt: UInt64 = 10
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: 1,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt + 1,
            connectionGeneration: 1
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated state has no accepted SmartLife SDK BLE provenance."))
    }

    @Test("authentication without payload fails closed")
    func payloadRequired() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: 2,
            latestObservedUptimeNanoseconds: 50_000_000_002,
            applicationPayloadCount: 0,
            connectionGeneration: 1
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated session has not produced an application payload yet."))
    }

    @Test("stale payload from before current authentication fails closed")
    func stalePayloadChronologyBlocks() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 10_000,
            authenticatedAtUptimeNanoseconds: 20_000,
            latestObservedUptimeNanoseconds: 45_000_020_000,
            applicationPayloadCount: 1,
            latestApplicationPayloadUptimeNanoseconds: 19_999,
            connectionGeneration: 2
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated connection chronology is unavailable or invalid."))
    }

    @Test("authentication timestamp before current connection fails closed")
    func authenticationBeforeConnectionBlocks() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 20_000,
            authenticatedAtUptimeNanoseconds: 19_999,
            latestObservedUptimeNanoseconds: 45_000_020_000,
            applicationPayloadCount: 1,
            latestApplicationPayloadUptimeNanoseconds: 20_001,
            connectionGeneration: 2
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated connection chronology is unavailable or invalid."))
    }

    @Test("authenticated payload still requires full physical stability window")
    func durationRequired() {
        let authenticatedAt: UInt64 = 10
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds - 1,
            applicationPayloadCount: 1,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt + 1,
            connectionGeneration: 1
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated connection has not survived the physical stability window yet."))
    }

    @Test("authenticated SmartLife SDK payload and 45 second survival unlock stationary mapping")
    func acceptedSDKPhysicalGate() {
        let authenticatedAt: UInt64 = 10
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: 1,
            latestApplicationPayloadUptimeNanoseconds: authenticatedAt + 1,
            connectionGeneration: 2
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }
}
