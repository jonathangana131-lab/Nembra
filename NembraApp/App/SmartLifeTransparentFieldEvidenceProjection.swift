import Foundation
import NembraBluetoothCapture

/// App-facing, export-safe projection of the documented Tuya transparent receive lane.
///
/// This deliberately carries only transport provenance and exact received bytes. It does not
/// identify the underlying FD50 GATT characteristic and cannot assign scooter DP semantics.
struct SmartLifeTransparentFieldEvidenceProjection: Codable, Equatable, Sendable {
    struct Payload: Codable, Equatable, Sendable {
        let sequence: Int
        let receivedAtUptimeNanoseconds: UInt64
        let elapsedSinceSDKConnectionNanoseconds: UInt64
        let byteCount: Int
        let hex: String
    }

    /// Read-only status for the first physical transport acceptance gate.
    ///
    /// `acceptedSameAuthenticatedGeneration` means only that documented Tuya device->app bytes
    /// were retained for this exact authenticated generation and that payload evidence crossed
    /// the historical rejection horizon. It does not establish raw FD50 characteristic custody,
    /// DP semantics, stationary mapping, or any control/write authority.
    enum DocumentedTransportAcceptanceState: String, Codable, Equatable, Sendable {
        case waitingForFirstAuthenticatedPayload
        case waitingForPayloadBeyondHistoricalRejectionHorizon
        case acceptedSameAuthenticatedGeneration
    }

    let connectionGeneration: UInt64
    let tuyaDeviceID: String
    let payloads: [Payload]
    let payloadCount: Int
    let totalByteCount: Int
    let omittedPayloadCount: Int
    let hasPayloadStrictlyBeyondHistoricalRejectionHorizon: Bool
    let satisfiesDocumentedAuthenticatedTransportAcceptance: Bool
    let documentedTransportAcceptanceState: DocumentedTransportAcceptanceState

    let authorizesRawFD50CharacteristicCustody = false
    let authorizesPhysicalFirstAcceptance = false
    let authorizesStationaryMapping = false
    let authorizesTelemetrySemantics = false
    let authorizesControlWrites = false
    let authorizesPairingResetOrUnbind = false

    init?(
        evidence: C7D09A22DocumentedTransparentLivePreflight.FieldAttemptEvidence
    ) {
        guard let generation = evidence.connectionGeneration,
              let artifact = evidence.artifact else {
            return nil
        }

        connectionGeneration = generation
        tuyaDeviceID = artifact.tuyaDeviceID
        payloads = artifact.retainedPayloads.map {
            Payload(
                sequence: $0.sequence,
                receivedAtUptimeNanoseconds: $0.receivedAtUptimeNanoseconds,
                elapsedSinceSDKConnectionNanoseconds: $0.elapsedSinceSDKConnectionNanoseconds,
                byteCount: $0.byteCount,
                hex: $0.hex
            )
        }
        payloadCount = artifact.payloadCount
        totalByteCount = artifact.totalByteCount
        omittedPayloadCount = artifact.omittedPayloadCount
        hasPayloadStrictlyBeyondHistoricalRejectionHorizon = artifact.hasPayloadStrictlyBeyondHistoricalRejectionHorizon
        satisfiesDocumentedAuthenticatedTransportAcceptance = evidence.satisfiesDocumentedAuthenticatedTransportAcceptance

        if artifact.payloadCount == 0 {
            documentedTransportAcceptanceState = .waitingForFirstAuthenticatedPayload
        } else if artifact.hasPayloadStrictlyBeyondHistoricalRejectionHorizon,
                  evidence.satisfiesDocumentedAuthenticatedTransportAcceptance {
            documentedTransportAcceptanceState = .acceptedSameAuthenticatedGeneration
        } else {
            documentedTransportAcceptanceState = .waitingForPayloadBeyondHistoricalRejectionHorizon
        }
    }
}

#if canImport(ThingSmartHomeKit)
extension SmartLifeTransparentFieldSession {
    /// Returns an exact-generation, semantics-free field artifact suitable for diagnostics/export.
    /// A non-nil value proves only documented Tuya transport custody for the requested generation.
    func evidenceProjection(
        for connectionToken: Generation
    ) async -> SmartLifeTransparentFieldEvidenceProjection? {
        guard let evidence = await fieldAttemptEvidence(for: connectionToken),
              evidence.connectionGeneration == connectionToken.diagnosticGeneration else {
            return nil
        }
        return SmartLifeTransparentFieldEvidenceProjection(evidence: evidence)
    }
}
#endif
