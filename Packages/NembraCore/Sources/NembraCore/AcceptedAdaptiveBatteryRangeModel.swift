import Foundation

public enum AcceptedAdaptiveRangeValidationError: Error, Equatable, Sendable {
    case invalidReceiptOrder
    case acquisitionEpochChanged
}

/// A receipt-bound range-learning window whose construction is unavailable to ordinary app
/// source. The public raw `BatteryRangeLearningWindow` remains a useful pure-model fixture,
/// but it is not the production authority boundary.
///
/// Package-scoped construction intentionally makes the future trusted ride/battery evidence
/// bridge responsible for declaring distance coverage. In the current direct-source app
/// composition there is no generic same-module initializer that can reuse two real SoC
/// anchors with invented distance and silently teach production range.
public struct AcceptedBatteryRangeLearningWindow: Equatable, Sendable {
    public let distanceMeters: Double
    public let distanceCoverage: BatteryRangeDistanceCoverage
    public let transportGapOccurred: Bool
    public let startSOC: AcceptedBatterySOCAnchor
    public let endSOC: AcceptedBatterySOCAnchor

#if SWIFT_PACKAGE
    package init(
        distanceMeters: Double,
        distanceCoverage: BatteryRangeDistanceCoverage,
        transportGapOccurred: Bool,
        startSOC: AcceptedBatterySOCAnchor,
        endSOC: AcceptedBatterySOCAnchor
    ) throws {
        guard startSOC.sourceReceiptIdentity.acquisitionEpoch
                == endSOC.sourceReceiptIdentity.acquisitionEpoch else {
            throw AcceptedAdaptiveRangeValidationError.acquisitionEpochChanged
        }
        guard endSOC.sourceReceiptIdentity.sequenceNumber
                > startSOC.sourceReceiptIdentity.sequenceNumber,
              endSOC.receivedAtUptimeNanoseconds > startSOC.receivedAtUptimeNanoseconds else {
            throw AcceptedAdaptiveRangeValidationError.invalidReceiptOrder
        }

        self.distanceMeters = distanceMeters
        self.distanceCoverage = distanceCoverage
        // An explicit post-gap battery boundary proves continuity was unobserved between the
        // two anchors even if a higher layer accidentally supplies `false` here.
        self.transportGapOccurred = transportGapOccurred
            || endSOC.continuity == .afterUnobservedInterval
        self.startSOC = startSOC
        self.endSOC = endSOC
    }
#endif
}

/// Production authority wrapper around the persistable adaptive-range math model.
///
/// `AdaptiveBatteryRangeModel` intentionally remains a reusable pure algorithm for tests,
/// simulation, offline research, and future migration. This wrapper is the stronger boundary
/// for live product use: ordinary app code cannot import arbitrary raw model state or feed it
/// caller-constructed learning windows. New production presentation should request live range
/// only through a receipt-bound `AcceptedBatterySOCAnchor`.
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
    @discardableResult
    package mutating func ingest(
        _ window: AcceptedBatteryRangeLearningWindow,
        policy: AdaptiveBatteryRangePolicy
    ) -> BatteryRangeLearningResult {
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
            return BatteryRangeLearningResult(
                disposition: .rejected(.numericalOverflow),
                sample: nil,
                confidence: model.confidence(using: policy)
            )
        }

        return model.ingest(rawWindow, policy: policy)
    }
#endif

    public func estimateRemainingRange(
        atAcceptedSOC soc: AcceptedBatterySOCAnchor,
        previousPresentedRemainingMeters: Double? = nil,
        policy: AdaptiveBatteryRangePolicy
    ) -> AdaptiveBatteryRangeLiveEstimate? {
        model.estimateRemainingRange(
            atAcceptedSOC: soc,
            previousPresentedRemainingMeters: previousPresentedRemainingMeters,
            policy: policy
        )
    }
}
