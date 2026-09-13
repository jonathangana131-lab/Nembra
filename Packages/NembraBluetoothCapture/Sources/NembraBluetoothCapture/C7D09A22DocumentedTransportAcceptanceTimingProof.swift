import Foundation

/// Emit-only audit record for the exact timing cut that satisfied C7D09A22's documented
/// authenticated Smart Life transport milestone.
///
/// `C7D09A22DocumentedTransportAcceptanceProof` preserves the accepted callback bytes and linked
/// scooter identity. This companion record additionally preserves the package-owned authentication
/// boundary and the independent session-ledger observation that proved the same generation remained
/// alive beyond the historical unauthenticated rejection window.
///
/// The initializer requires a package-produced `TuyaAuthenticatedReadOnlyPreflightSnapshot` and
/// revalidates the retained callback chronology against it. App code cannot manufacture such a
/// snapshot because snapshot construction remains package-owned. The type is intentionally
/// `Encodable` but not `Decodable`, so imported or hand-edited JSON cannot mint acceptance.
///
/// This remains documented SDK transport evidence only. It never identifies the underlying FD50
/// GATT characteristic and grants no DP semantics, control writes, pairing, reset, removal, or
/// unbind authority.
public struct C7D09A22DocumentedTransportAcceptanceTimingProof: Encodable, Equatable, Sendable {
    public static let evidenceKind = "c7d09a22-documented-authenticated-transport-acceptance-timing"

    public let kind: String
    public let connectionGeneration: UInt64
    public let linkedDeviceIdentity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity
    public let connectionStartedAtUptimeNanoseconds: UInt64
    public let authenticatedAtUptimeNanoseconds: UInt64
    public let latestRetainedDocumentedReceiveAtUptimeNanoseconds: UInt64
    public let independentLivenessObservedAtUptimeNanoseconds: UInt64
    public let postAuthenticationReceiveSurvivalNanoseconds: UInt64
    public let postAuthenticationLivenessSurvivalNanoseconds: UInt64
    public let documentedTransportAcceptanceSatisfied: Bool
    public let evidence: C7D09A22DocumentedTransparentEvidenceArtifact

    public init?(
        fieldAttempt: C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence,
        linkedDeviceIdentity: C7D09A22DocumentedSmartLifeReadOnlyConnector.LinkedDeviceIdentity,
        livenessSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) {
        guard fieldAttempt.satisfiesDocumentedAuthenticatedTransportAcceptance,
              fieldAttempt.milestone == .satisfied,
              let generation = fieldAttempt.connectionGeneration,
              generation > 0,
              let artifact = fieldAttempt.artifact,
              artifact.sourceConnectionGeneration == generation,
              artifact.tuyaDeviceID == linkedDeviceIdentity.deviceID,
              let receiveEvidence = artifact.validatedReceiveEvidence(connectionGeneration: generation),
              livenessSnapshot.authenticationState == .authenticated,
              livenessSnapshot.authenticationMethod == .smartLifeAppSDK,
              livenessSnapshot.hasActiveCallbackAuthority,
              livenessSnapshot.connectionGeneration == generation,
              let connectionStarted = livenessSnapshot.connectionStartedAtUptimeNanoseconds,
              connectionStarted == artifact.sdkConnectionStartedAtUptimeNanoseconds,
              let authenticatedAt = livenessSnapshot.authenticatedAtUptimeNanoseconds,
              authenticatedAt >= connectionStarted,
              let latestObserved = livenessSnapshot.latestObservedUptimeNanoseconds,
              let latestRetainedReceive = receiveEvidence.latestPayloadUptimeNanoseconds,
              latestRetainedReceive >= authenticatedAt,
              latestObserved >= latestRetainedReceive else {
            return nil
        }

        let horizon = TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        let receiveSurvival = latestRetainedReceive - authenticatedAt
        let livenessSurvival = latestObserved - authenticatedAt
        guard receiveSurvival > horizon,
              livenessSurvival > horizon else {
            return nil
        }

        kind = Self.evidenceKind
        connectionGeneration = generation
        self.linkedDeviceIdentity = linkedDeviceIdentity
        connectionStartedAtUptimeNanoseconds = connectionStarted
        authenticatedAtUptimeNanoseconds = authenticatedAt
        latestRetainedDocumentedReceiveAtUptimeNanoseconds = latestRetainedReceive
        independentLivenessObservedAtUptimeNanoseconds = latestObserved
        postAuthenticationReceiveSurvivalNanoseconds = receiveSurvival
        postAuthenticationLivenessSurvivalNanoseconds = livenessSurvival
        documentedTransportAcceptanceSatisfied = true
        evidence = artifact
    }

    /// Revalidates only the immutable chronology and exact receive bytes embedded in this
    /// package-minted value. It does not turn serialized JSON back into live session authority.
    public var embeddedTimingAndReceiveEvidenceIsSelfConsistent: Bool {
        guard kind == Self.evidenceKind,
              documentedTransportAcceptanceSatisfied,
              connectionGeneration > 0,
              evidence.sourceConnectionGeneration == connectionGeneration,
              evidence.tuyaDeviceID == linkedDeviceIdentity.deviceID,
              evidence.sdkConnectionStartedAtUptimeNanoseconds == connectionStartedAtUptimeNanoseconds,
              authenticatedAtUptimeNanoseconds >= connectionStartedAtUptimeNanoseconds,
              independentLivenessObservedAtUptimeNanoseconds >= latestRetainedDocumentedReceiveAtUptimeNanoseconds,
              let receiveEvidence = evidence.validatedReceiveEvidence(connectionGeneration: connectionGeneration),
              receiveEvidence.latestPayloadUptimeNanoseconds == latestRetainedDocumentedReceiveAtUptimeNanoseconds,
              latestRetainedDocumentedReceiveAtUptimeNanoseconds >= authenticatedAtUptimeNanoseconds else {
            return false
        }

        let receiveSurvival = latestRetainedDocumentedReceiveAtUptimeNanoseconds - authenticatedAtUptimeNanoseconds
        let livenessSurvival = independentLivenessObservedAtUptimeNanoseconds - authenticatedAtUptimeNanoseconds
        let horizon = TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds
        return receiveSurvival == postAuthenticationReceiveSurvivalNanoseconds
            && livenessSurvival == postAuthenticationLivenessSurvivalNanoseconds
            && receiveSurvival > horizon
            && livenessSurvival > horizon
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
