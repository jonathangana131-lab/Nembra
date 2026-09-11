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
    /// Diagnostic generation captured at artifact creation. This is provenance metadata only, not
    /// lifecycle authority: exact `TuyaReadOnlyConnectionToken` equality remains package-internal.
    /// Older/unbound artifacts decode as nil and deliberately cannot validate authenticated transport.
    public let sourceConnectionGeneration: UInt64?
    public let sdkConnectionStartedAtUptimeNanoseconds: UInt64
    public let payloadCount: Int
    public let totalByteCount: Int
    public let latestPayloadAtUptimeNanoseconds: UInt64?
    public let hasPayloadStrictlyBeyondHistoricalRejectionHorizon: Bool
    public let retainedPayloads: [Payload]
    public let retainedPayloadByteCount: Int
    public let omittedPayloadCount: Int

    /// Builds an unbound diagnostic artifact. It preserves bytes for inspection but cannot validate
    /// authenticated transport until the package-owned live preflight binds a source generation.
    public init(snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot) {
        self.init(snapshot: snapshot, connectionGeneration: nil)
    }

    /// Builds generation-bound diagnostic evidence from one package-owned authenticated attempt.
    public init(
        snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot,
        connectionGeneration: UInt64
    ) {
        self.init(
            snapshot: snapshot,
            sourceConnectionGeneration: connectionGeneration > 0 ? connectionGeneration : nil
        )
    }

    private init(
        snapshot: TuyaSmartLifeTransparentReceiveObservationLedger.Snapshot,
        sourceConnectionGeneration: UInt64?
    ) {
        kind = Self.evidenceKind
        tuyaDeviceID = snapshot.tuyaDeviceID
        self.sourceConnectionGeneration = sourceConnectionGeneration
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

    /// Reconstructs canonical receive evidence only from byte-preserving retained callbacks.
    ///
    /// Portable JSON is diagnostic evidence, not an authority token. Summary counters/timestamps
    /// can therefore never be sufficient by themselves to mint physical-first acceptance. This
    /// validator requires the artifact's own generation provenance to match the requested generation,
    /// repeated retained payload bytes, valid monotonic chronology, internally consistent byte
    /// accounting, and a retained callback strictly beyond the historical rejection horizon. The
    /// returned evidence remains documented Smart Life transport evidence only.
    public func validatedReceiveEvidence(connectionGeneration: UInt64) -> TuyaAuthenticatedReceiveEvidence? {
        guard connectionGeneration > 0,
              sourceConnectionGeneration == connectionGeneration,
              kind == Self.evidenceKind,
              !tuyaDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payloadCount >= retainedPayloads.count,
              omittedPayloadCount >= 0,
              payloadCount == retainedPayloads.count + omittedPayloadCount,
              retainedPayloads.count >= TuyaPhysicalFirstAcceptanceGate.minimumDocumentedReceivePayloadCount else {
            return nil
        }

        var previousTimestamp: UInt64?
        var retainedBytes = 0
        var hasRetainedPostHorizonPayload = false
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

        for (index, payload) in retainedPayloads.enumerated() {
            guard payload.sequence == index + 1,
                  payload.byteCount > 0,
                  payload.receivedAtUptimeNanoseconds >= sdkConnectionStartedAtUptimeNanoseconds,
                  payload.elapsedSinceSDKConnectionNanoseconds == payload.receivedAtUptimeNanoseconds - sdkConnectionStartedAtUptimeNanoseconds,
                  payload.hex.utf8.count == payload.byteCount * 2,
                  payload.hex.unicodeScalars.allSatisfy({ hexDigits.contains($0) }) else {
                return nil
            }
            if let previousTimestamp,
               payload.receivedAtUptimeNanoseconds <= previousTimestamp {
                return nil
            }
            previousTimestamp = payload.receivedAtUptimeNanoseconds
            retainedBytes += payload.byteCount
            if payload.elapsedSinceSDKConnectionNanoseconds > TuyaSmartLifeTransparentReceiveObservationLedger.c7d09a22HistoricalRejectionNanoseconds {
                hasRetainedPostHorizonPayload = true
            }
        }

        guard retainedPayloadByteCount == retainedBytes,
              totalByteCount >= retainedPayloadByteCount,
              hasRetainedPostHorizonPayload,
              hasPayloadStrictlyBeyondHistoricalRejectionHorizon,
              let retainedLatest = retainedPayloads.last?.receivedAtUptimeNanoseconds,
              let declaredLatest = latestPayloadAtUptimeNanoseconds,
              declaredLatest >= retainedLatest else {
            return nil
        }

        if omittedPayloadCount == 0 {
            guard totalByteCount == retainedPayloadByteCount,
                  declaredLatest == retainedLatest else {
                return nil
            }
        }

        return TuyaAuthenticatedReceiveEvidence(
            provenance: .smartLifeDocumentedDeviceToAppReceive,
            connectionGeneration: connectionGeneration,
            payloadCount: retainedPayloads.count,
            latestPayloadUptimeNanoseconds: retainedLatest
        )
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
