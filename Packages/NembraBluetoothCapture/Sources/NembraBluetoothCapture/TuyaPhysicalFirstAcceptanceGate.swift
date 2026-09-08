import Foundation

/// Non-secret evidence from Tuya's documented, authenticated device-to-app receive path.
///
/// This deliberately does not claim raw FD50 characteristic custody and carries no DP meaning.
/// The payload bytes may be retained separately by the capture artifact, but this gate only needs
/// receipt chronology/provenance to decide whether first physical transport acceptance is earned.
public struct TuyaAuthenticatedReceiveEvidence: Equatable, Sendable {
    public enum Provenance: String, Codable, Equatable, Sendable {
        /// Evidence delivered by the official Smart Life SDK's documented receive-only
        /// device-to-app transparent transport callback for the current authenticated generation.
        case smartLifeDocumentedDeviceToAppReceive = "tuya-smartlife-documented-device-to-app-receive"
    }

    public let provenance: Provenance
    public let connectionGeneration: UInt64
    public let payloadCount: Int
    public let latestPayloadUptimeNanoseconds: UInt64?

    public init(
        provenance: Provenance,
        connectionGeneration: UInt64,
        payloadCount: Int,
        latestPayloadUptimeNanoseconds: UInt64?
    ) {
        self.provenance = provenance
        self.connectionGeneration = connectionGeneration
        self.payloadCount = max(0, payloadCount)
        self.latestPayloadUptimeNanoseconds = latestPayloadUptimeNanoseconds
    }
}

/// Canonical first-physical-acceptance composition boundary.
///
/// Generic SDK DP/application callbacks are intentionally insufficient here. The authenticated
/// session must first satisfy `TuyaAuthenticatedReadOnlyPreflight`, and the same generation must
/// separately produce repeated evidence through Tuya's documented receive-only device-to-app path
/// strictly beyond C7D09A22's historical ~30 second rejection boundary.
///
/// This type performs no BLE writes, no DP queries/commands, no reset/unbind, and assigns no
/// speed/battery/mode/light/brake/power semantics.
public enum TuyaPhysicalFirstAcceptanceGate {
    public static let minimumDocumentedReceivePayloadCount = 2

    public enum Verdict: Equatable, Sendable {
        case blocked(reason: String)
        case readyForPhysicalFirstAcceptance
    }

    public static func verdict(
        preflight snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        receiveEvidence: TuyaAuthenticatedReceiveEvidence?
    ) -> Verdict {
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            return .blocked(reason: "Canonical authenticated read-only preflight is not ready.")
        }
        guard let receiveEvidence else {
            return .blocked(reason: "Documented authenticated device-to-app receive evidence is required.")
        }
        guard receiveEvidence.provenance == .smartLifeDocumentedDeviceToAppReceive else {
            return .blocked(reason: "Documented receive evidence has unsupported provenance.")
        }
        guard receiveEvidence.connectionGeneration > 0,
              receiveEvidence.connectionGeneration == snapshot.connectionGeneration else {
            return .blocked(reason: "Documented receive evidence does not belong to the current authenticated connection generation.")
        }
        guard receiveEvidence.payloadCount >= minimumDocumentedReceivePayloadCount else {
            return .blocked(reason: "Repeated documented authenticated receive payloads are required.")
        }
        guard let authenticatedAt = snapshot.authenticatedAtUptimeNanoseconds,
              let latestObserved = snapshot.latestObservedUptimeNanoseconds,
              let latestReceive = receiveEvidence.latestPayloadUptimeNanoseconds,
              latestReceive >= authenticatedAt,
              latestObserved >= latestReceive else {
            return .blocked(reason: "Documented receive chronology is unavailable or invalid.")
        }
        guard latestReceive - authenticatedAt > TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds else {
            return .blocked(reason: "Documented authenticated receive payloads have not survived beyond the historical rejection window yet.")
        }
        return .readyForPhysicalFirstAcceptance
    }
}
