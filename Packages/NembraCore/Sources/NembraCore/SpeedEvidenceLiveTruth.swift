import Foundation

/// App/session-owned generation for speed-evidence continuity.
///
/// This is not a scooter protocol identifier and does not prove a physical BLE
/// session. A production adapter advances it whenever its accepted connection
/// continuity changes so delayed evidence from an older app connection cannot be
/// promoted into the current speed truth.
public struct SpeedEvidenceConnectionGeneration: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
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
    case nonAuthoritativeSample
    case nonMonotonicReceipt
}

/// Pure state machine that separates a cached `VehicleState` speed number from
/// speed evidence that is current for the active connection continuity.
///
/// The model deliberately contains no guessed ES80 cadence or freshness timeout.
/// A caller may mark an explicit evidence gap when its verified/injected policy
/// says continuity was lost. Reconnect itself always demotes prior evidence to
/// retained until a new accepted absolute sample arrives in the new generation.
public struct SpeedEvidenceLiveTruth: Equatable, Sendable {
    public private(set) var availability: SpeedEvidenceAvailability = .unavailable
    public private(set) var activeConnectionGeneration: SpeedEvidenceConnectionGeneration?
    public private(set) var latestConnectionGeneration: SpeedEvidenceConnectionGeneration?

    private var lastAcceptedReceiptUptimeNanoseconds: UInt64?

    public init() {}

    /// Starts or reasserts a connected app-session generation.
    ///
    /// Reasserting the current generation is idempotent. A strictly newer
    /// generation creates a continuity boundary and demotes any prior live sample
    /// to retained. Older generations fail closed so late connection callbacks
    /// cannot resurrect old speed authority.
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
                return .success(())
            }
        }

        latestConnectionGeneration = generation
        activeConnectionGeneration = generation
        demoteToRetained()
        return .success(())
    }

    /// Ends the active connection generation without manufacturing a zero-speed
    /// sample. The last accepted sample remains retained when one exists.
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
        demoteToRetained()
        return .success(())
    }

    /// Marks field-specific observation continuity as interrupted while the
    /// transport may remain connected. This is the explicit hook for a caller's
    /// verified/injected freshness or telemetry-gap policy; the model itself does
    /// not invent a timeout.
    @discardableResult
    public mutating func markEvidenceGap(
        in generation: SpeedEvidenceConnectionGeneration
    ) -> Result<Void, SpeedEvidenceLiveTruthRejection> {
        guard let activeConnectionGeneration else {
            return .failure(.noActiveConnection)
        }
        guard activeConnectionGeneration == generation else {
            return .failure(.connectionGenerationMismatch)
        }

        demoteToRetained()
        return .success(())
    }

    /// Accepts one current absolute speed measurement for the active generation.
    ///
    /// The generation is supplied separately from the sample because the existing
    /// raw `SpeedTelemetrySample` intentionally models measurement provenance, not
    /// app connection continuity. This prevents a delayed pre-reconnect sample
    /// from becoming live merely because transport is currently connected.
    @discardableResult
    public mutating func accept(
        _ sample: SpeedTelemetrySample,
        in generation: SpeedEvidenceConnectionGeneration
    ) -> Result<Void, SpeedEvidenceLiveTruthRejection> {
        guard let activeConnectionGeneration else {
            return .failure(.noActiveConnection)
        }
        guard activeConnectionGeneration == generation else {
            return .failure(.connectionGenerationMismatch)
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
