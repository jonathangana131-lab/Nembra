import Foundation

/// Package-owned composition seam from the live documented Smart Life receive artifact to the
/// canonical physical-first acceptance boundary.
///
/// Keeping this conversion here prevents app/UI code from reconstructing receive provenance,
/// connection generations, or chronology on its own. It performs no BLE writes, DP queries,
/// pairing, reset, removal, or unbind and grants no scooter-semantic authority.
///
/// Important: Tuya's documented device-to-app callback does not expose the underlying GATT
/// service/characteristic identity. Even repeated authenticated callback bytes that survive the
/// historical rejection horizon are therefore transport evidence only. They must never be
/// promoted into raw FD50 characteristic-notify custody or physical first acceptance.
public enum C7D09A22DocumentedTransportPhysicalAcceptance {
    public static func verdict(
        authenticatedPreflight snapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot,
        fieldAttempt: C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence
    ) -> TuyaPhysicalFirstAcceptanceGate.Verdict {
        guard let generation = fieldAttempt.connectionGeneration,
              generation > 0,
              generation == snapshot.connectionGeneration else {
            return .blocked(reason: "Documented transport evidence does not belong to the current authenticated connection generation.")
        }

        guard fieldAttempt.milestone == .satisfied,
              let artifact = fieldAttempt.artifact else {
            return TuyaPhysicalFirstAcceptanceGate.verdict(
                preflight: snapshot,
                receiveEvidence: nil
            )
        }

        guard artifact.kind == C7D09A22DocumentedTransparentEvidenceArtifact.evidenceKind else {
            return .blocked(reason: "Documented transport artifact has unsupported provenance.")
        }

        guard let connectionStartedAt = snapshot.connectionStartedAtUptimeNanoseconds,
              artifact.sdkConnectionStartedAtUptimeNanoseconds == connectionStartedAt else {
            return .blocked(reason: "Documented transport artifact does not belong to the exact authenticated SDK connection instance.")
        }

        guard let receiveEvidence = artifact.validatedReceiveEvidence(connectionGeneration: generation) else {
            return .blocked(reason: "Documented transport artifact does not contain self-consistent retained receive bytes and chronology.")
        }

        let documentedVerdict = TuyaPhysicalFirstAcceptanceGate.verdict(
            preflight: snapshot,
            receiveEvidence: receiveEvidence
        )
        guard documentedVerdict == .readyForPhysicalFirstAcceptance else {
            return documentedVerdict
        }

        // The SDK callback proves authenticated transport survival, not characteristic-level notify
        // provenance. C7D09A22PhysicalFirstAcceptance is the separate gate that requires retained,
        // non-empty raw characteristic notification bytes from the physical characteristic path.
        return .blocked(
            reason: "Authenticated documented transport survived the rejection window; raw FD50 characteristic notify custody is still required for physical first acceptance."
        )
    }

    public static var authorizesRawFD50CharacteristicCustody: Bool { false }
    public static var authorizesPhysicalFirstAcceptance: Bool { false }
    public static var authorizesStationaryMapping: Bool { false }
    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesControlWrites: Bool { false }
    public static var authorizesPairingResetOrUnbind: Bool { false }
}
