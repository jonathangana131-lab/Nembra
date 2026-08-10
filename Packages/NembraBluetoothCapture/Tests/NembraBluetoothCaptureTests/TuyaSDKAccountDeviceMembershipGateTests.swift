import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya SDK account device membership gate")
struct TuyaSDKAccountDeviceMembershipGateTests {
    private let scooterID = "expected-es80-device-id"

    @Test("logged in alone is not device authority")
    func loginAloneBlocks() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 1,
            ownedDeviceIDs: ["some-other-device"],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )

        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "The logged-in Tuya SDK account does not contain the expected scooter device.")
        )
    }

    @Test("membership must be enumerated after login")
    func enumerationRequired() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: false,
            loadedHomeCount: 0,
            ownedDeviceIDs: [scooterID],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )

        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "Tuya SDK home/device membership has not been enumerated yet.")
        )
    }

    @Test("exact owned device membership authorizes")
    func ownedMembershipAuthorizes() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 1,
            ownedDeviceIDs: [scooterID],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )

        #expect(TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot) == .authorized)
    }

    @Test("exact shared device membership authorizes")
    func sharedMembershipAuthorizes() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 2,
            ownedDeviceIDs: [],
            sharedDeviceIDs: [scooterID],
            homeLoadFailureCount: 0
        )

        #expect(TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot) == .authorized)
    }

    @Test("incomplete home loading fails closed when scooter was not found")
    func incompleteMembershipBlocks() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 1,
            ownedDeviceIDs: [],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 1
        )

        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "Tuya SDK home/device membership is incomplete because one or more homes failed to load.")
        )
    }

    @Test("partial home loading cannot authorize even when one loaded home contains the scooter")
    func foundScooterDoesNotOverrideIncompleteMembership() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 1,
            ownedDeviceIDs: [scooterID],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 1
        )

        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "Tuya SDK home/device membership is incomplete because one or more homes failed to load.")
        )
    }

    @Test("expected device ID itself is required")
    func expectedIDRequired() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 1,
            ownedDeviceIDs: [],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )

        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: "   ", snapshot: snapshot)
                == .blocked(reason: "Expected Tuya device ID is unavailable.")
        )
    }
}
