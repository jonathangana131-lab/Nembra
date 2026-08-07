import Foundation

/// Fail-closed validation for the numeric hypothesis layer that sits strictly
/// above `TuyaCandidateDPMarkerCorrelator` temporal/equality evidence.
///
/// This layer never parses stock-app display strings and never promotes a
/// transform into AOVOPRO ES80 field truth.
public enum TuyaCandidateDPNumericHypothesisError: Error, Equatable, Sendable {
    case invalidCandidateIndex(Int)
    case invalidMarkerIndex(Int)
    case invalidNumericReference(markerIndex: Int)
    case duplicateNumericReferenceMarkerIndex(Int)
    case invalidHypothesisIdentifier
    case invalidHypothesisScale
    case invalidHypothesisOffset
    case invalidMaximumReferenceCount
    case invalidMaximumHypothesisCount
    case invalidAbsoluteTolerance
    case referenceCountExceedsPolicy(maximum: Int)
    case hypothesisCountExceedsPolicy(maximum: Int)
}

/// Caller-supplied numeric interpretation of one stock-app marker that already
/// exists in a parent temporal correlation report.
///
/// The marker index is the immutable bridge back to the exact marker/hit. Nembra
/// does not derive this number from `displayedReference`; locale, suffix, unit,
/// decimal-place and formatting assumptions therefore stay outside the core.
public struct TuyaCandidateDPNumericReference: Equatable, Sendable {
    public let markerIndex: Int
    public let value: Double

    public init(markerIndex: Int, value: Double) throws {
        guard markerIndex >= 0 else {
            throw TuyaCandidateDPNumericHypothesisError.invalidMarkerIndex(markerIndex)
        }
        guard value.isFinite else {
            throw TuyaCandidateDPNumericHypothesisError.invalidNumericReference(markerIndex: markerIndex)
        }
        self.markerIndex = markerIndex
        self.value = value
    }
}

/// One explicit caller-supplied linear interpretation candidate:
///
/// `displayCandidate = rawUnsignedMagnitude * scale + offset`
///
/// No battery/voltage/current/power defaults live here. A transform is research
/// input only and is retained verbatim beside every resulting comparison.
public struct TuyaCandidateDPNumericTransformHypothesis: Equatable, Sendable {
    public let identifier: String
    public let scale: Double
    public let offset: Double

    public init(identifier: String, scale: Double, offset: Double = 0) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPNumericHypothesisError.invalidHypothesisIdentifier
        }
        guard scale.isFinite, scale != 0 else {
            throw TuyaCandidateDPNumericHypothesisError.invalidHypothesisScale
        }
        guard offset.isFinite else {
            throw TuyaCandidateDPNumericHypothesisError.invalidHypothesisOffset
        }
        self.identifier = identifier
        self.scale = scale
        self.offset = offset
    }

    fileprivate func applying(to rawMagnitude: UInt32) -> Double? {
        let transformed = Double(rawMagnitude) * scale + offset
        return transformed.isFinite ? transformed : nil
    }
}

/// Caller-owned work limits and display-space comparison tolerance. These are
/// analysis policy, never physical ES80 protocol defaults.
public struct TuyaCandidateDPNumericHypothesisPolicy: Equatable, Sendable {
    public let maximumReferenceCount: Int
    public let maximumHypothesisCount: Int
    public let absoluteTolerance: Double

    public init(
        maximumReferenceCount: Int,
        maximumHypothesisCount: Int,
        absoluteTolerance: Double
    ) throws {
        guard maximumReferenceCount > 0 else {
            throw TuyaCandidateDPNumericHypothesisError.invalidMaximumReferenceCount
        }
        guard maximumHypothesisCount > 0 else {
            throw TuyaCandidateDPNumericHypothesisError.invalidMaximumHypothesisCount
        }
        guard absoluteTolerance.isFinite, absoluteTolerance >= 0 else {
            throw TuyaCandidateDPNumericHypothesisError.invalidAbsoluteTolerance
        }
        self.maximumReferenceCount = maximumReferenceCount
        self.maximumHypothesisCount = maximumHypothesisCount
        self.absoluteTolerance = absoluteTolerance
    }
}

/// One auditable comparison tied directly to the parent's accepted temporal hit.
/// Exact marker/message timing, DP byte offsets, raw bytes and raw magnitude stay
/// present beside transformed research math so this layer never weakens source
/// provenance merely because it adds a numeric comparison.
public struct TuyaCandidateDPNumericHypothesisSample: Equatable, Sendable {
    public let markerIndex: Int
    public let markerReceiptUptimeNanoseconds: UInt64
    public let displayedReference: String
    public let numericReferenceValue: Double
    public let observationIndex: Int
    public let observationFirstReceiptUptimeNanoseconds: UInt64
    public let observationLastReceiptUptimeNanoseconds: UInt64
    public let temporalDistanceNanoseconds: UInt64
    public let temporalRelation: TuyaCandidateDPMarkerTemporalRelation
    public let headerByteOffset: Int
    public let valueByteOffset: Int
    public let endByteOffsetExclusive: Int
    public let valueBytes: [UInt8]
    public let rawUnsignedMagnitude: UInt32
    public let transformedCandidateValue: Double
    public let absoluteError: Double
    public let isWithinTolerance: Bool

    fileprivate init(
        hit: TuyaCandidateDPMarkerHit,
        numericReferenceValue: Double,
        rawUnsignedMagnitude: UInt32,
        transformedCandidateValue: Double,
        absoluteError: Double,
        isWithinTolerance: Bool
    ) {
        markerIndex = hit.markerIndex
        markerReceiptUptimeNanoseconds = hit.markerReceiptUptimeNanoseconds
        displayedReference = hit.displayedReference
        self.numericReferenceValue = numericReferenceValue
        observationIndex = hit.observationIndex
        observationFirstReceiptUptimeNanoseconds = hit.observationFirstReceiptUptimeNanoseconds
        observationLastReceiptUptimeNanoseconds = hit.observationLastReceiptUptimeNanoseconds
        temporalDistanceNanoseconds = hit.temporalDistanceNanoseconds
        temporalRelation = hit.temporalRelation
        headerByteOffset = hit.headerByteOffset
        valueByteOffset = hit.valueByteOffset
        endByteOffsetExclusive = hit.endByteOffsetExclusive
        valueBytes = hit.valueBytes
        self.rawUnsignedMagnitude = rawUnsignedMagnitude
        self.transformedCandidateValue = transformedCandidateValue
        self.absoluteError = absoluteError
        self.isWithinTolerance = isWithinTolerance
    }
}

/// Descriptive evidence for one explicit transform. Counts describe only the
/// supplied marker references and parent-accepted hits; they are not confidence.
public struct TuyaCandidateDPNumericHypothesisEvidence: Equatable, Sendable {
    public let hypothesis: TuyaCandidateDPNumericTransformHypothesis
    public let numericReferenceCount: Int
    public let candidateHitCount: Int
    public let referencedCandidateHitCount: Int
    public let nonNumericReferencedHitCount: Int
    public let transformationFailureCount: Int
    public let distinctEvaluableReferenceValueCount: Int
    public let samples: [TuyaCandidateDPNumericHypothesisSample]
    public let meanAbsoluteError: Double?
    public let maximumAbsoluteError: Double?

    public var evaluableReferenceCount: Int { samples.count }

    public var matchedWithinToleranceCount: Int {
        samples.reduce(into: 0) { count, sample in
            if sample.isWithinTolerance { count += 1 }
        }
    }

    fileprivate init(
        hypothesis: TuyaCandidateDPNumericTransformHypothesis,
        numericReferenceCount: Int,
        candidateHitCount: Int,
        referencedCandidateHitCount: Int,
        nonNumericReferencedHitCount: Int,
        transformationFailureCount: Int,
        distinctEvaluableReferenceValueCount: Int,
        samples: [TuyaCandidateDPNumericHypothesisSample],
        meanAbsoluteError: Double?,
        maximumAbsoluteError: Double?
    ) {
        self.hypothesis = hypothesis
        self.numericReferenceCount = numericReferenceCount
        self.candidateHitCount = candidateHitCount
        self.referencedCandidateHitCount = referencedCandidateHitCount
        self.nonNumericReferencedHitCount = nonNumericReferencedHitCount
        self.transformationFailureCount = transformationFailureCount
        self.distinctEvaluableReferenceValueCount = distinctEvaluableReferenceValueCount
        self.samples = samples
        self.meanAbsoluteError = meanAbsoluteError
        self.maximumAbsoluteError = maximumAbsoluteError
    }
}

/// Numeric hypothesis evaluation for one exact candidate from one parent report.
/// Scope/continuity/framing truth remains owned by that report rather than being
/// re-invented here. The exact tolerance is retained because `isWithinTolerance`
/// is otherwise not auditable once the caller-owned policy leaves scope.
public struct TuyaCandidateDPNumericHypothesisReport: Equatable, Sendable {
    public let correlationScope: TuyaCandidateDPMarkerCorrelationScope
    public let candidateIndex: Int
    public let candidate: TuyaCandidateDPCorrelationCandidate
    public let numericReferenceCount: Int
    public let absoluteTolerance: Double
    public let unusedReferenceMarkerIndices: [Int]
    public let ambiguousReferenceMarkerIndices: [Int]
    public let sharedObservationReferenceMarkerIndices: [Int]
    public let evidence: [TuyaCandidateDPNumericHypothesisEvidence]

    fileprivate init(
        correlationScope: TuyaCandidateDPMarkerCorrelationScope,
        candidateIndex: Int,
        candidate: TuyaCandidateDPCorrelationCandidate,
        numericReferenceCount: Int,
        absoluteTolerance: Double,
        unusedReferenceMarkerIndices: [Int],
        ambiguousReferenceMarkerIndices: [Int],
        sharedObservationReferenceMarkerIndices: [Int],
        evidence: [TuyaCandidateDPNumericHypothesisEvidence]
    ) {
        self.correlationScope = correlationScope
        self.candidateIndex = candidateIndex
        self.candidate = candidate
        self.numericReferenceCount = numericReferenceCount
        self.absoluteTolerance = absoluteTolerance
        self.unusedReferenceMarkerIndices = unusedReferenceMarkerIndices
        self.ambiguousReferenceMarkerIndices = ambiguousReferenceMarkerIndices
        self.sharedObservationReferenceMarkerIndices = sharedObservationReferenceMarkerIndices
        self.evidence = evidence
    }
}

public enum TuyaCandidateDPNumericHypothesisEvaluator {
    /// Evaluates explicit numeric transforms only after the parent correlator has
    /// selected one exact stream/generation/framing scope and produced at most one
    /// independent, unambiguous candidate hit per marker.
    public static func evaluate(
        report: TuyaCandidateDPMarkerCorrelationReport,
        candidateIndex: Int,
        numericReferences: [TuyaCandidateDPNumericReference],
        hypotheses: [TuyaCandidateDPNumericTransformHypothesis],
        policy: TuyaCandidateDPNumericHypothesisPolicy
    ) throws -> TuyaCandidateDPNumericHypothesisReport {
        guard report.candidates.indices.contains(candidateIndex) else {
            throw TuyaCandidateDPNumericHypothesisError.invalidCandidateIndex(candidateIndex)
        }
        guard numericReferences.count <= policy.maximumReferenceCount else {
            throw TuyaCandidateDPNumericHypothesisError.referenceCountExceedsPolicy(
                maximum: policy.maximumReferenceCount
            )
        }
        guard hypotheses.count <= policy.maximumHypothesisCount else {
            throw TuyaCandidateDPNumericHypothesisError.hypothesisCountExceedsPolicy(
                maximum: policy.maximumHypothesisCount
            )
        }

        let candidateEvidence = report.candidates[candidateIndex]
        let referencesByMarker = try validatedReferences(
            numericReferences,
            markerCount: report.markerCount
        )
        let hitMarkerIndices = Set(candidateEvidence.hits.map(\.markerIndex))
        let ambiguousMarkerIndices = Set(candidateEvidence.ambiguousNearestMarkerIndices)
        let sharedObservationMarkerIndices = Set(candidateEvidence.sharedObservationMarkerIndices)
        let unusedReferenceMarkerIndices = referencesByMarker.keys
            .filter {
                !hitMarkerIndices.contains($0)
                    && !ambiguousMarkerIndices.contains($0)
                    && !sharedObservationMarkerIndices.contains($0)
            }
            .sorted()
        let ambiguousReferenceMarkerIndices = referencesByMarker.keys
            .filter { ambiguousMarkerIndices.contains($0) }
            .sorted()
        let sharedObservationReferenceMarkerIndices = referencesByMarker.keys
            .filter { sharedObservationMarkerIndices.contains($0) }
            .sorted()

        let evidence = hypotheses.map { hypothesis in
            buildEvidence(
                hypothesis: hypothesis,
                candidateEvidence: candidateEvidence,
                referencesByMarker: referencesByMarker,
                tolerance: policy.absoluteTolerance
            )
        }
        .sorted(by: evidenceRanksBefore)

        return TuyaCandidateDPNumericHypothesisReport(
            correlationScope: report.scope,
            candidateIndex: candidateIndex,
            candidate: candidateEvidence.candidate,
            numericReferenceCount: numericReferences.count,
            absoluteTolerance: policy.absoluteTolerance,
            unusedReferenceMarkerIndices: unusedReferenceMarkerIndices,
            ambiguousReferenceMarkerIndices: ambiguousReferenceMarkerIndices,
            sharedObservationReferenceMarkerIndices: sharedObservationReferenceMarkerIndices,
            evidence: evidence
        )
    }

    private static func validatedReferences(
        _ references: [TuyaCandidateDPNumericReference],
        markerCount: Int
    ) throws -> [Int: Double] {
        var byMarker: [Int: Double] = [:]
        byMarker.reserveCapacity(references.count)
        for reference in references {
            guard reference.markerIndex < markerCount else {
                throw TuyaCandidateDPNumericHypothesisError.invalidMarkerIndex(reference.markerIndex)
            }
            guard byMarker.updateValue(reference.value, forKey: reference.markerIndex) == nil else {
                throw TuyaCandidateDPNumericHypothesisError.duplicateNumericReferenceMarkerIndex(
                    reference.markerIndex
                )
            }
        }
        return byMarker
    }

    private static func buildEvidence(
        hypothesis: TuyaCandidateDPNumericTransformHypothesis,
        candidateEvidence: TuyaCandidateDPMarkerCandidateEvidence,
        referencesByMarker: [Int: Double],
        tolerance: Double
    ) -> TuyaCandidateDPNumericHypothesisEvidence {
        var referencedCandidateHitCount = 0
        var nonNumericReferencedHitCount = 0
        var transformationFailureCount = 0
        var samples: [TuyaCandidateDPNumericHypothesisSample] = []
        var distinctEvaluableReferences: Set<Double> = []
        var maximumAbsoluteError: Double?

        for hit in candidateEvidence.hits {
            guard let numericReference = referencesByMarker[hit.markerIndex] else { continue }
            referencedCandidateHitCount += 1

            guard let rawMagnitude = unsignedMagnitude(
                for: candidateEvidence.candidate,
                valueBytes: hit.valueBytes
            ) else {
                nonNumericReferencedHitCount += 1
                continue
            }
            guard let transformed = hypothesis.applying(to: rawMagnitude) else {
                transformationFailureCount += 1
                continue
            }
            let absoluteError = abs(transformed - numericReference)
            guard absoluteError.isFinite else {
                transformationFailureCount += 1
                continue
            }

            samples.append(
                TuyaCandidateDPNumericHypothesisSample(
                    hit: hit,
                    numericReferenceValue: numericReference,
                    rawUnsignedMagnitude: rawMagnitude,
                    transformedCandidateValue: transformed,
                    absoluteError: absoluteError,
                    isWithinTolerance: absoluteError <= tolerance
                )
            )
            distinctEvaluableReferences.insert(numericReference)
            maximumAbsoluteError = max(maximumAbsoluteError ?? absoluteError, absoluteError)
        }

        samples.sort { lhs, rhs in
            if lhs.markerIndex != rhs.markerIndex { return lhs.markerIndex < rhs.markerIndex }
            return lhs.observationIndex < rhs.observationIndex
        }

        let meanAbsoluteError: Double?
        if samples.isEmpty {
            meanAbsoluteError = nil
        } else {
            let divisor = Double(samples.count)
            let normalizedSum = samples.reduce(0.0) { partial, sample in
                partial + sample.absoluteError / divisor
            }
            meanAbsoluteError = normalizedSum.isFinite ? normalizedSum : nil
        }

        return TuyaCandidateDPNumericHypothesisEvidence(
            hypothesis: hypothesis,
            numericReferenceCount: referencesByMarker.count,
            candidateHitCount: candidateEvidence.hits.count,
            referencedCandidateHitCount: referencedCandidateHitCount,
            nonNumericReferencedHitCount: nonNumericReferencedHitCount,
            transformationFailureCount: transformationFailureCount,
            distinctEvaluableReferenceValueCount: distinctEvaluableReferences.count,
            samples: samples,
            meanAbsoluteError: meanAbsoluteError,
            maximumAbsoluteError: maximumAbsoluteError
        )
    }

    /// Mirrors #238's deliberately generic scalar projection against the raw
    /// bytes retained by the parent correlator. No signedness, scale, unit or
    /// field meaning is assigned. Malformed documented shapes remain unavailable.
    private static func unsignedMagnitude(
        for candidate: TuyaCandidateDPCorrelationCandidate,
        valueBytes: [UInt8]
    ) -> UInt32? {
        switch candidate.knownType {
        case .boolean:
            guard valueBytes.count == 1, valueBytes[0] <= 1 else { return nil }
        case .value:
            guard [1, 2, 4].contains(valueBytes.count) else { return nil }
        case .enumeration:
            guard valueBytes.count == 1 else { return nil }
        case .bitmap:
            guard [1, 2, 4].contains(valueBytes.count) else { return nil }
        case .raw, .string, .none:
            return nil
        }

        guard valueBytes.count == candidate.declaredValueLength else { return nil }
        var result: UInt32 = 0
        for byte in valueBytes {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    /// Deterministic research convenience only. More repeated in-tolerance
    /// support wins, then broader numeric variation/evaluable coverage and lower
    /// display-space error. This never becomes protocol confidence.
    private static func evidenceRanksBefore(
        _ lhs: TuyaCandidateDPNumericHypothesisEvidence,
        _ rhs: TuyaCandidateDPNumericHypothesisEvidence
    ) -> Bool {
        if lhs.matchedWithinToleranceCount != rhs.matchedWithinToleranceCount {
            return lhs.matchedWithinToleranceCount > rhs.matchedWithinToleranceCount
        }
        if lhs.distinctEvaluableReferenceValueCount != rhs.distinctEvaluableReferenceValueCount {
            return lhs.distinctEvaluableReferenceValueCount > rhs.distinctEvaluableReferenceValueCount
        }
        if lhs.evaluableReferenceCount != rhs.evaluableReferenceCount {
            return lhs.evaluableReferenceCount > rhs.evaluableReferenceCount
        }
        let lhsMean = lhs.meanAbsoluteError ?? .infinity
        let rhsMean = rhs.meanAbsoluteError ?? .infinity
        if lhsMean != rhsMean { return lhsMean < rhsMean }
        if lhs.hypothesis.identifier != rhs.hypothesis.identifier {
            return lhs.hypothesis.identifier < rhs.hypothesis.identifier
        }
        if lhs.hypothesis.scale != rhs.hypothesis.scale {
            return lhs.hypothesis.scale < rhs.hypothesis.scale
        }
        if lhs.hypothesis.offset != rhs.hypothesis.offset {
            return lhs.hypothesis.offset < rhs.hypothesis.offset
        }
        return false
    }
}
