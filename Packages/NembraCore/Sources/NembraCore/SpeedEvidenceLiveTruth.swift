import Foundation

/// App/session-owned generation for speed-evidence connection continuity.
///
/// This is not a scooter protocol identifier and does not prove a physical BLE
/// session. A production source adapter advances it whenever its accepted
/// connection continuity changes so delayed evidence from an older connection
/// cannot be promoted into current speed truth.
public struct SpeedEvidenceConnectionGeneration: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// Opaque source-attribution token for one uninterrupted speed-observation
/// segment inside one app connection generation.
///
/// Tokens are issued only by `SpeedEvidenceLiveTruth`. A source adapter should
/// retain the token that is current at the callback boundary and carry that exact
/// token with any asynchronously delivered sample. After an explicit evidence
/// gap, a new token is issued; queued callbacks carrying the previous token can
/// no longer resurrect pre-gap evidence.
public struct SpeedEvidenceContinuityToken: Equatable, Hashable, Sendable {
    public let connectionGeneration: SpeedEvidenceConnectionGeneration
    public let segmentSequence: UInt64

    fileprivate init(
        connectionGeneration: SpeedEvidenceConnectionGeneration,
        segmentSequence: UInt64
    ) {
        self.connectionGeneration = connectionGeneration
        self.segmentSequence = segmentSequence
    }
}

/// Field-specific currentness of the latest accepted absolute speed evidence.
///
/// Retained evidence may still be useful for explicitly last-known presentation,
/// but it must never authorize stopped-only controls, ride timing, or any other
/// behavior that requires a current measurement.
public enum SpeedEvidenceAvailability: Equatable, Sendable {
    case unavailable
    case retained(SpeedTelemetrySample)
    case live(SpeedTelemetrySample)

    public var currentAuthoritativeSample: SpeedTelemetrySample? {
        guard case let .live(sample) = self else { return nil }
        return sample
    }

    public var lastAcceptedSample: SpeedTelemetrySample? {
        switch self {
        case .unavailable:
            nil
        case let .retained(sample), let .live(sample):
            sample
        }
    }
}

public enum SpeedEvidenceLiveTruthRejection: Error, Equatable, Sendable {
    case invalidConnectionGeneration
    case staleConnectionGeneration
    case noActiveConnection
    case connectionGenerationMismatch
    case noActiveEvidenceContinuity
    case continuityTokenMismatch
    case continuitySegmentExhausted
    case nonAuthoritativeSample
    case nonMonotonicReceipt
}

/// Pure state machine that separates a cached `VehicleState` speed number from
/// speed evidence that is current for the active connection and field-observation
/// continuity.
///
/// The model deliberately contains no guessed ES80 cadence or freshness timeout.
/// A caller may mark an explicit evidence gap only when it has legitimate source
/// or lifecycle evidence that speed observation continuity was lost. Connection
/// changes and explicit field gaps both demote prior evidence to retained until a
/// newly source-attributed absolute measurement arrives.
public struct SpeedEvidenceLiveTruth: Equatable, Sendable {
    public private(set) var availability: SpeedEvidenceAvailability = .unavailable
    public private(set) var activeConnectionGeneration: SpeedEvidenceConnectionGeneration?
    public private(set) var latestConnectionGeneration: SpeedEvidenceConnectionGeneration?
    public private(set) var activeContinuityToken: SpeedEvidenceContinuityToken?

    private var lastAcceptedReceiptUptimeNanoseconds: UInt64?

    public init() {}

    /// Starts or reasserts a connected app-session generation.
    ///
    /// Reasserting the current active generation is idempotent and preserves the
    /// current field-continuity token. A strictly newer generation creates a new
    /// field-continuity segment and demotes any prior live sample to retained.
    /// Older generations fail closed so late connection callbacks cannot
    /// resurrect old speed authority.
    @discardableResult
    public mutating func beginConnectedGeneration(
        _ generation: SpeedEvidenceConnectionGeneration
    ) -> Result<Void, SpeedEvidenceLiveTruthRejection> {
        guard generation.rawValue > 0 else {
            return .failure(.invalidConnectionGeneration)
        }

        if let latestConnectionGeneration {
            if generation.rawValue < latestConnectionGeneration.rawValue {
                return .failure(.staleConnectionGeneration)
            }
            if generation == latestConnectionGeneration {
                guard activeConnectionGeneration == generation else {
                    return .failure(.staleConnectionGeneration)
                }
                guard activeContinuityToken != nil else {
                    return .failure(.noActiveEvidenceContinuity)
                }
                return .success(())
            }
        }

        latestConnectionGeneration = generation
        activeConnectionGeneration = generation
        activeContinuityToken = SpeedEvidenceContinuityToken(
            connectionGeneration: generation,
            segmentSequence: 1
        )
        demoteToRetained()
        return .success(())
    }

    /// Ends the active connection generation without manufacturing a zero-speed
    /// sample. The last accepted sample remains retained when one exists, and all
    /// source tokens from the ended generation become unusable.
    @discardableResult
    public mutating func endConnectedGeneration(
        _ generation: SpeedEvidenceConnectionGeneration
    ) -> Result<Void, SpeedEvidenceLiveTruthRejection> {
        guard generation.rawValue > 0 else {
            return .failure(.invalidConnectionGeneration)
        }
        guard let activeConnectionGeneration else {
            return .failure(.noActiveConnection)
        }
        guard activeConnectionGeneration == generation else {
            return .failure(.connectionGenerationMismatch)
        }

        self.activeConnectionGeneration = nil
        activeContinuityToken = nil
        demoteToRetained()
        return .success(())
    }

    /// Marks one explicit field-observation gap and rotates the source token.
    ///
    /// The caller must supply the token that was current at the boundary where
    /// the gap was established. This prevents a delayed/stale gap callback from
    /// demoting a newer segment. Samples already attributed to the old token may
    /// still be delivered later, but `accept` will reject them mechanically.
    ///
    /// This operation does not guess a timeout and does not synthesize a receipt
    /// timestamp. The source/lifecycle layer owns the evidence that a real gap
    /// occurred; this type only preserves that boundary.
    @discardableResult
    public mutating func markEvidenceGap(
        after continuityToken: SpeedEvidenceContinuityToken
    ) -> Result<Void, SpeedEvidenceLiveTruthRejection> {
        guard activeConnectionGeneration != nil else {
            return .failure(.noActiveConnection)
        }
        guard let activeContinuityToken else {
            return .failure(.noActiveEvidenceContinuity)
        }
        guard continuityToken == activeContinuityToken else {
            return .failure(.continuityTokenMismatch)
        }

        guard activeContinuityToken.segmentSequence < UInt64.max else {
            // A real gap has still been observed. Retire live authority even
            // though no further segment can be represented in this generation.
            demoteToRetained()
            self.activeContinuityToken = nil
            return .failure(.continuitySegmentExhausted)
        }

        self.activeContinuityToken = SpeedEvidenceContinuityToken(
            connectionGeneration: activeContinuityToken.connectionGeneration,
            segmentSequence: activeContinuityToken.segmentSequence + 1
        )
        demoteToRetained()
        return .success(())
    }

    /// Accepts one current absolute speed measurement attributed at the source
    /// callback boundary to an exact connection + field-continuity token.
    ///
    /// The opaque token is intentionally stronger than reading "whatever
    /// connection is current now" in a later asynchronous consumer. A delayed
    /// pre-reconnect or pre-gap callback retains its old token and therefore
    /// cannot become live after continuity advances.
    @discardableResult
    public mutating func accept(
        _ sample: SpeedTelemetrySample,
        attributedTo continuityToken: SpeedEvidenceContinuityToken
    ) -> Result<Void, SpeedEvidenceLiveTruthRejection> {
        guard activeConnectionGeneration != nil else {
            return .failure(.noActiveConnection)
        }
        guard let activeContinuityToken else {
            return .failure(.noActiveEvidenceContinuity)
        }
        guard continuityToken == activeContinuityToken else {
            return .failure(.continuityTokenMismatch)
        }
        guard sample.isAuthoritativeMeasurement else {
            return .failure(.nonAuthoritativeSample)
        }
        if let lastAcceptedReceiptUptimeNanoseconds,
           sample.receivedAtUptimeNanoseconds <= lastAcceptedReceiptUptimeNanoseconds {
            return .failure(.nonMonotonicReceipt)
        }

        lastAcceptedReceiptUptimeNanoseconds = sample.receivedAtUptimeNanoseconds
        availability = .live(sample)
        return .success(())
    }

    private mutating func demoteToRetained() {
        if let lastAcceptedSample = availability.lastAcceptedSample {
            availability = .retained(lastAcceptedSample)
        } else {
            availability = .unavailable
        }
    }
}
