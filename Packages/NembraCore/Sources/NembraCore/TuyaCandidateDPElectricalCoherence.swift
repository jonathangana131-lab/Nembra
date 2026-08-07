import Foundation

/// Caller-assigned roles for one narrow electrical relationship hypothesis.
/// Roles describe stock-app anchors chosen by a researcher; they never assign
/// AOVOPRO ES80 DP semantics to a candidate.
public enum TuyaCandidateDPElectricalRole: String, Equatable, Hashable, Sendable {
    case voltage
    case current
    case power
}

public enum TuyaCandidateDPElectricalCoherenceError: Error, Equatable, Sendable {
    case emptyEvidenceContextIdentifier
    case evidenceContextMismatch(role: TuyaCandidateDPElectricalRole)
    case invalidMaximumAnchorCount
    case invalidAbsolutePowerTolerance
    case invalidRelativePowerTolerance
    case anchorCountExceedsPolicy(maximum: Int)
    case invalidMarkerIndex(role: TuyaCandidateDPElectricalRole, index: Int)
    case duplicateAnchor(anchorIndex: Int, previousAnchorIndex: Int)
    case reusedMarkerIndex(role: TuyaCandidateDPElectricalRole, index: Int)
    case streamIdentityMismatch(role: TuyaCandidateDPElectricalRole)
    case continuityGenerationMismatch(role: TuyaCandidateDPElectricalRole)
    case dataLengthWidthMismatch(role: TuyaCandidateDPElectricalRole)
    case invalidHypothesisIdentifier(role: TuyaCandidateDPElectricalRole)
    case missingHypothesis(role: TuyaCandidateDPElectricalRole, identifier: String)
    case ambiguousHypothesisIdentifier(role: TuyaCandidateDPElectricalRole, identifier: String)
    case duplicateHypothesisSample(role: TuyaCandidateDPElectricalRole, markerIndex: Int)
}

/// Caller-attested identity for one capture/analysis context whose monotonic
/// receipt times are legitimately comparable. The identifier should originate
/// from retained capture metadata. Equality prevents accidental cross-session
/// mixing; it is not authentication or physical protocol proof.
public struct TuyaCandidateDPElectricalEvidenceContextIdentity: Equatable, Hashable, Sendable {
    public let identifier: String

    public init(identifier: String) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPElectricalCoherenceError.emptyEvidenceContextIdentifier
        }
        self.identifier = identifier
    }
}

/// Explicit per-role association between each numeric report and its capture
/// context. All identities must match before uptime-based span math occurs.
public struct TuyaCandidateDPElectricalEvidenceContextBindings: Equatable, Sendable {
    public let voltage: TuyaCandidateDPElectricalEvidenceContextIdentity
    public let current: TuyaCandidateDPElectricalEvidenceContextIdentity
    public let power: TuyaCandidateDPElectricalEvidenceContextIdentity

    public init(
        voltage: TuyaCandidateDPElectricalEvidenceContextIdentity,
        current: TuyaCandidateDPElectricalEvidenceContextIdentity,
        power: TuyaCandidateDPElectricalEvidenceContextIdentity
    ) {
        self.voltage = voltage
        self.current = current
        self.power = power
    }
}

/// One explicit three-field stock-app anchor group. Marker indices are local to
/// the three caller-supplied numeric-hypothesis reports. Reusing one marker in a
/// role across anchors is rejected so support cannot be inflated.
public struct TuyaCandidateDPElectricalAnchor: Equatable, Hashable, Sendable {
    public let voltageMarkerIndex: Int
    public let currentMarkerIndex: Int
    public let powerMarkerIndex: Int

    public init(
        voltageMarkerIndex: Int,
        currentMarkerIndex: Int,
        powerMarkerIndex: Int
    ) throws {
        guard voltageMarkerIndex >= 0 else {
            throw TuyaCandidateDPElectricalCoherenceError.invalidMarkerIndex(
                role: .voltage,
                index: voltageMarkerIndex
            )
        }
        guard currentMarkerIndex >= 0 else {
            throw TuyaCandidateDPElectricalCoherenceError.invalidMarkerIndex(
                role: .current,
                index: currentMarkerIndex
            )
        }
        guard powerMarkerIndex >= 0 else {
            throw TuyaCandidateDPElectricalCoherenceError.invalidMarkerIndex(
                role: .power,
                index: powerMarkerIndex
            )
        }
        self.voltageMarkerIndex = voltageMarkerIndex
        self.currentMarkerIndex = currentMarkerIndex
        self.powerMarkerIndex = powerMarkerIndex
    }
}

/// Caller-owned bounds for the explicit research relationship
/// `power = voltage × current`. Values are interpreted only in the caller's
/// chosen display-space units after the parent numeric transforms. There are no
/// ES80 timing or tolerance defaults here.
public struct TuyaCandidateDPElectricalCoherencePolicy: Equatable, Sendable {
    public let maximumAnchorCount: Int
    public let maximumEvidenceSpanNanoseconds: UInt64
    public let absolutePowerTolerance: Double
    public let relativePowerTolerance: Double

    public init(
        maximumAnchorCount: Int,
        maximumEvidenceSpanNanoseconds: UInt64,
        absolutePowerTolerance: Double,
        relativePowerTolerance: Double
    ) throws {
        guard maximumAnchorCount > 0 else {
            throw TuyaCandidateDPElectricalCoherenceError.invalidMaximumAnchorCount
        }
        guard absolutePowerTolerance.isFinite, absolutePowerTolerance >= 0 else {
            throw TuyaCandidateDPElectricalCoherenceError.invalidAbsolutePowerTolerance
        }
        guard relativePowerTolerance.isFinite, relativePowerTolerance >= 0 else {
            throw TuyaCandidateDPElectricalCoherenceError.invalidRelativePowerTolerance
        }
        self.maximumAnchorCount = maximumAnchorCount
        self.maximumEvidenceSpanNanoseconds = maximumEvidenceSpanNanoseconds
        self.absolutePowerTolerance = absolutePowerTolerance
        self.relativePowerTolerance = relativePowerTolerance
    }
}

/// Shared provenance scope required before three numeric series may be compared.
/// Field labels remain exact stock-app/research labels and are never parsed or
/// promoted into DP meaning.
public struct TuyaCandidateDPElectricalCoherenceScope: Equatable, Sendable {
    public let evidenceContextIdentity: TuyaCandidateDPElectricalEvidenceContextIdentity
    public let streamIdentity: TuyaCandidateValueStreamIdentity
    public let continuityGeneration: UInt64
    public let dataLengthWidth: TuyaCandidateDPDataLengthWidth
    public let voltageFieldLabel: String
    public let currentFieldLabel: String
    public let powerFieldLabel: String

    fileprivate init(
        evidenceContextIdentity: TuyaCandidateDPElectricalEvidenceContextIdentity,
        voltage: TuyaCandidateDPMarkerCorrelationScope,
        current: TuyaCandidateDPMarkerCorrelationScope,
        power: TuyaCandidateDPMarkerCorrelationScope
    ) {
        self.evidenceContextIdentity = evidenceContextIdentity
        streamIdentity = voltage.streamIdentity
        continuityGeneration = voltage.continuityGeneration
        dataLengthWidth = voltage.dataLengthWidth
        voltageFieldLabel = voltage.fieldLabel
        currentFieldLabel = current.fieldLabel
        powerFieldLabel = power.fieldLabel
    }
}

/// Exact candidate + transform selected by the caller for one research role.
///
/// The complete parent report and exact selected evidence are retained so a
/// downstream audit can recover parent unused/ambiguous/shared exclusions,
/// nonnumeric/transformation counts, complete caller references, and every raw
/// selected sample without reconstructing provenance from child summary flags.
/// Convenience fields are copied only for stable direct access.
public struct TuyaCandidateDPElectricalSeriesSelection: Equatable, Sendable {
    public let role: TuyaCandidateDPElectricalRole
    public let fieldLabel: String
    public let candidateIndex: Int
    public let candidate: TuyaCandidateDPCorrelationCandidate
    public let sourceReport: TuyaCandidateDPNumericHypothesisReport
    public let selectedEvidence: TuyaCandidateDPNumericHypothesisEvidence
    public let hypothesis: TuyaCandidateDPNumericTransformHypothesis
    public let numericReferences: [TuyaCandidateDPNumericReference]
    public let numericAbsoluteTolerance: Double
    public let evaluableSampleCount: Int

    fileprivate init(
        role: TuyaCandidateDPElectricalRole,
        report: TuyaCandidateDPNumericHypothesisReport,
        evidence: TuyaCandidateDPNumericHypothesisEvidence
    ) {
        self.role = role
        fieldLabel = report.correlationScope.fieldLabel
        candidateIndex = report.candidateIndex
        candidate = report.candidate
        sourceReport = report
        selectedEvidence = evidence
        hypothesis = evidence.hypothesis
        numericReferences = report.numericReferences
        numericAbsoluteTolerance = report.absoluteTolerance
        evaluableSampleCount = evidence.samples.count
    }
}

public enum TuyaCandidateDPElectricalAnchorRejectionReason: Equatable, Sendable {
    case missingNumericSample(role: TuyaCandidateDPElectricalRole, markerIndex: Int)
    case evidenceSpanExceedsPolicy(actual: UInt64, maximum: UInt64)
    case nonFiniteReferenceRelationship
    case nonFiniteCandidateRelationship
}

/// Explicitly rejected anchor. Missing, too-distant, and overflowing evidence
/// remains visible instead of being silently dropped from support counts.
public struct TuyaCandidateDPElectricalRejectedAnchor: Equatable, Sendable {
    public let anchorIndex: Int
    public let anchor: TuyaCandidateDPElectricalAnchor
    public let reason: TuyaCandidateDPElectricalAnchorRejectionReason

    fileprivate init(
        anchorIndex: Int,
        anchor: TuyaCandidateDPElectricalAnchor,
        reason: TuyaCandidateDPElectricalAnchorRejectionReason
    ) {
        self.anchorIndex = anchorIndex
        self.anchor = anchor
        self.reason = reason
    }
}

/// One accepted, time-bounded comparison. Both independently entered stock-app
/// numeric references and transformed raw-candidate values are checked against
/// the same explicit `power = voltage × current` relationship.
///
/// Joint support requires:
/// 1. stock-app references themselves are relationship-coherent;
/// 2. all three parent numeric transforms individually match their anchors;
/// 3. transformed candidate values are relationship-coherent.
///
/// This is research prioritization evidence, never protocol confidence.
public struct TuyaCandidateDPElectricalAnchorEvaluation: Equatable, Sendable {
    public let anchorIndex: Int
    public let anchor: TuyaCandidateDPElectricalAnchor
    public let voltageSample: TuyaCandidateDPNumericHypothesisSample
    public let currentSample: TuyaCandidateDPNumericHypothesisSample
    public let powerSample: TuyaCandidateDPNumericHypothesisSample
    public let evidenceSpanNanoseconds: UInt64

    public let referencePredictedPower: Double
    public let referenceAbsolutePowerError: Double
    public let referenceRelativePowerError: Double
    public let referenceAllowedPowerError: Double
    public let referenceRelationshipWithinTolerance: Bool

    public let candidatePredictedPower: Double
    public let candidateAbsolutePowerError: Double
    public let candidateRelativePowerError: Double
    public let candidateAllowedPowerError: Double
    public let candidateRelationshipWithinTolerance: Bool

    public let allNumericHypothesesMatchReferences: Bool
    public let supportsJointHypothesis: Bool

    fileprivate init(
        anchorIndex: Int,
        anchor: TuyaCandidateDPElectricalAnchor,
        voltageSample: TuyaCandidateDPNumericHypothesisSample,
        currentSample: TuyaCandidateDPNumericHypothesisSample,
        powerSample: TuyaCandidateDPNumericHypothesisSample,
        evidenceSpanNanoseconds: UInt64,
        reference: RelationshipMetrics,
        candidate: RelationshipMetrics
    ) {
        self.anchorIndex = anchorIndex
        self.anchor = anchor
        self.voltageSample = voltageSample
        self.currentSample = currentSample
        self.powerSample = powerSample
        self.evidenceSpanNanoseconds = evidenceSpanNanoseconds

        referencePredictedPower = reference.predictedPower
        referenceAbsolutePowerError = reference.absoluteError
        referenceRelativePowerError = reference.relativeError
        referenceAllowedPowerError = reference.allowedError
        referenceRelationshipWithinTolerance = reference.isWithinTolerance

        candidatePredictedPower = candidate.predictedPower
        candidateAbsolutePowerError = candidate.absoluteError
        candidateRelativePowerError = candidate.relativeError
        candidateAllowedPowerError = candidate.allowedError
        candidateRelationshipWithinTolerance = candidate.isWithinTolerance

        allNumericHypothesesMatchReferences =
            voltageSample.isWithinTolerance
            && currentSample.isWithinTolerance
            && powerSample.isWithinTolerance
        supportsJointHypothesis =
            reference.isWithinTolerance
            && allNumericHypothesesMatchReferences
            && candidate.isWithinTolerance
    }
}

/// Descriptive result for one explicit triplet of DP candidates/transforms.
/// Counts are not confidence scores. Exact caller policy and requested anchors
/// are retained so the report is self-auditing rather than outcome-only.
public struct TuyaCandidateDPElectricalCoherenceReport: Equatable, Sendable {
    public let scope: TuyaCandidateDPElectricalCoherenceScope
    public let policy: TuyaCandidateDPElectricalCoherencePolicy
    public let requestedAnchors: [TuyaCandidateDPElectricalAnchor]
    public let voltageSelection: TuyaCandidateDPElectricalSeriesSelection
    public let currentSelection: TuyaCandidateDPElectricalSeriesSelection
    public let powerSelection: TuyaCandidateDPElectricalSeriesSelection
    public let requestedAnchorCount: Int
    public let evaluations: [TuyaCandidateDPElectricalAnchorEvaluation]
    public let rejectedAnchors: [TuyaCandidateDPElectricalRejectedAnchor]
    public let referenceRelationshipMatchedCount: Int
    public let candidateRelationshipMatchedCount: Int
    public let allNumericHypothesesMatchedCount: Int
    public let jointSupportCount: Int
    public let meanReferenceAbsolutePowerError: Double?
    public let meanCandidateAbsolutePowerError: Double?
    public let maximumCandidateAbsolutePowerError: Double?

    fileprivate init(
        scope: TuyaCandidateDPElectricalCoherenceScope,
        policy: TuyaCandidateDPElectricalCoherencePolicy,
        requestedAnchors: [TuyaCandidateDPElectricalAnchor],
        voltageSelection: TuyaCandidateDPElectricalSeriesSelection,
        currentSelection: TuyaCandidateDPElectricalSeriesSelection,
        powerSelection: TuyaCandidateDPElectricalSeriesSelection,
        evaluations: [TuyaCandidateDPElectricalAnchorEvaluation],
        rejectedAnchors: [TuyaCandidateDPElectricalRejectedAnchor]
    ) {
        self.scope = scope
        self.policy = policy
        self.requestedAnchors = requestedAnchors
        self.voltageSelection = voltageSelection
        self.currentSelection = currentSelection
        self.powerSelection = powerSelection
        requestedAnchorCount = requestedAnchors.count
        self.evaluations = evaluations
        self.rejectedAnchors = rejectedAnchors

        referenceRelationshipMatchedCount = evaluations.reduce(into: 0) { count, evaluation in
            if evaluation.referenceRelationshipWithinTolerance { count += 1 }
        }
        candidateRelationshipMatchedCount = evaluations.reduce(into: 0) { count, evaluation in
            if evaluation.candidateRelationshipWithinTolerance { count += 1 }
        }
        allNumericHypothesesMatchedCount = evaluations.reduce(into: 0) { count, evaluation in
            if evaluation.allNumericHypothesesMatchReferences { count += 1 }
        }
        jointSupportCount = evaluations.reduce(into: 0) { count, evaluation in
            if evaluation.supportsJointHypothesis { count += 1 }
        }

        meanReferenceAbsolutePowerError = Self.stableMean(
            evaluations.map(\.referenceAbsolutePowerError)
        )
        meanCandidateAbsolutePowerError = Self.stableMean(
            evaluations.map(\.candidateAbsolutePowerError)
        )
        maximumCandidateAbsolutePowerError =
            evaluations.map(\.candidateAbsolutePowerError).max()
    }

    /// Compute the mean of finite nonnegative errors without forming a raw sum
    /// or a sum of rounded `value / count` terms. The online update stays inside
    /// the convex hull of the observed errors, so even three
    /// `Double.greatestFiniteMagnitude` values retain that finite mean.
    private static func stableMean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var mean = 0.0
        for (index, value) in values.enumerated() {
            let divisor = Double(index + 1)
            mean += (value - mean) / divisor
            guard mean.isFinite else { return nil }
        }
        return mean
    }
}

public enum TuyaCandidateDPElectricalCoherenceEvaluator {
    /// Evaluates one caller-selected voltage/current/power candidate triplet.
    ///
    /// Before uptime-based comparison, the caller must bind each report to the
    /// same retained capture/clock context. Reports must also share the exact
    /// GATT value stream, continuity generation, and DP length-width hypothesis.
    /// No candidate search or semantic promotion occurs here.
    public static func evaluate(
        voltageReport: TuyaCandidateDPNumericHypothesisReport,
        voltageHypothesisIdentifier: String,
        currentReport: TuyaCandidateDPNumericHypothesisReport,
        currentHypothesisIdentifier: String,
        powerReport: TuyaCandidateDPNumericHypothesisReport,
        powerHypothesisIdentifier: String,
        evidenceContexts: TuyaCandidateDPElectricalEvidenceContextBindings,
        anchors: [TuyaCandidateDPElectricalAnchor],
        policy: TuyaCandidateDPElectricalCoherencePolicy
    ) throws -> TuyaCandidateDPElectricalCoherenceReport {
        guard anchors.count <= policy.maximumAnchorCount else {
            throw TuyaCandidateDPElectricalCoherenceError.anchorCountExceedsPolicy(
                maximum: policy.maximumAnchorCount
            )
        }

        try validateEvidenceContexts(evidenceContexts)
        try validateScope(
            voltage: voltageReport.correlationScope,
            current: currentReport.correlationScope,
            power: powerReport.correlationScope
        )
        try validateAnchors(anchors)

        let voltageEvidence = try selectedEvidence(
            in: voltageReport,
            identifier: voltageHypothesisIdentifier,
            role: .voltage
        )
        let currentEvidence = try selectedEvidence(
            in: currentReport,
            identifier: currentHypothesisIdentifier,
            role: .current
        )
        let powerEvidence = try selectedEvidence(
            in: powerReport,
            identifier: powerHypothesisIdentifier,
            role: .power
        )

        let voltageSamples = try samplesByMarker(voltageEvidence, role: .voltage)
        let currentSamples = try samplesByMarker(currentEvidence, role: .current)
        let powerSamples = try samplesByMarker(powerEvidence, role: .power)

        var evaluations: [TuyaCandidateDPElectricalAnchorEvaluation] = []
        var rejections: [TuyaCandidateDPElectricalRejectedAnchor] = []
        evaluations.reserveCapacity(anchors.count)
        rejections.reserveCapacity(anchors.count)

        for (anchorIndex, anchor) in anchors.enumerated() {
            guard let voltageSample = voltageSamples[anchor.voltageMarkerIndex] else {
                rejections.append(
                    TuyaCandidateDPElectricalRejectedAnchor(
                        anchorIndex: anchorIndex,
                        anchor: anchor,
                        reason: .missingNumericSample(
                            role: .voltage,
                            markerIndex: anchor.voltageMarkerIndex
                        )
                    )
                )
                continue
            }
            guard let currentSample = currentSamples[anchor.currentMarkerIndex] else {
                rejections.append(
                    TuyaCandidateDPElectricalRejectedAnchor(
                        anchorIndex: anchorIndex,
                        anchor: anchor,
                        reason: .missingNumericSample(
                            role: .current,
                            markerIndex: anchor.currentMarkerIndex
                        )
                    )
                )
                continue
            }
            guard let powerSample = powerSamples[anchor.powerMarkerIndex] else {
                rejections.append(
                    TuyaCandidateDPElectricalRejectedAnchor(
                        anchorIndex: anchorIndex,
                        anchor: anchor,
                        reason: .missingNumericSample(
                            role: .power,
                            markerIndex: anchor.powerMarkerIndex
                        )
                    )
                )
                continue
            }

            let span = evidenceSpan(
                voltage: voltageSample,
                current: currentSample,
                power: powerSample
            )
            guard span <= policy.maximumEvidenceSpanNanoseconds else {
                rejections.append(
                    TuyaCandidateDPElectricalRejectedAnchor(
                        anchorIndex: anchorIndex,
                        anchor: anchor,
                        reason: .evidenceSpanExceedsPolicy(
                            actual: span,
                            maximum: policy.maximumEvidenceSpanNanoseconds
                        )
                    )
                )
                continue
            }

            guard let reference = relationshipMetrics(
                voltage: voltageSample.numericReferenceValue,
                current: currentSample.numericReferenceValue,
                power: powerSample.numericReferenceValue,
                policy: policy
            ) else {
                rejections.append(
                    TuyaCandidateDPElectricalRejectedAnchor(
                        anchorIndex: anchorIndex,
                        anchor: anchor,
                        reason: .nonFiniteReferenceRelationship
                    )
                )
                continue
            }

            guard let candidate = relationshipMetrics(
                voltage: voltageSample.transformedCandidateValue,
                current: currentSample.transformedCandidateValue,
                power: powerSample.transformedCandidateValue,
                policy: policy
            ) else {
                rejections.append(
                    TuyaCandidateDPElectricalRejectedAnchor(
                        anchorIndex: anchorIndex,
                        anchor: anchor,
                        reason: .nonFiniteCandidateRelationship
                    )
                )
                continue
            }

            evaluations.append(
                TuyaCandidateDPElectricalAnchorEvaluation(
                    anchorIndex: anchorIndex,
                    anchor: anchor,
                    voltageSample: voltageSample,
                    currentSample: currentSample,
                    powerSample: powerSample,
                    evidenceSpanNanoseconds: span,
                    reference: reference,
                    candidate: candidate
                )
            )
        }

        return TuyaCandidateDPElectricalCoherenceReport(
            scope: TuyaCandidateDPElectricalCoherenceScope(
                evidenceContextIdentity: evidenceContexts.voltage,
                voltage: voltageReport.correlationScope,
                current: currentReport.correlationScope,
                power: powerReport.correlationScope
            ),
            policy: policy,
            requestedAnchors: anchors,
            voltageSelection: TuyaCandidateDPElectricalSeriesSelection(
                role: .voltage,
                report: voltageReport,
                evidence: voltageEvidence
            ),
            currentSelection: TuyaCandidateDPElectricalSeriesSelection(
                role: .current,
                report: currentReport,
                evidence: currentEvidence
            ),
            powerSelection: TuyaCandidateDPElectricalSeriesSelection(
                role: .power,
                report: powerReport,
                evidence: powerEvidence
            ),
            evaluations: evaluations,
            rejectedAnchors: rejections
        )
    }

    private static func validateEvidenceContexts(
        _ contexts: TuyaCandidateDPElectricalEvidenceContextBindings
    ) throws {
        guard contexts.current == contexts.voltage else {
            throw TuyaCandidateDPElectricalCoherenceError.evidenceContextMismatch(role: .current)
        }
        guard contexts.power == contexts.voltage else {
            throw TuyaCandidateDPElectricalCoherenceError.evidenceContextMismatch(role: .power)
        }
    }

    private static func validateScope(
        voltage: TuyaCandidateDPMarkerCorrelationScope,
        current: TuyaCandidateDPMarkerCorrelationScope,
        power: TuyaCandidateDPMarkerCorrelationScope
    ) throws {
        for (role, scope) in [
            (TuyaCandidateDPElectricalRole.current, current),
            (TuyaCandidateDPElectricalRole.power, power)
        ] {
            guard scope.streamIdentity == voltage.streamIdentity else {
                throw TuyaCandidateDPElectricalCoherenceError.streamIdentityMismatch(role: role)
            }
            guard scope.continuityGeneration == voltage.continuityGeneration else {
                throw TuyaCandidateDPElectricalCoherenceError.continuityGenerationMismatch(role: role)
            }
            guard scope.dataLengthWidth == voltage.dataLengthWidth else {
                throw TuyaCandidateDPElectricalCoherenceError.dataLengthWidthMismatch(role: role)
            }
        }
    }

    private static func validateAnchors(
        _ anchors: [TuyaCandidateDPElectricalAnchor]
    ) throws {
        var firstIndexByAnchor: [TuyaCandidateDPElectricalAnchor: Int] = [:]
        var voltageMarkerIndices: Set<Int> = []
        var currentMarkerIndices: Set<Int> = []
        var powerMarkerIndices: Set<Int> = []

        for (anchorIndex, anchor) in anchors.enumerated() {
            if let previous = firstIndexByAnchor.updateValue(anchorIndex, forKey: anchor) {
                throw TuyaCandidateDPElectricalCoherenceError.duplicateAnchor(
                    anchorIndex: anchorIndex,
                    previousAnchorIndex: previous
                )
            }
            guard voltageMarkerIndices.insert(anchor.voltageMarkerIndex).inserted else {
                throw TuyaCandidateDPElectricalCoherenceError.reusedMarkerIndex(
                    role: .voltage,
                    index: anchor.voltageMarkerIndex
                )
            }
            guard currentMarkerIndices.insert(anchor.currentMarkerIndex).inserted else {
                throw TuyaCandidateDPElectricalCoherenceError.reusedMarkerIndex(
                    role: .current,
                    index: anchor.currentMarkerIndex
                )
            }
            guard powerMarkerIndices.insert(anchor.powerMarkerIndex).inserted else {
                throw TuyaCandidateDPElectricalCoherenceError.reusedMarkerIndex(
                    role: .power,
                    index: anchor.powerMarkerIndex
                )
            }
        }
    }

    private static func selectedEvidence(
        in report: TuyaCandidateDPNumericHypothesisReport,
        identifier: String,
        role: TuyaCandidateDPElectricalRole
    ) throws -> TuyaCandidateDPNumericHypothesisEvidence {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPElectricalCoherenceError.invalidHypothesisIdentifier(role: role)
        }
        let matches = report.evidence.filter { $0.hypothesis.identifier == identifier }
        guard !matches.isEmpty else {
            throw TuyaCandidateDPElectricalCoherenceError.missingHypothesis(
                role: role,
                identifier: identifier
            )
        }
        guard matches.count == 1, let evidence = matches.first else {
            throw TuyaCandidateDPElectricalCoherenceError.ambiguousHypothesisIdentifier(
                role: role,
                identifier: identifier
            )
        }
        return evidence
    }

    private static func samplesByMarker(
        _ evidence: TuyaCandidateDPNumericHypothesisEvidence,
        role: TuyaCandidateDPElectricalRole
    ) throws -> [Int: TuyaCandidateDPNumericHypothesisSample] {
        var result: [Int: TuyaCandidateDPNumericHypothesisSample] = [:]
        result.reserveCapacity(evidence.samples.count)
        for sample in evidence.samples {
            guard result.updateValue(sample, forKey: sample.markerIndex) == nil else {
                throw TuyaCandidateDPElectricalCoherenceError.duplicateHypothesisSample(
                    role: role,
                    markerIndex: sample.markerIndex
                )
            }
        }
        return result
    }

    private static func evidenceSpan(
        voltage: TuyaCandidateDPNumericHypothesisSample,
        current: TuyaCandidateDPNumericHypothesisSample,
        power: TuyaCandidateDPNumericHypothesisSample
    ) -> UInt64 {
        let times = [
            voltage.markerReceiptUptimeNanoseconds,
            current.markerReceiptUptimeNanoseconds,
            power.markerReceiptUptimeNanoseconds,
            voltage.observationLastReceiptUptimeNanoseconds,
            current.observationLastReceiptUptimeNanoseconds,
            power.observationLastReceiptUptimeNanoseconds
        ]
        guard let minimum = times.min(), let maximum = times.max() else { return 0 }
        return maximum - minimum
    }

    private static func relationshipMetrics(
        voltage: Double,
        current: Double,
        power: Double,
        policy: TuyaCandidateDPElectricalCoherencePolicy
    ) -> RelationshipMetrics? {
        let predictedPower = voltage * current
        guard predictedPower.isFinite else { return nil }

        let absoluteError = abs(predictedPower - power)
        guard absoluteError.isFinite else { return nil }

        let magnitude = max(abs(predictedPower), abs(power))
        let relativeAllowance = magnitude * policy.relativePowerTolerance
        guard relativeAllowance.isFinite else { return nil }

        let allowedError = max(policy.absolutePowerTolerance, relativeAllowance)
        guard allowedError.isFinite else { return nil }

        let relativeError: Double
        if magnitude == 0 {
            relativeError = 0
        } else {
            relativeError = absoluteError / magnitude
            guard relativeError.isFinite else { return nil }
        }

        return RelationshipMetrics(
            predictedPower: predictedPower,
            absoluteError: absoluteError,
            relativeError: relativeError,
            allowedError: allowedError,
            isWithinTolerance: absoluteError <= allowedError
        )
    }
}

fileprivate struct RelationshipMetrics {
    let predictedPower: Double
    let absoluteError: Double
    let relativeError: Double
    let allowedError: Double
    let isWithinTolerance: Bool
}
