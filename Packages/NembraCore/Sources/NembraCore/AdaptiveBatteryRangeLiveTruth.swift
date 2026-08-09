import Foundation

public enum AdaptiveBatteryRangeLiveTruthError: Error, Equatable, Sendable {
    case notVerifiedStateOfCharge
    case missingReceiptIdentity
    case observationNotCurrentlyAccepted
}

/// Receipt-bound state-of-charge evidence that has crossed the battery stream validator.
///
/// This is the production-facing bridge between battery truth and adaptive range. It cannot
/// be constructed from a percentage, a generic `BatterySOCReading`, persisted JSON, stock-app
/// correlation data, or Simulator presentation state. A caller must present an authoritative
/// SoC observation whose exact raw receipt is still owned by the accepted battery chronology.
///
/// Live currentness is deliberately stronger than receipt metadata. Every anchor carries an
/// opaque process-local lease. Anchors minted by `AcceptedBatterySOCStream` receive its revocable
/// owner lease. Package-only one-off projections from a standalone chronology validator receive a
/// detached lease that can never be live; they exist only for adversarial/offline span validation
/// and are not an external product authority surface.
///
/// Copying an owner-bound validator at R1 therefore cannot preserve R1 authority after the real
/// owner crosses a gap, consumes a newer receipt, or accepts R2.
///
/// `continuitySegmentStartReceiptIdentity` is present only when the anchor was minted by
/// `AcceptedBatterySOCStream`, which observes the complete accepted battery chronology and can
/// prove which no-gap segment contains the sample.
///
/// The type is deliberately not Codable. Process-local receipt identity, continuity-segment
/// identity, and live-currentness must never survive persistence/relaunch by serialization.
public struct AcceptedBatterySOCAnchor: Equatable, Sendable {
    public let percentage: Double
    public let sourceReceiptIdentity: BatteryEvidenceReceiptIdentity
    public let receivedAtUptimeNanoseconds: UInt64
    public let continuity: BatteryEvidenceContinuity
    public let continuitySegmentStartReceiptIdentity: BatteryEvidenceReceiptIdentity?
    let currentnessLease: BatteryEvidenceCurrentnessLease

    fileprivate init(
        percentage: Double,
        sourceReceiptIdentity: BatteryEvidenceReceiptIdentity,
        receivedAtUptimeNanoseconds: UInt64,
        continuity: BatteryEvidenceContinuity,
        continuitySegmentStartReceiptIdentity: BatteryEvidenceReceiptIdentity?,
        currentnessLease: BatteryEvidenceCurrentnessLease
    ) {
        self.percentage = percentage
        self.sourceReceiptIdentity = sourceReceiptIdentity
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuity = continuity
        self.continuitySegmentStartReceiptIdentity = continuitySegmentStartReceiptIdentity
        self.currentnessLease = currentnessLease
    }

#if SWIFT_PACKAGE
    /// Package-only projection used by focused authority/negative tests and trusted package
    /// composition. External clients must obtain live anchors from `AcceptedBatterySOCStream`.
    package static func current(
        observation: BatteryEvidenceObservation,
        acceptedBy validator: BatteryEvidenceStreamValidator
    ) throws -> Self {
        try projectOneOff(
            observation: observation,
            acceptedBy: validator
        )
    }
#else
    /// When these package sources are compiled directly into the app, sibling app code cannot use
    /// the one-off projection as an alternate authority path. Live anchors come from the stream.
    fileprivate static func current(
        observation: BatteryEvidenceObservation,
        acceptedBy validator: BatteryEvidenceStreamValidator
    ) throws -> Self {
        try projectOneOff(
            observation: observation,
            acceptedBy: validator
        )
    }
#endif

    /// Projects a verified vehicle SoC observation whose immutable receipt metadata matches the
    /// supplied validator. The public product path does not expose this helper.
    ///
    /// If that validator is bound to `AcceptedBatterySOCStream`, the result receives its live
    /// owner lease. A standalone chronology validator deliberately yields a detached lease: the
    /// resulting one-off anchor can be inspected inside the package to prove that unsegmented
    /// evidence is rejected for learning, but `isCurrent` is false and live range estimation
    /// fails closed.
    ///
    /// A copy of an owner-bound validator re-admits the supplied observation before minting the
    /// anchor. That proves immutable continuity metadata matches the accepted receipt, while the
    /// shared owner lease proves the receipt is still live in the real chronology.
    private static func projectOneOff(
        observation: BatteryEvidenceObservation,
        acceptedBy validator: BatteryEvidenceStreamValidator
    ) throws -> Self {
        guard observation.isAdaptiveRangeSOCEvidence,
              observation.value.field == .stateOfChargePercent,
              let percentage = observation.value.numericValue else {
            throw AdaptiveBatteryRangeLiveTruthError.notVerifiedStateOfCharge
        }
        guard let receiptIdentity = observation.receiptIdentity else {
            throw AdaptiveBatteryRangeLiveTruthError.missingReceiptIdentity
        }
        guard validator.requiresContinuityBoundary == false,
              validator.lastAcceptedReceiptIdentity == receiptIdentity,
              validator.lastAcceptedUptimeNanoseconds == observation.receivedAtUptimeNanoseconds else {
            throw AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted
        }

        var validationCopy = validator
        do {
            try validationCopy.accept(observation)
        } catch {
            throw AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted
        }

        let currentnessLease: BatteryEvidenceCurrentnessLease
        if let ownerLease = validator.currentnessLease(
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: observation.receivedAtUptimeNanoseconds
        ) {
            currentnessLease = ownerLease
        } else {
            // A standalone chronology validator cannot become live authority merely because its
            // local value-state says R1 was accepted. Give the package-only projection a detached,
            // unpublished lease so every live-currentness check fails closed. The weak handle
            // intentionally does not keep `detachedOwner` alive past this scope.
            let detachedOwner = BatteryEvidenceCurrentnessOwner()
            currentnessLease = BatteryEvidenceCurrentnessLease(
                ownerHandle: detachedOwner.leaseHandle,
                generation: detachedOwner.generation()
            )
        }

        return Self(
            percentage: percentage,
            sourceReceiptIdentity: receiptIdentity,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuity: observation.continuity,
            continuitySegmentStartReceiptIdentity: nil,
            currentnessLease: currentnessLease
        )
    }

    /// True only while this anchor's opaque owner lease and exact receipt remain current.
    /// The validator argument is a lineage check, not by-value authority: a stale copied validator
    /// cannot revive the lease because every owner-bound copy observes revocation.
    public func isCurrent(in validator: BatteryEvidenceStreamValidator) -> Bool {
        validator.recognizesCurrentnessLease(
            currentnessLease,
            receiptIdentity: sourceReceiptIdentity,
            uptimeNanoseconds: receivedAtUptimeNanoseconds
        )
    }

    /// Owner-bound currentness without exposing or requiring a validator snapshot.
    public var isCurrent: Bool {
        currentnessLease.isCurrent(
            receiptIdentity: sourceReceiptIdentity,
            uptimeNanoseconds: receivedAtUptimeNanoseconds
        )
    }
}

/// Chronology owner that binds accepted SoC samples to an immutable no-gap battery segment.
///
/// The wrapped `BatteryEvidenceStreamValidator` remains the receipt/uptime/metadata authority.
/// This layer additionally binds that validator to one revocable currentness owner and records
/// which accepted receipt began the current continuity segment.
///
/// Copies of this value share the currentness owner. Once one live lineage advances, an older copy
/// cannot keep minting current anchors from its stale value-state: the shared generation has moved.
/// This deliberately turns copied stream values into fail-closed stale handles rather than
/// parallel currentness authorities.
///
/// All battery-bearing observations that participate in production chronology should pass through
/// this stream, not only SoC. Non-SoC siblings/callbacks advance receipt truth but simply return
/// nil instead of an SoC anchor.
public struct AcceptedBatterySOCStream: Equatable, Sendable {
    public private(set) var validator: BatteryEvidenceStreamValidator
    public private(set) var continuitySegmentStartReceiptIdentity: BatteryEvidenceReceiptIdentity?

    public init() {
        validator = BatteryEvidenceStreamValidator(
            currentnessOwner: BatteryEvidenceCurrentnessOwner()
        )
        continuitySegmentStartReceiptIdentity = nil
    }

    /// Records an explicit observation gap while preserving the prior segment as retained history.
    /// The segment identity switches only when a valid newer boundary receipt is accepted.
    /// The owner-bound validator revokes every outstanding R1 lease immediately.
    public mutating func markUnobservedInterval() {
        validator.markUnobservedInterval()
    }

    /// Admits one normalized battery observation and returns an anchor only for verified SoC.
    ///
    /// Receipt admission happens before segment mutation. A rejected/malformed boundary therefore
    /// cannot silently rotate the segment or mint an anchor. Same-receipt semantic siblings keep
    /// the same segment because the parent validator requires identical immutable metadata.
    ///
    /// A newer callback revokes the preceding currentness generation before later admission checks,
    /// matching the validator's stronger seen-chronology rule: a rejected newer callback must never
    /// leave an older accepted SoC looking live.
    @discardableResult
    public mutating func accept(
        _ observation: BatteryEvidenceObservation
    ) throws -> AcceptedBatterySOCAnchor? {
        try validator.accept(observation)

        guard let receiptIdentity = observation.receiptIdentity else {
            // Parent admission already requires this, so this is a defensive fail-closed path.
            throw AdaptiveBatteryRangeLiveTruthError.missingReceiptIdentity
        }

        if continuitySegmentStartReceiptIdentity == nil
            || observation.continuity == .afterUnobservedInterval {
            continuitySegmentStartReceiptIdentity = receiptIdentity
        }

        guard observation.isAdaptiveRangeSOCEvidence,
              observation.value.field == .stateOfChargePercent,
              let percentage = observation.value.numericValue else {
            return nil
        }

        guard let currentnessLease = validator.currentnessLease(
            receiptIdentity: receiptIdentity,
            uptimeNanoseconds: observation.receivedAtUptimeNanoseconds
        ) else {
            throw AdaptiveBatteryRangeLiveTruthError.observationNotCurrentlyAccepted
        }

        return AcceptedBatterySOCAnchor(
            percentage: percentage,
            sourceReceiptIdentity: receiptIdentity,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuity: observation.continuity,
            continuitySegmentStartReceiptIdentity: continuitySegmentStartReceiptIdentity,
            currentnessLease: currentnessLease
        )
    }
}
