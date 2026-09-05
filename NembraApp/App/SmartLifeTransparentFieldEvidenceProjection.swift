import Foundation
import NembraBluetoothCapture

/// App-facing, export-safe projection of the documented Tuya transparent receive lane.
///
/// This deliberately carries only transport provenance and exact received bytes. It does not
/// identify the underlying FD50 GATT characteristic and cannot assign scooter DP semantics.
struct SmartLifeTransparentFieldEvidenceProjection: Codable, Equatable, Sendable {
    struct Payload: Codable, Equatable, Sendable {
        let receivedAtUptimeNanoseconds: UInt64
        let hex: String
    }

    let connectionGeneration: UInt64
    let tuyaDeviceID: String
    let payloads: [Payload]
    let payloadCount: Int
    let hasPayloadStrictlyBeyondHistoricalRejectionHorizon: Bool
    let satisfiesDocumentedAuthenticatedTransportAcceptance: Bool

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
        payloads = artifact.payloads.map {
            Payload(
                receivedAtUptimeNanoseconds: $0.receivedAtUptimeNanoseconds,
                hex: $0.hex
            )
        }
        payloadCount = artifact.payloadCount
        hasPayloadStrictlyBeyondHistoricalRejectionHorizon = artifact.hasPayloadStrictlyBeyondHistoricalRejectionHorizon
        satisfiesDocumentedAuthenticatedTransportAcceptance = evidence.satisfiesDocumentedAuthenticatedTransportAcceptance
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
