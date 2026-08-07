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
/// Seen callback chronology is intentionally stronger than accepted semantic evidence.
/// Once a newer trusted receipt is observed, a later lower sequence can never re-enter just
/// because the newer receipt failed semantic/metadata admission. Likewise, one immutable
/// receipt may not be retried with different uptime or continuity metadata after rejection.
///
/// An explicit `.afterUnobservedInterval` observation starts a fresh continuity segment,
/// but it does not switch an existing validator into a different acquisition epoch. A real
/// process/acquisition restart must create a fresh validator. `markUnobservedInterval()`
/// requires a strictly newer receipt to carry the first post-gap boundary.
public struct BatteryEvidenceStreamValidator: Equatable, Sendable {
    public private(set) var lastAcceptedReceiptIdentity: BatteryEvidenceReceiptIdentity?
    public private(set) var lastAcceptedUptimeNanoseconds: UInt64?
    public private(set) var requiresContinuityBoundary: Bool

    /// Highest same-epoch raw callback identity observed by this validator, whether or not
    /// that callback ultimately produced accepted semantic evidence. This watermark prevents
    /// a rejected newer callback from reopening chronology for delayed older callbacks.
    private(set) var lastSeenReceiptIdentity: BatteryEvidenceReceiptIdentity?

    /// Exact immutable metadata belonging to `lastSeenReceiptIdentity`. Keep this separate
    /// from `seenUptimeFloorNanoseconds`: a rejected callback with backward uptime still has
    /// one exact receipt timestamp, but it must never lower the floor enforced on later
    /// callbacks.
    private var lastSeenReceiptUptimeNanoseconds: UInt64?
    private var lastSeenReceiptContinuity: BatteryEvidenceContinuity?

    /// Greatest monotonic uptime accepted as raw callback chronology in this acquisition
    /// epoch. A callback that arrives below this floor is consumed by receipt sequence but
    /// cannot lower the floor for a later callback.
    private var seenUptimeFloorNanoseconds: UInt64?

    public init() {
        lastAcceptedReceiptIdentity = nil
        lastAcceptedUptimeNanoseconds = nil
        requiresContinuityBoundary = false
        lastSeenReceiptIdentity = nil
        lastSeenReceiptUptimeNanoseconds = nil
        lastSeenReceiptContinuity = nil
        seenUptimeFloorNanoseconds = nil
    }

    /// Records that battery evidence continuity is no longer known.
    ///
    /// The prior accepted receipt/uptime baseline and the raw-callback watermarks are
    /// intentionally retained. The first post-gap observation must come from a genuinely
    /// newer receipt and explicitly carry the boundary. This prevents an already-seen or
    /// delayed pre-gap receipt from reopening the stream merely because its uptime happens
    /// to equal or exceed the accepted baseline.
    public mutating func markUnobservedInterval() {
        requiresContinuityBoundary = true
    }

    /// Validates process-local receipt ordering and advances accepted evidence atomically.
    ///
    /// A same-epoch receipt becomes part of seen callback chronology before later semantic
    /// admission checks. Rejection never promotes its battery value, but it also never makes
    /// the callback disappear from ordering history.
    ///
    /// This method never promotes `BatteryEvidenceRole`, changes semantic values, or
    /// decides whether an observation is suitable for adaptive-range learning.
    public mutating func accept(_ observation: BatteryEvidenceObservation) throws {
        guard let receiptIdentity = observation.receiptIdentity else {
            throw BatteryEvidenceStreamValidationError.missingReceiptIdentity
        }

        if let lastSeenReceiptIdentity {
            guard receiptIdentity.acquisitionEpoch == lastSeenReceiptIdentity.acquisitionEpoch else {
                throw BatteryEvidenceStreamValidationError.acquisitionEpochChanged
            }

            if receiptIdentity.sequenceNumber == lastSeenReceiptIdentity.sequenceNumber {
                guard observation.receivedAtUptimeNanoseconds == lastSeenReceiptUptimeNanoseconds,
                      observation.continuity == lastSeenReceiptContinuity else {
                    throw BatteryEvidenceStreamValidationError.inconsistentReceiptMetadata
                }

                // Sibling semantic fields are legal only for a receipt that already passed
                // stream admission. A receipt first seen through a rejected observation is
                // permanently consumed and cannot be retried into acceptance.
                guard lastAcceptedReceiptIdentity == receiptIdentity,
                      !requiresContinuityBoundary else {
                    throw BatteryEvidenceStreamValidationError.staleReceiptIdentity
                }
                return
            }

            guard receiptIdentity.sequenceNumber > lastSeenReceiptIdentity.sequenceNumber else {
                throw BatteryEvidenceStreamValidationError.staleReceiptIdentity
            }
        }

        // The receipt identity and its exact metadata are trusted callback-order facts even
        // if later uptime/continuity admission rejects the semantic observation. Consume the
        // sequence watermark first so delayed lower-sequence evidence can never become fresh.
        lastSeenReceiptIdentity = receiptIdentity
        lastSeenReceiptUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        lastSeenReceiptContinuity = observation.continuity

        // The monotonic uptime floor represents all prior same-epoch callbacks whose uptime
        // did not already violate chronology, including observations later rejected only for
        // semantic continuity. A backward callback is still consumed by sequence identity,
        // but cannot lower this floor and thereby make an older uptime acceptable later.
        if let seenUptimeFloorNanoseconds,
           observation.receivedAtUptimeNanoseconds < seenUptimeFloorNanoseconds {
            throw BatteryEvidenceStreamValidationError.nonMonotonicUptime
        }
        seenUptimeFloorNanoseconds = observation.receivedAtUptimeNanoseconds

        if let lastAcceptedReceiptIdentity {
            // Defensive consistency: accepted and seen identities should remain in one epoch.
            guard receiptIdentity.acquisitionEpoch == lastAcceptedReceiptIdentity.acquisitionEpoch else {
                throw BatteryEvidenceStreamValidationError.acquisitionEpochChanged
            }
        }

        if requiresContinuityBoundary,
           observation.continuity != .afterUnobservedInterval {
            throw BatteryEvidenceStreamValidationError.missingContinuityBoundary
        }

        lastAcceptedReceiptIdentity = receiptIdentity
        lastAcceptedUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        requiresContinuityBoundary = false
    }
}
