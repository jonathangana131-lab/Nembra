import Foundation

/// Fail-closed policy for preserving the identity of the Tuya SDK account that
/// produced an exact-device membership proof.
///
/// `ThingSmartUser.isLogin` answers only whether *an* account session is current.
/// It cannot prove that the current account is the same account whose homes were
/// enumerated. The field app therefore captures the SDK's stable current-user UID
/// when exact scooter membership is accepted and must continuously compare that
/// in-memory identity with the current SDK UID until the physical attempt ends.
///
/// This type deliberately does not persist or export the UID. The UID is source
/// identity authority, not product telemetry or Capture artifact content.
public enum TuyaSDKAccountIdentityLeaseGate {
    public struct Snapshot: Equatable, Sendable {
        public let isLoggedIn: Bool
        public let currentAccountUID: String?
        public let membershipAccountUID: String?
        public let expectedDeviceID: String
        public let membershipDeviceID: String

        public init(
            isLoggedIn: Bool,
            currentAccountUID: String?,
            membershipAccountUID: String?,
            expectedDeviceID: String,
            membershipDeviceID: String
        ) {
            self.isLoggedIn = isLoggedIn
            self.currentAccountUID = currentAccountUID
            self.membershipAccountUID = membershipAccountUID
            self.expectedDeviceID = expectedDeviceID
            self.membershipDeviceID = membershipDeviceID
        }
    }

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case authorized
    }

    public static func verdict(for snapshot: Snapshot) -> Verdict {
        guard snapshot.isLoggedIn else {
            return .blocked(reason: "Tuya SDK account session is not logged in.")
        }
        guard let currentUID = normalized(snapshot.currentAccountUID) else {
            return .blocked(reason: "Current Tuya SDK account identity is unavailable.")
        }
        guard let membershipUID = normalized(snapshot.membershipAccountUID) else {
            return .blocked(reason: "Exact scooter membership is not bound to a Tuya SDK account identity.")
        }
        guard currentUID == membershipUID else {
            return .blocked(reason: "Tuya SDK account identity changed after scooter membership was verified.")
        }

        let expectedDeviceID = snapshot.expectedDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let membershipDeviceID = snapshot.membershipDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedDeviceID.isEmpty else {
            return .blocked(reason: "Expected Tuya scooter device ID is unavailable.")
        }
        guard !membershipDeviceID.isEmpty else {
            return .blocked(reason: "The account-bound membership proof has no scooter device ID.")
        }
        guard expectedDeviceID == membershipDeviceID else {
            return .blocked(reason: "Account-bound membership belongs to a different Tuya device.")
        }
        return .authorized
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
