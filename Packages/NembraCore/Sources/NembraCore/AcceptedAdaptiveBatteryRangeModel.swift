import Foundation

public enum AcceptedAdaptiveRangeValidationError: Error, Equatable, Sendable {
    case invalidDistance
    case invalidReceiptOrder
    case acquisitionEpochChanged
    case missingContinuitySegmentIdentity
    case invalidPlausibilityPolicy
}

public enum AcceptedBatteryRangeLearningDeferralReason: Equatable, Sendable {
    /// No absolute plausibility ceiling is yet justified for a brand-new accepted model.
    /// Higher layers should retain candidate evidence and wait for repeated/trusted evidence,
    /// not invent an ES80 range ceiling or silently teach from the lone first window.
    case firstWindowPlausibilityUnverified
}

public enum AcceptedBatteryRangeLearningDisposition: Equatable, Sendable {
    case accepted
    case deferred(AcceptedBatteryRangeLearningDeferralReason)
    case rejected(BatteryRangeLearningRejectionReason)
}

/// Production-facing learning result. Deferral is distinct from rejection: the candidate may be
/// structurally trustworthy, but accepted learned history remains unchanged until the evidence
/// needed for a first-baseline plausibility decision exists.
public struct AcceptedBatteryRangeLearningResult: Equatable, Sendable {
    public let disposition: AcceptedBatteryRangeLearningDisposition
    public let sample: BatteryRangeEfficiencySample?
    public let confidence: AdaptiveRangeConfidence
}

/// Optional production plausibility screen for learned range windows.
///
/// This is deliberately separate from `AdaptiveBatteryRangePolicy` because it is a truth gate,
/// not a presentation/tuning default. Nembra does not currently know a verified ES80 full-charge
/// range ceiling. Production integration must therefore choose explicitly between:
/// - `deferredUntilVerifiedEvidence`, which makes no physical ceiling claim and deliberately
///   defers the first accepted learning window; or
/// - a finite positive maximum supplied only after a higher layer has legitimate evidence for a
///   conservative plausibility bound.
///
/// The bound is a rejection threshold for corrupted/discontinuous learning evidence. It is not
/// the scooter's rated range, learned typical range, advertised range, or a number to display.
public struct AcceptedAdaptiveRangePlausibilityPolicy: Equatable, Sendable {
    public let maximumFullChargeEquivalentMeters: Double?

    private init(maximumFullChargeEquivalentMeters: Double?) {
        self.maximumFullChargeEquivalentMeters = maximumFullChargeEquivalentMeters
    }

    /// Leaves the absolute first-window ceiling unavailable until evidence exists.
    /// On an empty accepted model, an otherwise-valid learning window is returned as deferred
    /// without mutating history. Once accepted history already exists, relative outlier policy can
    /// continue operating with this value if an absolute ceiling is still legitimately unknown.
    public static let deferredUntilVerifiedEvidence = Self(
        maximumFullChargeEquivalentMeters: nil
    )

    /// Creates an evidence-backed absolute plausibility ceiling.
    public init(maximumFullChargeEquivalentMeters: Double) throws {
        guard maximumFullChargeEquivalentMeters.isFinite,
              maximumFullChargeEquivalentMeters > 0 else {
            throw AcceptedAdaptiveRangeValidationError.invalidPlausibilityPolicy
        }
        self.maximumFullChargeEquivalentMeters = maximumFullChargeEquivalentMeters
    }
}

/// A receipt-bound range-learning window whose trusted construction is unavailable to ordinary
/// app source. The public raw `BatteryRangeLearningWindow` remains a useful pure-model fixture,
/// but it is not the production authority boundary.
///
/// The explicit private initializer is important for Nembra's current direct-source app
/// composition: without it Swift could synthesize a same-module memberwise initializer and
/// accidentally reopen the exact distance/coverage authority bypass this type is meant to seal.
///
/// Endpoint continuity metadata is not enough to prove a whole learning span stayed observed:
/// `R1 -> gap -> boundary R2 -> continuous R3` would otherwise let R1->R3 look continuous. Both
/// anchors must therefore carry continuity-segment identity minted by `AcceptedBatterySOCStream`.
/// A segment change automatically taints the window as a transport gap even when a higher layer
/// incorrectly supplies `transportGapOccurred: false`.
public struct AcceptedBatteryRangeLearningWindow: Equatable, Sendable {
    public let distanceMeters: Double
    public let distanceCoverage: BatteryRangeDistanceCoverage
    public let transportGapOccurred: Bool
    public let startSOC: AcceptedBatterySOCAnchor
    public let endSOC: AcceptedBatterySOCAnchor

    private init(
        distanceMeters: Double,
        distanceCoverage: BatteryRangeDistanceCoverage,
        transportGapOccurred: Bool,
        startSOC: AcceptedBatterySOCAnchor,
        endSOC: AcceptedBatterySOCAnchor,
        trustedBoundary: Void
    ) throws {
        _ = trustedBoundary
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw AcceptedAdaptiveRangeValidationError.invalidDistance
        }
        guard startSOC.sourceReceiptIdentity.acquisitionEpoch
                == endSOC.sourceReceiptIdentity.acquisitionEpoch else {
            throw AcceptedAdaptiveRangeValidationError.acquisitionEpochChanged
        }
        guard endSOC.sourceReceiptIdentity.sequenceNumber
                > startSOC.sourceReceiptIdentity.sequenceNumber,
              endSOC.receivedAtUptimeNanoseconds > startSOC.receivedAtUptimeNanoseconds else {
            throw AcceptedAdaptiveRangeValidationError.invalidReceiptOrder
        }
        guard let startSegment = startSOC.continuitySegmentStartReceiptIdentity,
              let endSegment = endSOC.continuitySegmentStartReceiptIdentity else {
            throw AcceptedAdaptiveRangeValidationError.missingContinuitySegmentIdentity
        }
        guard startSegment.acquisitionEpoch == startSOC.sourceReceiptIdentity.acquisitionEpoch,
              endSegment.acquisitionEpoch == endSOC.sourceReceiptIdentity.acquisitionEpoch else {
            throw AcceptedAdaptiveRangeValidationError.acquisitionEpochChanged
        }

        self.distanceMeters = distanceMeters
        self.distanceCoverage = distanceCoverage
        self.transportGapOccurred = transportGapOccurred
            || startSegment != endSegment
            || endSOC.continuity == .afterUnobservedInterval
        self.startSOC = startSOC
        self.endSOC = endSOC
    }

#if SWIFT_PACKAGE
    /// Package-trusted construction for the ride-distance evidence bridge and tests.
    /// Direct app source does not receive this initializer.
    package init(
        distanceMeters: Double,
        distanceCoverage: BatteryRangeDistanceCoverage,
        transportGapOccurred: Bool,
        startSOC: AcceptedBatterySOCAnchor,
        endSOC: AcceptedBatterySOCAnchor
    ) throws {
        try self.init(
            distanceMeters: distanceMeters,
            distanceCoverage: distanceCoverage,
            transportGapOccurred: transportGapOccurred,
            startSOC: startSOC,
            endSOC: endSOC,
            trustedBoundary: ()
        )
    }
#endif
}

/// Production authority wrapper around the persistable adaptive-range math model.
///
/// `AdaptiveBatteryRangeModel` intentionally remains a reusable pure algorithm for tests,
/// simulation, offline research, and future migration. This wrapper is the stronger boundary
/// for live product use: ordinary app code cannot import arbitrary raw model state or feed it
/// caller-constructed learning windows. New production presentation should request live range
/// only through a receipt-bound `AcceptedBatterySOCAnchor` plus the validator that still owns it.
///
/// This type is deliberately non-Codable for now. Persisting learned production state needs an
/// explicit scooter-identity-bound envelope; generic decoding must not silently turn imported
/// math state into accepted learned history.
public struct AcceptedAdaptiveBatteryRangeModel: Equatable, Sendable {
    private var model: AdaptiveBatteryRangeModel

    public init() {
        model = AdaptiveBatteryRangeModel()
    }

#if SWIFT_PACKAGE
    /// Package-scoped restore hook for focused tests and a future trusted scooter-identity
    /// persistence boundary. It is not exposed to ordinary package clients or direct app code.
    package init(trustedRestoredModel: AdaptiveBatteryRangeModel) {
        model = trustedRestoredModel
    }
#endif

    public var hasLearnedEfficiency: Bool {
        model.hasLearnedEfficiency
    }

    public var historicalConsumedPercentagePoints: Double {
        model.historicalConsumedPercentagePoints
    }

    public var acceptedWindowCount: Int {
        model.acceptedWindowCount
    }

    public func confidence(using policy: AdaptiveBatteryRangePolicy) -> AdaptiveRangeConfidence {
        model.confidence(using: policy)
    }

    public func typicalFullChargeRangeMeters(
        using policy: AdaptiveBatteryRangePolicy
    ) -> Double? {
        model.typicalFullChargeRangeMeters(using: policy)
    }

#if SWIFT_PACKAGE
    /// Trusted package integration is the only mutation path into accepted learned history.
    /// The sealed anchors are converted to raw algorithm inputs only inside this boundary.
    ///
    /// On a brand-new accepted model, `.deferredUntilVerifiedEvidence` does **not** teach from the
    /// first lone window: an otherwise-valid candidate is returned as `.deferred` with no model
    /// mutation. A higher layer may collect repeated span-proven candidates and later supply a
    /// conservative evidence-backed ceiling. Do not invent a number merely to leave deferral.
    ///
    /// Once accepted history already exists, a missing absolute ceiling no longer blocks every
    /// future update; the raw model's learned relative-outlier policy remains available. If an
    /// absolute evidence-backed ceiling is supplied, it is applied to every otherwise-valid
    /// window as an additional fail-closed bound.
    @discardableResult
    package mutating func ingest(
        _ window: AcceptedBatteryRangeLearningWindow,
        policy: AdaptiveBatteryRangePolicy,
        plausibilityPolicy: AcceptedAdaptiveRangePlausibilityPolicy
    ) -> AcceptedBatteryRangeLearningResult {
        let confidenceBefore = model.confidence(using: policy)

        guard let start = try? BatterySOCReading(
            percentage: window.startSOC.percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: window.startSOC.receivedAtUptimeNanoseconds
        ),
        let end = try? BatterySOCReading(
            percentage: window.endSOC.percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: window.endSOC.receivedAtUptimeNanoseconds
        ),
        let rawWindow = try? BatteryRangeLearningWindow(
            distanceMeters: window.distanceMeters,
            distanceCoverage: window.distanceCoverage,
            transportGapOccurred: window.transportGapOccurred,
            startSOC: start,
            endSOC: end
        ) else {
            return AcceptedBatteryRangeLearningResult(
                disposition: .rejected(.numericalOverflow),
                sample: nil,
                confidence: confidenceBefore
            )
        }

        if window.distanceCoverage == .complete,
           window.transportGapOccurred == false {
            let consumed = window.startSOC.percentage - window.endSOC.percentage
            if consumed > 0,
               consumed >= policy.minimumConsumedPercentagePoints,
               window.distanceMeters >= policy.minimumDistanceMeters {
                let metersPerPercentagePoint = window.distanceMeters / consumed
                let fullChargeEquivalentMeters = metersPerPercentagePoint * 100
                guard fullChargeEquivalentMeters.isFinite else {
                    return AcceptedBatteryRangeLearningResult(
                        disposition: .rejected(.numericalOverflow),
                        sample: nil,
                        confidence: confidenceBefore
                    )
                }

                if model.hasLearnedEfficiency == false,
                   plausibilityPolicy.maximumFullChargeEquivalentMeters == nil {
                    return AcceptedBatteryRangeLearningResult(
                        disposition: .deferred(.firstWindowPlausibilityUnverified),
                        sample: nil,
                        confidence: confidenceBefore
                    )
                }

                if let maximum = plausibilityPolicy.maximumFullChargeEquivalentMeters,
                   fullChargeEquivalentMeters > maximum {
                    return AcceptedBatteryRangeLearningResult(
                        disposition: .rejected(.efficiencyOutlier),
                        sample: nil,
                        confidence: confidenceBefore
                    )
                }
            }
        }

        let rawResult = model.ingest(rawWindow, policy: policy)
        let disposition: AcceptedBatteryRangeLearningDisposition
        switch rawResult.disposition {
        case .accepted:
            disposition = .accepted
        case let .rejected(reason):
            disposition = .rejected(reason)
        }

        return AcceptedBatteryRangeLearningResult(
            disposition: disposition,
            sample: rawResult.sample,
            confidence: rawResult.confidence
        )
    }
#endif

    /// Returns a receipt-bound live estimate without accepting caller-constructed presentation
    /// carry-over. Until Nembra has a sealed continuity/scooter-identity-bound presentation state,
    /// production starts from the current evidence-derived raw range on every accepted estimate.
    /// This deliberately sacrifices smoothing rather than allowing a stale, cross-gap, or
    /// cross-scooter `Double` to masquerade as fresh presentation under a current receipt.
    public func estimateRemainingRange(
        atAcceptedSOC soc: AcceptedBatterySOCAnchor,
        acceptedBy validator: BatteryEvidenceStreamValidator,
        policy: AdaptiveBatteryRangePolicy
    ) -> AdaptiveBatteryRangeLiveEstimate? {
        model.estimateRemainingRange(
            atAcceptedSOC: soc,
            acceptedBy: validator,
            previousPresentedRemainingMeters: nil,
            policy: policy
        )
    }
}
