import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya SDK account identity lease gate")
struct TuyaSDKAccountIdentityLeaseGateTests {
    private let expectedDeviceID = "es80-device-123"

    @Test("same logged-in account and exact device authorizes")
    func sameAccountAndDeviceAuthorizes() {
        #expect(verdict(
            isLoggedIn: true,
            currentUID: "account-a",
            membershipUID: "account-a",
            membershipDeviceID: expectedDeviceID
        ) == .authorized)
    }

    @Test("account switch fails even while SDK remains logged in")
    func accountSwitchFailsClosed() {
        #expect(verdict(
            isLoggedIn: true,
            currentUID: "account-b",
            membershipUID: "account-a",
            membershipDeviceID: expectedDeviceID
        ) == .blocked(reason: "Tuya SDK account identity changed after scooter membership was verified."))
    }

    @Test("logged-out state invalidates an otherwise matching lease")
    func logoutFailsClosed() {
        #expect(verdict(
            isLoggedIn: false,
            currentUID: "account-a",
            membershipUID: "account-a",
            membershipDeviceID: expectedDeviceID
        ) == .blocked(reason: "Tuya SDK account session is not logged in."))
    }

    @Test("missing current account identity fails closed")
    func missingCurrentUIDFailsClosed() {
        #expect(verdict(
            isLoggedIn: true,
            currentUID: nil,
            membershipUID: "account-a",
            membershipDeviceID: expectedDeviceID
        ) == .blocked(reason: "Current Tuya SDK account identity is unavailable."))
    }

    @Test("membership without bound account identity fails closed")
    func unboundMembershipFailsClosed() {
        #expect(verdict(
            isLoggedIn: true,
            currentUID: "account-a",
            membershipUID: nil,
            membershipDeviceID: expectedDeviceID
        ) == .blocked(reason: "Exact scooter membership is not bound to a Tuya SDK account identity."))
    }

    @Test("account identity normalization does not relax equality")
    func trimsOnlyWhitespace() {
        #expect(verdict(
            isLoggedIn: true,
            currentUID: "  account-a  ",
            membershipUID: "account-a",
            membershipDeviceID: expectedDeviceID
        ) == .authorized)
        #expect(verdict(
            isLoggedIn: true,
            currentUID: "ACCOUNT-A",
            membershipUID: "account-a",
            membershipDeviceID: expectedDeviceID
        ) == .blocked(reason: "Tuya SDK account identity changed after scooter membership was verified."))
    }

    @Test("device substitution fails under the same account")
    func deviceSubstitutionFailsClosed() {
        #expect(verdict(
            isLoggedIn: true,
            currentUID: "account-a",
            membershipUID: "account-a",
            membershipDeviceID: "different-device"
        ) == .blocked(reason: "Account-bound membership belongs to a different Tuya device."))
    }

    @Test("blank identities and device IDs are never authority")
    func blankInputsFailClosed() {
        #expect(verdict(
            isLoggedIn: true,
            currentUID: "   ",
            membershipUID: "account-a",
            membershipDeviceID: expectedDeviceID
        ) == .blocked(reason: "Current Tuya SDK account identity is unavailable."))

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
        isLoggedIn: Bool,
        currentUID: String?,
        membershipUID: String?,
        membershipDeviceID: String
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
