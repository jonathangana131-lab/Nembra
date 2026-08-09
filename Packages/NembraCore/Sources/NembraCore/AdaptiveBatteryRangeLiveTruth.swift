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
/// SoC observation whose exact raw receipt is still the validator's current accepted receipt.
///
/// `continuitySegmentStartReceiptIdentity` is present only when the anchor was minted by
/// `AcceptedBatterySOCStream`, which observes the complete accepted battery chronology and can
/// prove which no-gap segment contains the sample. A one-off current projection deliberately
/// leaves that identity nil: endpoint metadata alone cannot prove span continuity for learning.
///
/// The type is deliberately not Codable. Process-local receipt identity, continuity-segment
/// identity, and live-currentness must never survive persistence/relaunch by serialization.
public struct AcceptedBatterySOCAnchor: Equatable, Sendable {
    public let percentage: Double
    public let sourceReceiptIdentity: BatteryEvidenceReceiptIdentity
    public let receivedAtUptimeNanoseconds: UInt64
    public let continuity: BatteryEvidenceContinuity
    public let continuitySegmentStartReceiptIdentity: BatteryEvidenceReceiptIdentity?

    fileprivate init(
        percentage: Double,
        sourceReceiptIdentity: BatteryEvidenceReceiptIdentity,
        receivedAtUptimeNanoseconds: UInt64,
        continuity: BatteryEvidenceContinuity,
        continuitySegmentStartReceiptIdentity: BatteryEvidenceReceiptIdentity?
    ) {
        self.percentage = percentage
        self.sourceReceiptIdentity = sourceReceiptIdentity
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuity = continuity
        self.continuitySegmentStartReceiptIdentity = continuitySegmentStartReceiptIdentity
    }

    /// Projects only a currently accepted verified vehicle SoC observation into live range input.
    ///
    /// A copy of the validator re-admits the supplied observation before minting the anchor. That
    /// is stronger than comparing receipt+uptime alone: it also proves immutable continuity
    /// metadata matches the receipt already accepted by the validator. A forged same-receipt
    /// sibling with different `.continuous` / `.afterUnobservedInterval` metadata therefore
    /// cannot become trusted range evidence.
    ///
    /// This one-off projection intentionally has no continuity-segment identity. It is sufficient
    /// for a current live estimate, but insufficient for learning across a span. Learning anchors
    /// must be minted by `AcceptedBatterySOCStream`, which observes every accepted boundary.
    public static func current(
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

        return Self(
            percentage: percentage,
            sourceReceiptIdentity: receiptIdentity,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuity: observation.continuity,
            continuitySegmentStartReceiptIdentity: nil
        )
    }

    /// True only while this exact receipt remains the validator's current accepted evidence.
    /// A marked gap immediately makes a retained anchor non-current even before a replacement
    /// battery sample arrives.
    public func isCurrent(in validator: BatteryEvidenceStreamValidator) -> Bool {
        validator.requiresContinuityBoundary == false
            && validator.lastAcceptedReceiptIdentity == sourceReceiptIdentity
            && validator.lastAcceptedUptimeNanoseconds == receivedAtUptimeNanoseconds
    }
}

/// Chronology owner that binds accepted SoC samples to an immutable no-gap battery segment.
///
/// The wrapped `BatteryEvidenceStreamValidator` remains the receipt/uptime/metadata authority.
/// This layer adds only one fact the endpoint validator cannot reconstruct later: which accepted
/// receipt began the current continuity segment. The segment start changes only when the first
/// accepted post-gap receipt carries `.afterUnobservedInterval` (or on the first accepted receipt
/// of a fresh stream).
///
/// All battery-bearing observations that participate in production chronology should pass through
/// this stream, not only SoC. Non-SoC siblings/callbacks advance receipt truth but simply return
/// nil instead of an SoC anchor.
public struct AcceptedBatterySOCStream: Equatable, Sendable {
    public private(set) var validator: BatteryEvidenceStreamValidator
    public private(set) var continuitySegmentStartReceiptIdentity: BatteryEvidenceReceiptIdentity?

    public init() {
        validator = BatteryEvidenceStreamValidator()
        continuitySegmentStartReceiptIdentity = nil
    }

    /// Records an explicit observation gap while preserving the prior segment as retained history.
    /// The segment identity switches only when a valid newer boundary receipt is accepted.
    public mutating func markUnobservedInterval() {
        validator.markUnobservedInterval()
    }

    /// Admits one normalized battery observation and returns an anchor only for verified SoC.
    ///
    /// Receipt admission happens before segment mutation. A rejected/malformed boundary therefore
    /// cannot silently rotate the segment or mint an anchor. Same-receipt semantic siblings keep
    /// the same segment because the parent validator requires identical immutable metadata.
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

        return AcceptedBatterySOCAnchor(
            percentage: percentage,
            sourceReceiptIdentity: receiptIdentity,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuity: observation.continuity,
            continuitySegmentStartReceiptIdentity: continuitySegmentStartReceiptIdentity
        )
    }
}
