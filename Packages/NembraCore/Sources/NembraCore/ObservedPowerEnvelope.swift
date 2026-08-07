import Foundation

public enum ObservedPowerEnvelopeScopeError: Error, Equatable, Sendable {
    case emptyVehicleIdentityKey
    case emptyConfirmedModeKey
}

/// An opaque calibration scope supplied by the integration layer after it has a
/// legitimate stable scooter identity. NembraCore deliberately does not derive
/// this key from model name, BLE local name, or any other unverified identity.
///
/// `confirmedModeKey` is optional. Supplying one means the caller has already
/// established that the mode identity itself is trustworthy enough to own a
/// separate learned envelope.
public struct ObservedPowerEnvelopeScope: Equatable, Hashable, Sendable {
    public let vehicleIdentityKey: String
    public let confirmedModeKey: String?

    public init(vehicleIdentityKey: String, confirmedModeKey: String? = nil) throws {
        guard !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ObservedPowerEnvelopeScopeError.emptyVehicleIdentityKey
        }
        if let confirmedModeKey {
            guard !confirmedModeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ObservedPowerEnvelopeScopeError.emptyConfirmedModeKey
            }
        }
        self.vehicleIdentityKey = vehicleIdentityKey
        self.confirmedModeKey = confirmedModeKey
    }
}

public enum ObservedPowerEnvelopePolicyError: Error, Equatable, Sendable {
    case invalidWindowCapacity
    case invalidMinimumLearningSampleCount
    case invalidMinimumUpperBandSupportCount
    case invalidUpperPercentile
    case invalidUpperBandFraction
    case invalidHeadroomFraction
    case invalidUpwardHysteresisFraction
}

/// Caller-selected software policy for learning a stable *observed* propulsion
/// gauge scale. No values here claim the motor/controller rated maximum.
public struct ObservedPowerEnvelopePolicy: Equatable, Sendable {
    public let windowCapacity: Int
    public let minimumLearningSampleCount: Int
    public let minimumUpperBandSupportCount: Int
    public let upperPercentile: Double
    public let upperBandFraction: Double
    public let headroomFraction: Double
    public let upwardHysteresisFraction: Double

    public init(
        windowCapacity: Int,
        minimumLearningSampleCount: Int,
        minimumUpperBandSupportCount: Int,
        upperPercentile: Double,
        upperBandFraction: Double,
        headroomFraction: Double,
        upwardHysteresisFraction: Double
    ) throws {
        guard windowCapacity > 0 else { throw ObservedPowerEnvelopePolicyError.invalidWindowCapacity }
        guard minimumLearningSampleCount > 0,
              minimumLearningSampleCount <= windowCapacity else {
            throw ObservedPowerEnvelopePolicyError.invalidMinimumLearningSampleCount
        }
        guard minimumUpperBandSupportCount >= 2,
              minimumUpperBandSupportCount <= minimumLearningSampleCount else {
            throw ObservedPowerEnvelopePolicyError.invalidMinimumUpperBandSupportCount
        }
        guard upperPercentile.isFinite,
              upperPercentile > 0,
              upperPercentile < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidUpperPercentile
        }
        guard upperBandFraction.isFinite,
              upperBandFraction >= 0,
              upperBandFraction < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidUpperBandFraction
        }
        guard headroomFraction.isFinite,
              headroomFraction >= 0,
              headroomFraction < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidHeadroomFraction
        }
        guard upwardHysteresisFraction.isFinite,
              upwardHysteresisFraction >= 0,
              upwardHysteresisFraction < 1 else {
            throw ObservedPowerEnvelopePolicyError.invalidUpwardHysteresisFraction
        }

        self.windowCapacity = windowCapacity
        self.minimumLearningSampleCount = minimumLearningSampleCount
        self.minimumUpperBandSupportCount = minimumUpperBandSupportCount
        self.upperPercentile = upperPercentile
        self.upperBandFraction = upperBandFraction
        self.headroomFraction = headroomFraction
        self.upwardHysteresisFraction = upwardHysteresisFraction
    }
}

/// Controls whether an already accepted authoritative physical observation is
/// allowed to influence learned calibration. `measurementOnly` preserves the
/// measurement for callers but cannot resize the gauge.
///
/// This extra gate is deliberate: low-battery or thermally limited observations
/// must not silently redefine "full observed power" merely because their watts
/// are otherwise valid telemetry.
public enum ObservedPowerEnvelopeLearningEligibility: Equatable, Sendable {
    case measurementOnly
    case eligibleForEnvelopeLearning
}

public enum ObservedPowerEnvelopeRejection: Equatable, Sendable {
    case nonIncreasingObservationTimestamp
    case invalidPowerWatts
}

public struct ObservedPowerEnvelopeCalibration: Equatable, Sendable {
    public let scope: ObservedPowerEnvelopeScope
    /// Robust upper-envelope statistic from qualified accepted observations.
    /// This is not a certified/rated motor or controller maximum.
    public let learnedObservedCeilingWatts: Double
    /// Presentation scale after restrained headroom is applied.
    public let learnedGaugeScaleWatts: Double
    public let learningSampleCount: Int
    public let upperBandSupportCount: Int
}

public enum ObservedPowerEnvelopeRecordResult: Equatable, Sendable {
    case acceptedMeasurementOnly
    case acceptedLearningSample
    case calibrationEstablished(ObservedPowerEnvelopeCalibration)
    case calibrationRaised(ObservedPowerEnvelopeCalibration)
    case rejected(ObservedPowerEnvelopeRejection)
}

/// Learns a stable upward-adapting presentation scale from observations that a
/// higher layer has already qualified as authoritative physical power evidence.
///
/// This type does **not** decode BLE/Tuya data, establish watts semantics, infer
/// throttle position, or decide whether an observation is free from battery or
/// thermal limiting. Callers must keep unverified/synthetic inputs out of the
/// authoritative learning path and may mark accepted values `measurementOnly`.
///
/// Automatic downward adaptation is intentionally absent at the current product
/// evidence maturity. Once a stronger ceiling has been observed, ordinary lower
/// output cannot shrink the scale and masquerade battery/thermal power reduction
/// as a new "full power" baseline. A future downward-recalibration path needs its
/// own explicit evidence policy rather than silent decay.
public struct ObservedPowerEnvelopeLearner: Sendable {
    public let scope: ObservedPowerEnvelopeScope
    public let policy: ObservedPowerEnvelopePolicy

    private var lastObservedUptimeNanoseconds: UInt64?
    private var eligiblePowerWindow: [Double] = []
    private var calibrationStorage: ObservedPowerEnvelopeCalibration?

    public init(scope: ObservedPowerEnvelopeScope, policy: ObservedPowerEnvelopePolicy) {
        self.scope = scope
        self.policy = policy
    }

    public var calibration: ObservedPowerEnvelopeCalibration? {
        calibrationStorage
    }

    @discardableResult
    public mutating func recordQualifiedObservation(
        powerWatts: Double,
        observedAtUptimeNanoseconds: UInt64,
        learningEligibility: ObservedPowerEnvelopeLearningEligibility
    ) -> ObservedPowerEnvelopeRecordResult {
        if let lastObservedUptimeNanoseconds,
           observedAtUptimeNanoseconds <= lastObservedUptimeNanoseconds {
            return .rejected(.nonIncreasingObservationTimestamp)
        }

        // A fresh callback is ordering evidence even if its numeric payload later
        // proves unusable. Advancing chronology prevents an older delayed value
        // from entering after this rejected observation.
        lastObservedUptimeNanoseconds = observedAtUptimeNanoseconds

        guard powerWatts.isFinite, powerWatts >= 0 else {
            return .rejected(.invalidPowerWatts)
        }

        guard learningEligibility == .eligibleForEnvelopeLearning else {
            return .acceptedMeasurementOnly
        }

        eligiblePowerWindow.append(powerWatts)
        if eligiblePowerWindow.count > policy.windowCapacity {
            eligiblePowerWindow.removeFirst(eligiblePowerWindow.count - policy.windowCapacity)
        }

        guard let candidate = calibrationCandidate() else {
            return .acceptedLearningSample
        }

        guard let existing = calibrationStorage else {
            calibrationStorage = candidate
            return .calibrationEstablished(candidate)
        }

        let requiredScale = existing.learnedGaugeScaleWatts * (1 + policy.upwardHysteresisFraction)
        guard requiredScale.isFinite,
              candidate.learnedGaugeScaleWatts > requiredScale else {
            return .acceptedLearningSample
        }

        calibrationStorage = candidate
        return .calibrationRaised(candidate)
    }

    /// Render-only normalization helper. The raw measured watts remain the
    /// authoritative numeric value; this fraction is only gauge presentation.
    public func normalizedPresentationPosition(forAcceptedPowerWatts powerWatts: Double) -> Double? {
        guard powerWatts.isFinite, powerWatts >= 0,
              let scale = calibrationStorage?.learnedGaugeScaleWatts,
              scale.isFinite, scale > 0 else {
            return nil
        }
        return min(max(powerWatts / scale, 0), 1)
    }

    private func calibrationCandidate() -> ObservedPowerEnvelopeCalibration? {
        guard eligiblePowerWindow.count >= policy.minimumLearningSampleCount else {
            return nil
        }

        let sorted = eligiblePowerWindow.sorted()
        let rawRank = Double(sorted.count - 1) * policy.upperPercentile
        let percentileIndex = Int(rawRank.rounded(.down))
        let observedCeiling = sorted[percentileIndex]
        guard observedCeiling.isFinite, observedCeiling > 0 else { return nil }

        let lowerSupportBound = observedCeiling * (1 - policy.upperBandFraction)
        guard lowerSupportBound.isFinite, lowerSupportBound >= 0 else { return nil }

        let supportCount = sorted.count { $0 >= lowerSupportBound }
        guard supportCount >= policy.minimumUpperBandSupportCount else { return nil }

        let scale = observedCeiling * (1 + policy.headroomFraction)
        guard scale.isFinite, scale > 0 else { return nil }

        return ObservedPowerEnvelopeCalibration(
            scope: scope,
            learnedObservedCeilingWatts: observedCeiling,
            learnedGaugeScaleWatts: scale,
            learningSampleCount: eligiblePowerWindow.count,
            upperBandSupportCount: supportCount
        )
    }
}
