import Foundation

/// Fail-closed authority boundary between a Tuya SDK user session and permission to
/// attempt the authenticated ES80 BLE preflight.
///
/// A successful Tuya SDK login is intentionally insufficient. Tuya homes are the
/// device/permission boundary, so the exact expected device ID must be observed in
/// the logged-in SDK account's owned or shared device membership before BLE auth can
/// be attempted. This value object contains no account token, password, verification
/// code, local key, AppSecret, session key, or decrypted transport material.
public enum TuyaSDKAccountDeviceMembershipGate {
    public struct Snapshot: Equatable, Sendable {
        public let isLoggedIn: Bool
        public let homeEnumerationCompleted: Bool
        public let loadedHomeCount: Int
        public let ownedDeviceIDs: Set<String>
        public let sharedDeviceIDs: Set<String>
        public let homeLoadFailureCount: Int

        public init(
            isLoggedIn: Bool,
            homeEnumerationCompleted: Bool,
            loadedHomeCount: Int,
            ownedDeviceIDs: Set<String>,
            sharedDeviceIDs: Set<String>,
            homeLoadFailureCount: Int
        ) {
            self.isLoggedIn = isLoggedIn
            self.homeEnumerationCompleted = homeEnumerationCompleted
            self.loadedHomeCount = max(0, loadedHomeCount)
            self.ownedDeviceIDs = ownedDeviceIDs
            self.sharedDeviceIDs = sharedDeviceIDs
            self.homeLoadFailureCount = max(0, homeLoadFailureCount)
        }
    }

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case authorized
    }

    public static func verdict(
        expectedDeviceID: String,
        snapshot: Snapshot
    ) -> Verdict {
        let expected = expectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty else {
            return .blocked(reason: "Expected Tuya device ID is unavailable.")
        }
        guard snapshot.isLoggedIn else {
            return .blocked(reason: "Tuya SDK account session is not logged in.")
        }
        guard snapshot.homeEnumerationCompleted else {
            return .blocked(reason: "Tuya SDK home/device membership has not been enumerated yet.")
        }

        if snapshot.ownedDeviceIDs.contains(expected) || snapshot.sharedDeviceIDs.contains(expected) {
            return .authorized
        }

        if snapshot.homeLoadFailureCount > 0 {
            return .blocked(reason: "Tuya SDK home/device membership is incomplete because one or more homes failed to load.")
        }

        return .blocked(reason: "The logged-in Tuya SDK account does not contain the expected scooter device.")
    }
}
