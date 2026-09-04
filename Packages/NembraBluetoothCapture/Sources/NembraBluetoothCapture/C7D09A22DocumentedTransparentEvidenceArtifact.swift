import Foundation

/// Portable, non-secret evidence from Tuya's documented device-to-app transparent receive path.
///
/// This artifact is intentionally narrower than physical first acceptance. It preserves the exact
/// callback bytes retained by `TuyaSmartLifeTransparentReceiveObservationLedger`, their monotonic
/// chronology, and whether authenticated transport produced a payload strictly beyond C7D09A22's
/// historical ~30-second unauthenticated rejection horizon. The documented callback does not expose
/// the underlying GATT service/characteristic tuple, so this artifact cannot mint raw-FD50 custody,
/// DP semantics, stationary mapping, or control authority.
public struct C7D09A22DocumentedTransparentEvidenceArtifact: Codable, Equatable, Sendable {
    public static let evidenceKind = "tuya-smart-life-documented-transparent-receive"

    public struct Payload: Codable, Equatable, Sendable {
        public let sequence: Int
        public let receivedAtUptimeNanoseconds: UInt64
        public let elapsedSinceSDKConnectionNanoseconds: UInt64
        public let byteCount: Int
        public let hex: String
    }

    public let kind: String
    public let tuyaDeviceID: String
    public let sdkConnectionStartedAtUptimeNanoseconds: UInt64
    public let payloadCount: Int
    public let totalByteCount: Int
    public let latestPayloadAtUptimeNanoseconds: UInt64?
    public let hasPayloadStrictlyBeyondHistoricalRejectionHorizon: Bool
    public let retainedPayloads: [Payload]
    public let retainedPayloadByteCount: Int
    public let omittedPayloadCount: Int

    public init(snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot) {
        kind = Self.evidenceKind
        tuyaDeviceID = snapshot.tuyaDeviceID
        sdkConnectionStartedAtUptimeNanoseconds = snapshot.sdkConnectionStartedAtUptimeNanoseconds
        payloadCount = snapshot.payloadCount
        totalByteCount = snapshot.totalByteCount
        latestPayloadAtUptimeNanoseconds = snapshot.latestPayloadAtUptimeNanoseconds
        hasPayloadStrictlyBeyondHistoricalRejectionHorizon = snapshot.hasPayloadStrictlyBeyondHistoricalRejectionHorizon
        retainedPayloads = snapshot.retainedPayloads.enumerated().map { index, retained in
            Payload(
                sequence: index + 1,
                receivedAtUptimeNanoseconds: retained.receivedAtUptimeNanoseconds,
                elapsedSinceSDKConnectionNanoseconds: retained.receivedAtUptimeNanoseconds - snapshot.sdkConnectionStartedAtUptimeNanoseconds,
                byteCount: retained.byteCount,
                hex: retained.hex
            )
        }
        retainedPayloadByteCount = snapshot.retainedPayloadByteCount
        omittedPayloadCount = snapshot.omittedPayloadCount
    }

    /// Deterministic JSON suitable for attaching to a field capture without exposing account secrets.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    // Documented SDK-transparent evidence remains diagnostic-only.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
