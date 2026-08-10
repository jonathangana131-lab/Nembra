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
            connectionGeneration: 1
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated state has no accepted Tuya authentication provenance."))
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

    @Test("authenticated payload still requires more than old disconnect window")
    func durationRequired() {
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: 10,
            latestObservedUptimeNanoseconds: 44_999_999_999,
            applicationPayloadCount: 1,
            connectionGeneration: 1
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .blocked(reason: "Authenticated connection has not survived the physical stability window yet."))
    }

    @Test("authenticated SDK payload and 45 second survival unlock stationary mapping")
    func acceptedSDKPhysicalGate() {
        let authenticatedAt: UInt64 = 10
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .smartLifeAppSDK,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: 1,
            connectionGeneration: 2
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }

    @Test("documented device-sharing provenance can unlock the same read-only gate")
    func acceptedDeviceSharingPhysicalGate() {
        let authenticatedAt: UInt64 = 20
        let snapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: .authenticated,
            authenticationMethod: .documentedDeviceSharing,
            connectionStartedAtUptimeNanoseconds: 1,
            authenticatedAtUptimeNanoseconds: authenticatedAt,
            latestObservedUptimeNanoseconds: authenticatedAt + TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds,
            applicationPayloadCount: 2,
            connectionGeneration: 3
        )
        #expect(TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping)
    }
}
