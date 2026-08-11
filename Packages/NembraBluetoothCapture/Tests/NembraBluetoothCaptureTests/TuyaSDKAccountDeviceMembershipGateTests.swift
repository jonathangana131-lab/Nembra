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

    @Test("zero loaded homes cannot authorize caller-supplied membership")
    func zeroLoadedHomesCannotAuthorizeMembership() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 0,
            ownedDeviceIDs: [scooterID],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )

        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "Tuya SDK home/device membership has no successfully loaded homes.")
        )
    }

    @Test("zero loaded homes remain an unavailable authority state")
    func zeroLoadedHomesWithoutMembershipBlocks() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 0,
            ownedDeviceIDs: [],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )

        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "Tuya SDK home/device membership has no successfully loaded homes.")
        )
    }

    @Test("negative loaded-home count remains malformed and cannot authorize")
    func negativeLoadedHomeCountCannotAuthorize() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: -1,
            ownedDeviceIDs: [scooterID],
            sharedDeviceIDs: [],
            homeLoadFailureCount: 0
        )

        #expect(snapshot.loadedHomeCount == -1)
        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "Tuya SDK home/device membership has no successfully loaded homes.")
        )
    }

    @Test("negative home-load failure count cannot be normalized into authorization")
    func negativeHomeLoadFailureCountCannotAuthorize() {
        let snapshot = TuyaSDKAccountDeviceMembershipGate.Snapshot(
            isLoggedIn: true,
            homeEnumerationCompleted: true,
            loadedHomeCount: 1,
            ownedDeviceIDs: [scooterID],
            sharedDeviceIDs: [],
            homeLoadFailureCount: -1
        )

        #expect(snapshot.homeLoadFailureCount == -1)
        #expect(
            TuyaSDKAccountDeviceMembershipGate.verdict(expectedDeviceID: scooterID, snapshot: snapshot)
                == .blocked(reason: "Tuya SDK home/device membership is incomplete because one or more homes failed to load.")
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

    @Test("finding scooter in one loaded home cannot override incomplete membership")
    func partialPositiveMembershipStillBlocks() {
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
