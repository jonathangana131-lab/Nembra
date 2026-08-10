import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya SDK account identity lease gate")
struct TuyaSDKAccountIdentityLeaseGateTests {
    private let expectedDeviceID = "es80-device-123"

    @Test("same logged-in account and exact device authorizes")
    func sameAccountAndDeviceAuthorizes() {
        #expect(verdict(true, "account-a", "account-a", expectedDeviceID) == .authorized)
    }

    @Test("account switch fails even while SDK remains logged in")
    func accountSwitchFailsClosed() {
        #expect(verdict(true, "account-b", "account-a", expectedDeviceID) == .blocked(reason: "Tuya SDK account identity changed after scooter membership was verified."))
    }

    @Test("logout invalidates an otherwise matching lease")
    func logoutFailsClosed() {
        #expect(verdict(false, "account-a", "account-a", expectedDeviceID) == .blocked(reason: "Tuya SDK account session is not logged in."))
    }

    @Test("missing or unbound account identity fails closed")
    func missingIdentityFailsClosed() {
        #expect(verdict(true, nil, "account-a", expectedDeviceID) == .blocked(reason: "Current Tuya SDK account identity is unavailable."))
        #expect(verdict(true, "account-a", nil, expectedDeviceID) == .blocked(reason: "Exact scooter membership is not bound to a Tuya SDK account identity."))
    }

    @Test("UID equality is exact after whitespace normalization")
    func uidEqualityIsExact() {
        #expect(verdict(true, "  account-a  ", "account-a", expectedDeviceID) == .authorized)
        #expect(verdict(true, "ACCOUNT-A", "account-a", expectedDeviceID) == .blocked(reason: "Tuya SDK account identity changed after scooter membership was verified."))
    }

    @Test("device substitution fails under the same account")
    func deviceSubstitutionFailsClosed() {
        #expect(verdict(true, "account-a", "account-a", "different-device") == .blocked(reason: "Account-bound membership belongs to a different Tuya device."))
    }

    @Test("blank identity and blank expected device never authorize")
    func blankInputsFailClosed() {
        #expect(verdict(true, "   ", "account-a", expectedDeviceID) == .blocked(reason: "Current Tuya SDK account identity is unavailable."))
        let blankExpected = TuyaSDKAccountIdentityLeaseGate.Snapshot(
            isLoggedIn: true,
            currentAccountUID: "account-a",
            membershipAccountUID: "account-a",
            expectedDeviceID: " ",
            membershipDeviceID: expectedDeviceID
        )
        #expect(TuyaSDKAccountIdentityLeaseGate.verdict(for: blankExpected) == .blocked(reason: "Expected Tuya scooter device ID is unavailable."))
    }

    private func verdict(
        _ isLoggedIn: Bool,
        _ currentUID: String?,
        _ membershipUID: String?,
        _ membershipDeviceID: String
    ) -> TuyaSDKAccountIdentityLeaseGate.Verdict {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: .init(
            isLoggedIn: isLoggedIn,
            currentAccountUID: currentUID,
            membershipAccountUID: membershipUID,
            expectedDeviceID: expectedDeviceID,
            membershipDeviceID: membershipDeviceID
        ))
    }
}
