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
/// The type is deliberately not Codable. Process-local receipt identity and live-currentness
/// must never survive persistence/relaunch by serialization.
public struct AcceptedBatterySOCAnchor: Equatable, Sendable {
    public let percentage: Double
    public let sourceReceiptIdentity: BatteryEvidenceReceiptIdentity
    public let receivedAtUptimeNanoseconds: UInt64
    public let continuity: BatteryEvidenceContinuity

    private init(
        percentage: Double,
        sourceReceiptIdentity: BatteryEvidenceReceiptIdentity,
        receivedAtUptimeNanoseconds: UInt64,
        continuity: BatteryEvidenceContinuity
    ) {
        self.percentage = percentage
        self.sourceReceiptIdentity = sourceReceiptIdentity
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuity = continuity
    }

    /// Projects only a currently accepted verified vehicle SoC observation into range input.
    ///
    /// `BatteryEvidenceStreamValidator.accept(_:)` remains the chronology/continuity authority.
    /// This projection does not accept an older once-valid receipt after a newer callback, and
    /// it fails while a continuity boundary is pending after a disconnect/unobserved interval.
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

        return Self(
            percentage: percentage,
            sourceReceiptIdentity: receiptIdentity,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds,
            continuity: observation.continuity
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
