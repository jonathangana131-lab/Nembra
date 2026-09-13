import Foundation

/// Portable proof that the package-owned live preflight observed the documented Smart Life
/// transport milestone as satisfied for one exact authenticated generation.
///
/// The embedded evidence preserves the exact retained device-to-app callback bytes. This wrapper
/// additionally records that those bytes were sampled from the same coherent `FieldAttemptEvidence`
/// cut whose transport milestone was satisfied, so a saved field artifact does not have to infer
/// first-stage transport acceptance from a UI log line.
///
/// This is deliberately *not* raw FD50 characteristic custody. Tuya's documented transparent
/// callback does not expose the underlying GATT characteristic identity, so this proof cannot mint
/// physical-first acceptance, scooter DP semantics, writes, pairing, reset, removal, or unbind.
public struct C7D09A22DocumentedTransportAcceptanceProof: Codable, Equatable, Sendable {
    public static let evidenceKind = "c7d09a22-documented-authenticated-transport-acceptance"

    public let kind: String
    public let connectionGeneration: UInt64
    public let documentedTransportAcceptanceSatisfied: Bool
    public let evidence: C7D09A22DocumentedTransparentEvidenceArtifact

    public init?(
        fieldAttempt: C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence
    ) {
        guard fieldAttempt.satisfiesDocumentedAuthenticatedTransportAcceptance,
              fieldAttempt.milestone == .satisfied,
              let generation = fieldAttempt.connectionGeneration,
              generation > 0,
              let artifact = fieldAttempt.artifact,
              artifact.sourceConnectionGeneration == generation,
              artifact.validatedReceiveEvidence(connectionGeneration: generation) != nil else {
            return nil
        }

        kind = Self.evidenceKind
        connectionGeneration = generation
        documentedTransportAcceptanceSatisfied = true
        evidence = artifact
    }

    /// Revalidates all byte-preserving provenance that remains portable after the live session.
    /// The boolean is accepted only in combination with the exact package-minted evidence kind,
    /// generation binding, and self-consistent retained callback bytes.
    public var hasValidPortableDocumentedTransportAcceptanceProof: Bool {
        guard kind == Self.evidenceKind,
              documentedTransportAcceptanceSatisfied,
              connectionGeneration > 0,
              evidence.sourceConnectionGeneration == connectionGeneration else {
            return false
        }
        return evidence.validatedReceiveEvidence(connectionGeneration: connectionGeneration) != nil
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}

public extension C7D09A22DocumentedTransparentLivePreflight {
    /// Returns portable documented Smart Life receive evidence only when the exact armed
    /// authenticated generation has crossed the physical transport liveness boundary.
    ///
    /// Unlike `evidenceArtifact()`, which is intentionally useful for diagnostics before the
    /// historical rejection horizon, this accessor is acceptance-scoped: it samples one coherent
    /// package-owned field-attempt cut and exposes bytes only when that same cut proves repeated
    /// documented device-to-app receive plus independent authenticated-session survival beyond the
    /// post-authentication rejection window.
    ///
    /// This remains documented SDK transport evidence. It does not identify the underlying FD50
    /// GATT characteristic and cannot authorize DP semantics, control writes, pairing, reset,
    /// removal, or unbind.
    func acceptedDocumentedTransportEvidenceArtifact() async -> C7D09A22DocumentedTransparentEvidenceArtifact? {
        let evidence = await fieldAttemptEvidence()
        guard evidence.satisfiesDocumentedAuthenticatedTransportAcceptance else {
            return nil
        }
        return evidence.artifact
    }

    /// Produces a durable package-owned record of the first-stage physical-truth milestone.
    /// A proof exists only when the same coherent field-attempt cut contains repeated retained
    /// documented receive bytes and the independently observed authenticated transport milestone.
    /// It intentionally remains weaker than raw FD50 characteristic custody.
    func acceptedDocumentedTransportProofArtifact() async -> C7D09A22DocumentedTransportAcceptanceProof? {
        C7D09A22DocumentedTransportAcceptanceProof(fieldAttempt: await fieldAttemptEvidence())
    }
}
