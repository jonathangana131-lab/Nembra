public enum BatteryEvidenceStreamValidationError: Error, Equatable, Sendable {
    case missingReceiptIdentity
    case staleReceiptIdentity
    case acquisitionEpochChanged
    case inconsistentReceiptMetadata
    case nonMonotonicUptime
    case missingContinuityBoundary
    case staleCurrentnessOwner
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
///
/// `BatteryEvidenceStreamValidator` deliberately remains a value type for deterministic
/// chronology testing. Accepted/seen chronology stays value data. Live-currentness authority is
/// different: validators owned by `AcceptedBatterySOCStream` share one revocable reference-backed
/// generation. Copying such a validator cannot snapshot R1 currentness and replay it after the
/// owner crosses a gap or newer receipt, even though the copy still truthfully reports its local
/// last accepted chronology for diagnostics.
public struct BatteryEvidenceStreamValidator: Equatable, Sendable {
    private var acceptedReceiptIdentity: BatteryEvidenceReceiptIdentity?
    private var acceptedUptimeNanoseconds: UInt64?
    private var continuityBoundaryRequired: Bool

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

    /// Present only when a higher owner such as `AcceptedBatterySOCStream` binds this validator
    /// to live-currentness authority. Standalone validators remain useful chronology checkers but
    /// cannot mint owner-bound live range authority.
    private var currentnessOwner: BatteryEvidenceCurrentnessOwner?
    private var currentnessGeneration: BatteryEvidenceCurrentnessOwner.Generation?

    /// Accepted chronology remains the local value-state even if a later observed callback revokes
    /// live currentness. Do not infer currentness from these diagnostics; owner-bound anchors and
    /// live estimates use opaque leases instead.
    public var lastAcceptedReceiptIdentity: BatteryEvidenceReceiptIdentity? {
        acceptedReceiptIdentity
    }

    public var lastAcceptedUptimeNanoseconds: UInt64? {
        acceptedUptimeNanoseconds
    }

    public var requiresContinuityBoundary: Bool {
        continuityBoundaryRequired
    }

    public init() {
        acceptedReceiptIdentity = nil
        acceptedUptimeNanoseconds = nil
        continuityBoundaryRequired = false
        lastSeenReceiptIdentity = nil
        lastSeenReceiptUptimeNanoseconds = nil
        lastSeenReceiptContinuity = nil
        seenUptimeFloorNanoseconds = nil
        currentnessOwner = nil
        currentnessGeneration = nil
    }

    /// Trusted owner binding used by the accepted SoC chronology owner. A raw public validator
    /// intentionally has no live-currentness capability; it can validate order but cannot by
    /// itself prove that a retained receipt is still the live owner's receipt.
    init(currentnessOwner: BatteryEvidenceCurrentnessOwner) {
        self.init()
        self.currentnessOwner = currentnessOwner
        currentnessGeneration = currentnessOwner.generation()
    }

    /// Records that battery evidence continuity is no longer known.
    ///
    /// The prior accepted receipt/uptime baseline and the raw-callback watermarks are
    /// intentionally retained. The first post-gap observation must come from a genuinely
    /// newer receipt and explicitly carry the boundary. This prevents an already-seen or
    /// delayed pre-gap receipt from reopening the stream merely because its uptime happens
    /// to equal or exceed the accepted baseline.
    ///
    /// If this validator is an old copy of an owner-bound validator, the shared owner is not
    /// moved backwards. The stale copy becomes incapable of minting currentness on its next
    /// admission attempt.
    public mutating func markUnobservedInterval() {
        continuityBoundaryRequired = true

        guard let currentnessOwner,
              let currentnessGeneration,
              let replacement = currentnessOwner.invalidateIfOwned(
                by: currentnessGeneration,
                requiresContinuityBoundary: true
              ) else { return }
        self.currentnessGeneration = replacement
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
        try requireCurrentnessOwnershipIfBound()

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
                guard acceptedReceiptIdentity == receiptIdentity,
                      !continuityBoundaryRequired else {
                    throw BatteryEvidenceStreamValidationError.staleReceiptIdentity
                }

                try requirePublishedCurrentnessIfBound(
                    receiptIdentity: receiptIdentity,
                    uptimeNanoseconds: observation.receivedAtUptimeNanoseconds
                )
                return
            }

            guard receiptIdentity.sequenceNumber > lastSeenReceiptIdentity.sequenceNumber else {
                throw BatteryEvidenceStreamValidationError.staleReceiptIdentity
            }
        }

        // A genuinely newer seen callback revokes the old live-currentness generation before
        // later admission checks. Even if uptime/continuity rejection follows, R1 must not remain
        // presentable as live merely because R2 failed semantic admission.
        try invalidateCurrentnessForNewReceiptIfBound()

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

        if let acceptedReceiptIdentity {
            // Defensive consistency: accepted and seen identities should remain in one epoch.
            guard receiptIdentity.acquisitionEpoch == acceptedReceiptIdentity.acquisitionEpoch else {
                throw BatteryEvidenceStreamValidationError.acquisitionEpochChanged
            }
        }

        if continuityBoundaryRequired,
           observation.continuity != .afterUnobservedInterval {
            throw BatteryEvidenceStreamValidationError.missingContinuityBoundary
        }

        acceptedReceiptIdentity = receiptIdentity
        acceptedUptimeNanoseconds = observation.receivedAtUptimeNanoseconds
        continuityBoundaryRequired = false

        try publishCurrentnessIfBound(
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: observation.receivedAtUptimeNanoseconds
        )
    }

    /// Returns the owner-bound lease for exactly the receipt this validator still owns.
    /// Standalone validators and stale copies deliberately return nil.
    func currentnessLease(
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64
    ) -> BatteryEvidenceCurrentnessLease? {
        guard let currentnessOwner,
              let currentnessGeneration,
              currentnessOwner.isCurrent(
                generation: currentnessGeneration,
                receiptIdentity: receiptIdentity,
                uptimeNanoseconds: uptimeNanoseconds
              ) else { return nil }
        return BatteryEvidenceCurrentnessLease(
            ownerHandle: currentnessOwner.leaseHandle,
            generation: currentnessGeneration
        )
    }

    func recognizesCurrentnessLease(
        _ lease: BatteryEvidenceCurrentnessLease,
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64
    ) -> Bool {
        guard let currentnessOwner,
              let currentnessGeneration,
              currentnessOwner.leaseHandle === lease.ownerHandle,
              currentnessGeneration === lease.generation else { return false }
        return lease.isCurrent(
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: uptimeNanoseconds
        )
    }

    public static func == (
        lhs: BatteryEvidenceStreamValidator,
        rhs: BatteryEvidenceStreamValidator
    ) -> Bool {
        // Equality remains chronology-value equality for diagnostics/tests. Live-currentness
        // authority is intentionally not reducible to value equality.
        lhs.acceptedReceiptIdentity == rhs.acceptedReceiptIdentity
            && lhs.acceptedUptimeNanoseconds == rhs.acceptedUptimeNanoseconds
            && lhs.continuityBoundaryRequired == rhs.continuityBoundaryRequired
            && lhs.lastSeenReceiptIdentity == rhs.lastSeenReceiptIdentity
            && lhs.lastSeenReceiptUptimeNanoseconds == rhs.lastSeenReceiptUptimeNanoseconds
            && lhs.lastSeenReceiptContinuity == rhs.lastSeenReceiptContinuity
            && lhs.seenUptimeFloorNanoseconds == rhs.seenUptimeFloorNanoseconds
    }

    private func requireCurrentnessOwnershipIfBound() throws {
        guard let currentnessOwner,
              let currentnessGeneration else { return }
        guard currentnessOwner.snapshotIfOwned(by: currentnessGeneration) != nil else {
            throw BatteryEvidenceStreamValidationError.staleCurrentnessOwner
        }
    }

    private mutating func invalidateCurrentnessForNewReceiptIfBound() throws {
        guard let currentnessOwner,
              let currentnessGeneration else { return }
        guard let replacement = currentnessOwner.invalidateIfOwned(
            by: currentnessGeneration,
            requiresContinuityBoundary: continuityBoundaryRequired
        ) else {
            throw BatteryEvidenceStreamValidationError.staleCurrentnessOwner
        }
        self.currentnessGeneration = replacement
    }

    private func publishCurrentnessIfBound(
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64
    ) throws {
        guard let currentnessOwner,
              let currentnessGeneration else { return }
        guard currentnessOwner.publishIfOwned(
            by: currentnessGeneration,
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: uptimeNanoseconds,
            requiresContinuityBoundary: continuityBoundaryRequired
        ) else {
            throw BatteryEvidenceStreamValidationError.staleCurrentnessOwner
        }
    }

    private func requirePublishedCurrentnessIfBound(
        receiptIdentity: BatteryEvidenceReceiptIdentity,
        uptimeNanoseconds: UInt64
    ) throws {
        guard let currentnessOwner,
              let currentnessGeneration else { return }
        guard currentnessOwner.isCurrent(
            generation: currentnessGeneration,
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: uptimeNanoseconds
        ) else {
            throw BatteryEvidenceStreamValidationError.staleCurrentnessOwner
        }
    }
}
