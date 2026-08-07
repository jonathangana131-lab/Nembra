public enum BatteryEvidenceStreamValidationError: Error, Equatable, Sendable {
    case missingReceiptIdentity
    case staleReceiptIdentity
    case acquisitionEpochChanged
    case inconsistentReceiptMetadata
    case nonMonotonicUptime
    case missingContinuityBoundary
}

/// Process-local ordering guard for normalized battery evidence.
///
/// Callback identity, not uptime equality, establishes whether two observations came from
/// the same raw receipt. A receipt consists of one acquisition epoch plus a strict sequence
/// number minted before semantic normalization fans out. Several sibling fields may share
/// the same receipt identity. Distinct higher-sequence callbacks remain distinct even when
/// the monotonic clock reports the same uptime tick.
///
/// Uptime remains a chronology/age constraint inside one acquisition epoch: it may stay
/// equal or increase across newer receipts but must never move backwards. Wall-clock dates
/// are deliberately ignored for ordering because the system clock can move.
///
/// An explicit `.afterUnobservedInterval` observation starts a fresh continuity segment,
/// but it does not switch an existing validator into a different acquisition epoch. A real
/// process/acquisition restart must create a fresh validator. `markUnobservedInterval()`
/// requires a strictly newer receipt to carry the first post-gap boundary.
public struct BatteryEvidenceStreamValidator: Equatable, Sendable {
    public private(set) var lastAcceptedReceiptIdentity: BatteryEvidenceReceiptIdentity?
    public private(set) var lastAcceptedUptimeNanoseconds: UInt64?
    public private(set) var requiresContinuityBoundary: Bool
    private var lastAcceptedReceiptContinuity: BatteryEvidenceContinuity?

    public init() {
        lastAcceptedReceiptIdentity = nil
        lastAcceptedUptimeNanoseconds = nil
        requiresContinuityBoundary = false
        lastAcceptedReceiptContinuity = nil
    }

    /// Records that battery evidence continuity is no longer known.
    ///
    /// The prior receipt/uptime baseline is intentionally retained. The first post-gap
    /// observation must be from a strictly newer receipt and explicitly carry the boundary.
    /// This prevents the already-seen receipt or any delayed pre-gap receipt from reopening
    /// the stream merely because its uptime happens to equal or exceed the old baseline.
    public mutating func markUnobservedInterval() {
        requiresContinuityBoundary = true
    }

    /// Validates process-local receipt ordering and advances the baseline atomically.
    ///
    /// This method never promotes `BatteryEvidenceRole`, changes semantic values, or
    /// decides whether an observation is suitable for adaptive-range learning.
    public mutating func accept(_ observation: BatteryEvidenceObservation) throws {
        guard let receiptIdentity = observation.receiptIdentity else {
            throw BatteryEvidenceStreamValidationError.missingReceiptIdentity
        }

        if let lastAcceptedReceiptIdentity {
            guard receiptIdentity.acquisitionEpoch == lastAcceptedReceiptIdentity.acquisitionEpoch else {
                throw BatteryEvidenceStreamValidationError.acquisitionEpochChanged
            }

            if receiptIdentity.sequenceNumber == lastAcceptedReceiptIdentity.sequenceNumber {
                guard !requiresContinuityBoundary else {
                    throw BatteryEvidenceStreamValidationError.staleReceiptIdentity
                }
                guard observation.receivedAtUptimeNanoseconds == lastAcceptedUptimeNanoseconds,
                      observation.continuity == lastAcceptedReceiptContinuity else {
                    throw BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata
                }

                // Same receipt + same receipt metadata is a sibling/idempotent stream event.
                // Field-level duplicate/conflict policy belongs to the snapshot accumulator.
                return
            }

            guard receiptIdentity.sequenceNumber > lastAcceptedReceiptIdentity.sequenceNumber else {
                throw BatteryEvidenceStreamValidationError.staleReceiptIdentity
            }

            if let lastAcceptedUptimeNanoseconds,
               observation.receivedAtUptimeNanoseconds < lastAcceptedUptimeNanoseconds {
                throw BatteryEvidenceStreamValidationError.nonMonotonicUptime
            }
        }

        if requiresContinuityBoundary,
           observation.continuity != .afterUnobservedInterval {
            throw BatteryEvidenceStreamValidationError.missingContinuityBoundary
        }

        lastAcceptedReceiptIdentity = receiptIdentity
        lastAcceptedUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        lastAcceptedReceiptContinuity = observation.continuity
        requiresContinuityBoundary = false
    }
}
