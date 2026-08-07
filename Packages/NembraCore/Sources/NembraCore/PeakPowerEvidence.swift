import Foundation

/// Describes only whether this accumulator recorded a loss in the selected
/// power-observation stream. It does not claim continuous sampling between
/// accepted callbacks or that the observed maximum equals a perfect physical
/// continuous-time maximum.
public enum PeakPowerObservationContinuity: String, Codable, Equatable, Sendable {
    case noRecordedSelectedSourceEvidenceLoss
    case partialSelectedSourceEvidence
}

public enum PeakPowerInterruption: Equatable, Sendable {
    case vehicleConnectionLost
    case applicationLifecycleInterrupted
    case sourceUnavailable
    case observationStreamRestarted
}

public enum PeakPowerRecordRejection: Equatable, Sendable {
    case scopeMismatch(
        expected: ObservedPowerEnvelopeScope,
        actual: ObservedPowerEnvelopeScope
    )
    case evidenceAuthorityMismatch(
        expected: ObservedPowerEnvelopeEvidenceAuthority,
        actual: ObservedPowerEnvelopeEvidenceAuthority
    )
    case nonIncreasingObservationSequence
    case nonIncreasingObservationTimestamp
    case invalidPowerWatts
}

/// One nonnegative accepted propulsion-power observation eligible to become a
/// session peak. Signed negative observations may still be legitimate accepted
/// transport evidence (for example, if future verified semantics expose regen),
/// but they never become a positive propulsion peak here.
public struct PeakPowerMeasurement: Equatable, Sendable {
    public let scope: ObservedPowerEnvelopeScope
    public let powerWatts: Double
    public let receiptSequenceNumber: UInt64
    public let observedAtUptimeNanoseconds: UInt64
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority

    fileprivate init(observation: ObservedPowerEnvelopeObservation) {
        self.scope = observation.scope
        self.powerWatts = observation.powerWatts
        self.receiptSequenceNumber = observation.receiptSequenceNumber
        self.observedAtUptimeNanoseconds = observation.observedAtUptimeNanoseconds
        self.evidenceAuthority = observation.evidenceAuthority
    }
}

public enum PeakPowerRecordResult: Equatable, Sendable {
    case peakUpdated(PeakPowerMeasurement)
    case acceptedWithoutPeakChange
    case rejected(PeakPowerRecordRejection)
}

/// Highest accepted nonnegative propulsion-power observation for one exact
/// vehicle/mode scope and one evidence authority.
///
/// `peak` means the highest accepted *measurement* Nembra actually observed in
/// this scoped stream. It is not a motor/controller rating, not the learned
/// observed-power envelope, not a display-interpolated frame, and not proof of
/// throttle position. Finite negative observations remain accepted stream
/// evidence but are intentionally excluded from the positive propulsion peak.
public struct PeakPowerEvidence: Equatable, Sendable {
    public let scope: ObservedPowerEnvelopeScope
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    public let peak: PeakPowerMeasurement
    /// Every finite, correctly scoped and ordered power observation, including
    /// signed negative values that are not candidates for positive peak power.
    public let acceptedMeasurementCount: Int
    /// Accepted nonnegative observations that were eligible to compete for peak.
    public let peakCandidateMeasurementCount: Int
    public let qualityRejectedMeasurementCount: Int
    public let knownInterruptionCount: Int
    public let continuity: PeakPowerObservationContinuity
}

public enum PeakPowerEvidenceAccumulatorError: Error, Equatable, Sendable {
    case scopeAuthorityMismatch(
        expected: ObservedPowerEnvelopeScopeAuthority,
        actual: ObservedPowerEnvelopeScopeAuthority
    )
}

/// Session-local accumulator that consumes the same immutable accepted power
/// observation shape used by observed-envelope learning while preserving an
/// independent peak semantic.
///
/// Envelope learning eligibility is deliberately ignored here. A legitimate
/// measurement may be unsuitable for calibration because of battery/thermal
/// context while still remaining a valid observed peak-power measurement.
public struct PeakPowerEvidenceAccumulator: Sendable {
    public let scope: ObservedPowerEnvelopeScope
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority

    private var peakStorage: PeakPowerMeasurement?
    /// Replay protection belongs to the selected immutable source stream, not to
    /// the current product-facing peak accumulation window. These high-water
    /// marks therefore survive `reset()` unless a future source-generation
    /// identity provides a mechanically provable new chronology domain.
    private var lastSeenReceiptSequenceNumber: UInt64?
    private var lastObservedUptimeNanoseconds: UInt64?
    private var acceptedMeasurementCount = 0
    private var peakCandidateMeasurementCount = 0
    private var qualityRejectedMeasurementCount = 0
    private var knownInterruptionCount = 0

    private init(
        scope: ObservedPowerEnvelopeScope,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) {
        self.scope = scope
        self.evidenceAuthority = evidenceAuthority
    }

    /// Public Simulator construction is explicit QA evidence only.
    public static func simulatorQA(scope: ObservedPowerEnvelopeScope) throws -> Self {
        guard scope.identityAuthority == .simulatorQA else {
            throw PeakPowerEvidenceAccumulatorError.scopeAuthorityMismatch(
                expected: .simulatorQA,
                actual: scope.identityAuthority
            )
        }
        return Self(scope: scope, evidenceAuthority: .simulatorQA)
    }

#if SWIFT_PACKAGE
    /// Verified physical peak accumulation is package-owned so unrelated UI/app
    /// code cannot manufacture physical authority from arbitrary strings.
    package static func verifiedVehicleMeasurements(
        scope: ObservedPowerEnvelopeScope
    ) throws -> Self {
        guard scope.identityAuthority == .verifiedVehicleIdentity else {
            throw PeakPowerEvidenceAccumulatorError.scopeAuthorityMismatch(
                expected: .verifiedVehicleIdentity,
                actual: scope.identityAuthority
            )
        }
        return Self(scope: scope, evidenceAuthority: .verifiedVehicleMeasurement)
    }
#else
    fileprivate static func verifiedVehicleMeasurements(
        scope: ObservedPowerEnvelopeScope
    ) throws -> Self {
        guard scope.identityAuthority == .verifiedVehicleIdentity else {
            throw PeakPowerEvidenceAccumulatorError.scopeAuthorityMismatch(
                expected: .verifiedVehicleIdentity,
                actual: scope.identityAuthority
            )
        }
        return Self(scope: scope, evidenceAuthority: .verifiedVehicleMeasurement)
    }
#endif

    @discardableResult
    public mutating func record(
        _ observation: ObservedPowerEnvelopeObservation
    ) -> PeakPowerRecordResult {
        guard observation.scope == scope else {
            return .rejected(.scopeMismatch(expected: scope, actual: observation.scope))
        }
        guard observation.evidenceAuthority == evidenceAuthority else {
            return .rejected(.evidenceAuthorityMismatch(
                expected: evidenceAuthority,
                actual: observation.evidenceAuthority
            ))
        }

        if let lastSeenReceiptSequenceNumber,
           observation.receiptSequenceNumber <= lastSeenReceiptSequenceNumber {
            qualityRejectedMeasurementCount += 1
            return .rejected(.nonIncreasingObservationSequence)
        }

        // Once a genuinely newer immutable callback identity is observed for the
        // selected stream, consume it before checking uptime/value quality. This
        // prevents a rejected callback from being rewritten later with cleaner
        // metadata and prevents delayed lower sequences from re-entering.
        lastSeenReceiptSequenceNumber = observation.receiptSequenceNumber

        if let lastObservedUptimeNanoseconds,
           observation.observedAtUptimeNanoseconds < lastObservedUptimeNanoseconds {
            qualityRejectedMeasurementCount += 1
            return .rejected(.nonIncreasingObservationTimestamp)
        }
        lastObservedUptimeNanoseconds = observation.observedAtUptimeNanoseconds

        guard observation.powerWatts.isFinite else {
            qualityRejectedMeasurementCount += 1
            return .rejected(.invalidPowerWatts)
        }

        acceptedMeasurementCount += 1

        // Negative values remain legitimate accepted stream evidence but are not
        // relabeled as positive propulsion output. Regen presentation/peak needs
        // separately verified signed semantics before it can exist as a product.
        guard observation.powerWatts >= 0 else {
            return .acceptedWithoutPeakChange
        }

        peakCandidateMeasurementCount += 1
        let measurement = PeakPowerMeasurement(observation: observation)
        if peakStorage.map({ measurement.powerWatts > $0.powerWatts }) ?? true {
            peakStorage = measurement
            return .peakUpdated(measurement)
        }

        return .acceptedWithoutPeakChange
    }

    /// Marks a known evidence break without discarding an already observed peak.
    /// The value remains a real accepted observation, while continuity becomes
    /// explicitly partial for the rest of this accumulation epoch.
    public mutating func recordInterruption(_ interruption: PeakPowerInterruption) {
        _ = interruption
        knownInterruptionCount += 1
    }

    public var evidence: PeakPowerEvidence? {
        guard let peak = peakStorage else { return nil }

        let continuity: PeakPowerObservationContinuity =
            (qualityRejectedMeasurementCount == 0 && knownInterruptionCount == 0)
                ? .noRecordedSelectedSourceEvidenceLoss
                : .partialSelectedSourceEvidence

        return PeakPowerEvidence(
            scope: scope,
            evidenceAuthority: evidenceAuthority,
            peak: peak,
            acceptedMeasurementCount: acceptedMeasurementCount,
            peakCandidateMeasurementCount: peakCandidateMeasurementCount,
            qualityRejectedMeasurementCount: qualityRejectedMeasurementCount,
            knownInterruptionCount: knownInterruptionCount,
            continuity: continuity
        )
    }

    /// Clears only the product-facing accumulation window. Replay high-water
    /// marks intentionally survive: `ObservedPowerEnvelopeObservation` does not
    /// yet carry an acquisition/source generation that could prove a restarted
    /// sequence belongs to a genuinely new immutable callback stream. A delayed
    /// pre-reset callback must therefore remain unable to re-enter after reset.
    public mutating func reset() {
        peakStorage = nil
        acceptedMeasurementCount = 0
        peakCandidateMeasurementCount = 0
        qualityRejectedMeasurementCount = 0
        knownInterruptionCount = 0
    }
}
