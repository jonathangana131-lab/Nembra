import Foundation

/// Portable record that the package-owned live preflight observed the documented Smart Life
/// transport milestone as satisfied for one exact authenticated generation and linked scooter.
///
/// The embedded evidence preserves the exact retained device-to-app callback bytes. This wrapper
/// additionally records that those bytes were sampled from the same coherent `FieldAttemptEvidence`
/// cut whose transport milestone was satisfied, and binds that cut to the exact linked Tuya device
/// identity used to select the authenticated scooter. A saved field artifact therefore cannot infer
/// first-stage transport acceptance from a UI log line or relabel accepted bytes as another scooter.
///
/// This type is intentionally `Encodable` but not `Decodable`: arbitrary external JSON must never
/// be able to mint an acceptance-shaped package value. A later app export may exact-byte seal the
/// emitted JSON, while imported/hand-edited JSON remains diagnostic data only.
///
/// This is deliberately *not* raw FD50 characteristic custody. Tuya's documented transparent
/// callback does not expose the underlying GATT characteristic identity, so this record cannot mint
/// physical-first acceptance, scooter DP semantics, writes, pairing, reset, removal, or unbind.
public struct C7D09A22DocumentedTransportAcceptanceProof: Encodable, Equatable, Sendable {
    public static let evidenceKind = "c7d09a22-documented-authenticated-transport-acceptance"

    public let kind: String
    public let connectionGeneration: UInt64
    public let linkedDeviceIdentity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity
    public let documentedTransportAcceptanceSatisfied: Bool
    public let evidence: C7D09A22DocumentedTransparentEvidenceArtifact

    public init?(
        fieldAttempt: C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence,
        linkedDeviceIdentity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity
    ) {
        guard fieldAttempt.satisfiesDocumentedAuthenticatedTransportAcceptance,
              fieldAttempt.milestone == .satisfied,
              let generation = fieldAttempt.connectionGeneration,
              generation > 0,
              let artifact = fieldAttempt.artifact,
              artifact.sourceConnectionGeneration == generation,
              artifact.tuyaDeviceID == linkedDeviceIdentity.deviceID,
              artifact.validatedReceiveEvidence(connectionGeneration: generation) != nil else {
            return nil
        }

        kind = Self.evidenceKind
        connectionGeneration = generation
        self.linkedDeviceIdentity = linkedDeviceIdentity
        documentedTransportAcceptanceSatisfied = true
        evidence = artifact
    }

    /// Revalidates only the portable exact-byte evidence embedded in this package-minted record.
    /// The live independent-liveness observation is what allowed this value to be minted; it is not
    /// reconstructed from portable JSON and this property deliberately makes no such claim.
    public var embeddedReceiveEvidenceIsSelfConsistent: Bool {
        guard kind == Self.evidenceKind,
              documentedTransportAcceptanceSatisfied,
              connectionGeneration > 0,
              evidence.sourceConnectionGeneration == connectionGeneration,
              evidence.tuyaDeviceID == linkedDeviceIdentity.deviceID else {
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
    /// Samples an acceptance cut across the actor boundaries used by the live preflight and then
    /// revalidates the exact active package token before returning it.
    ///
    /// `fieldAttemptEvidence()` necessarily awaits both the authenticated-session ledger and the
    /// transparent receive ledger. Swift actors are re-entrant across those awaits, so an app-level
    /// reconnect/re-arm can otherwise occur between the two samples. Diagnostic generation numbers
    /// are explicitly insufficient authority because independent ledgers can both mint generation
    /// `1`. The package-minted connection token is therefore captured before the first suspension and
    /// must remain exact-token equal before, between, and after the sampled cuts.
    ///
    /// Payload traffic may legitimately advance between the two cuts, so equality is intentionally
    /// not required. The second coherent cut is returned only while the exact same connection token
    /// remains armed. This does not create any new protocol or mutation authority.
    private func stableFieldAttemptEvidenceForAcceptance() async -> FieldAttemptEvidence? {
        guard hasActiveAuthenticatedGeneration,
              let expectedToken = activeConnectionTokenForAcceptanceFence,
              expectedToken.diagnosticGeneration > 0 else {
            return nil
        }

        let first = await fieldAttemptEvidence()
        guard first.connectionGeneration == expectedToken.diagnosticGeneration,
              hasActiveAuthenticatedGeneration,
              activeConnectionTokenForAcceptanceFence == expectedToken else {
            return nil
        }

        let second = await fieldAttemptEvidence()
        guard second.connectionGeneration == expectedToken.diagnosticGeneration,
              hasActiveAuthenticatedGeneration,
              activeConnectionTokenForAcceptanceFence == expectedToken else {
            return nil
        }

        return second
    }

    /// Returns portable documented Smart Life receive evidence only when the exact armed
    /// authenticated generation has crossed the physical transport liveness boundary.
    ///
    /// Unlike `evidenceArtifact()`, which is intentionally useful for diagnostics before the
    /// historical rejection horizon, this accessor is acceptance-scoped: it samples one stable
    /// package-owned field-attempt cut and exposes bytes only when that exact connection token
    /// proves repeated documented device-to-app receive plus independent authenticated-session
    /// survival beyond the post-authentication rejection window.
    ///
    /// This remains documented SDK transport evidence. It does not identify the underlying FD50
    /// GATT characteristic and cannot authorize DP semantics, control writes, pairing, reset,
    /// removal, or unbind.
    func acceptedDocumentedTransportEvidenceArtifact() async -> C7D09A22DocumentedTransparentEvidenceArtifact? {
        guard let evidence = await stableFieldAttemptEvidenceForAcceptance(),
              evidence.satisfiesDocumentedAuthenticatedTransportAcceptance else {
            return nil
        }
        return evidence.artifact
    }

    /// Produces a package-minted, emit-only record of the first-stage physical-truth milestone.
    /// A record exists only when a stable field-attempt cut contains repeated retained documented
    /// receive bytes, the independently observed authenticated transport milestone, and those bytes
    /// belong to the exact linked Tuya device identity supplied by the authenticated Smart Life
    /// connection path. It intentionally remains weaker than raw FD50 characteristic custody.
    func acceptedDocumentedTransportProofArtifact(
        linkedDeviceIdentity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity
    ) async -> C7D09A22DocumentedTransportAcceptanceProof? {
        guard let evidence = await stableFieldAttemptEvidenceForAcceptance() else {
            return nil
        }
        return C7D09A22DocumentedTransportAcceptanceProof(
            fieldAttempt: evidence,
            linkedDeviceIdentity: linkedDeviceIdentity
        )
    }
}
