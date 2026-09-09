import Foundation

/// Package-owned composition seam from the live documented Smart Life receive artifact to the
/// canonical physical-first acceptance gate.
///
/// Keeping this conversion here prevents app/UI code from reconstructing receive provenance,
/// connection generations, or chronology on its own. It performs no BLE writes, DP queries,
/// pairing, reset, removal, or unbind and grants no scooter-semantic authority.
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

        let receiveEvidence = TuyaAuthenticatedReceiveEvidence(
            provenance: .smartLifeDocumentedDeviceToAppReceive,
            connectionGeneration: generation,
            payloadCount: artifact.payloadCount,
            latestPayloadUptimeNanoseconds: artifact.latestPayloadAtUptimeNanoseconds
        )

        return TuyaPhysicalFirstAcceptanceGate.verdict(
            preflight: snapshot,
            receiveEvidence: receiveEvidence
        )
    }

    public static var authorizesRawFD50CharacteristicCustody: Bool { false }
    public static var authorizesStationaryMapping: Bool { false }
    public static var authorizesTelemetrySemantics: Bool { false }
    public static var authorizesControlWrites: Bool { false }
    public static var authorizesPairingResetOrUnbind: Bool { false }
}
