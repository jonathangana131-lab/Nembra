import Foundation

/// Fail-closed errors for repeated numeric correlation of already-parsed Tuya
/// DP candidates against caller-supplied stock-app reference observations.
///
/// This layer never parses human display strings and never assigns an AOVOPRO
/// ES80 meaning, unit, signedness, or scale to a DP identifier.
public enum TuyaCandidateDPMarkerCorrelationError: Error, Equatable, Sendable {
    case invalidMarkerField
    case invalidSourceStreamIdentity
    case invalidNumericReferenceValue(markerSequenceNumber: UInt64)
    case invalidHypothesisIdentifier
    case invalidHypothesisScale
    case invalidHypothesisOffset
    case invalidMaximumSnapshotCount
    case invalidMaximumHypothesisCount
    case invalidAbsoluteTolerance
    case snapshotCountExceedsPolicy(maximum: Int)
    case hypothesisCountExceedsPolicy(maximum: Int)
    case duplicateMarkerSequenceNumber(UInt64)
    case mixedSourceStreamIdentity
    case mixedDataLengthWidth
}

/// One exact human-observed marker paired upstream with one exact candidate DP
/// payload from one opaque source stream.
///
/// `numericReferenceValue` must be supplied explicitly by research tooling. The
/// analyzer intentionally does not turn strings such as "41.3 V" or "73%" into
/// numbers, because doing so would silently create unit/format assumptions.
public struct TuyaCandidateDPMarkerSnapshot: Equatable, Sendable {
    public let markerSequenceNumber: UInt64
    public let markerField: String
    public let markerDisplayedValue: String
    public let numericReferenceValue: Double
    public let candidateSequenceNumber: UInt64
    public let sourceStreamIdentity: String
    public let continuityGeneration: UInt64
    public let payload: TuyaCandidateDPPayload

    public init(
        markerSequenceNumber: UInt64,
        markerField: String,
        markerDisplayedValue: String,
        numericReferenceValue: Double,
        candidateSequenceNumber: UInt64,
        sourceStreamIdentity: String,
        continuityGeneration: UInt64,
        payload: TuyaCandidateDPPayload
    ) throws {
        guard !markerField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidMarkerField
        }
        guard !sourceStreamIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidSourceStreamIdentity
        }
        guard numericReferenceValue.isFinite else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidNumericReferenceValue(
                markerSequenceNumber: markerSequenceNumber
            )
        }

        self.markerSequenceNumber = markerSequenceNumber
        self.markerField = markerField
        self.markerDisplayedValue = markerDisplayedValue
        self.numericReferenceValue = numericReferenceValue
        self.candidateSequenceNumber = candidateSequenceNumber
        self.sourceStreamIdentity = sourceStreamIdentity
        self.continuityGeneration = continuityGeneration
        self.payload = payload
    }
}

/// One explicit caller-supplied linear interpretation hypothesis:
///
/// `displayCandidate = rawUnsignedMagnitude * scale + offset`
///
/// This is research input, not protocol truth. Nembra does not provide a default
/// volts/amps/watts/battery scale here and does not search arbitrary transforms.
public struct TuyaCandidateDPLinearTransformHypothesis: Equatable, Sendable {
    public let identifier: String
    public let scale: Double
    public let offset: Double

    public init(identifier: String, scale: Double, offset: Double = 0) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidHypothesisIdentifier
        }
        guard scale.isFinite, scale != 0 else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidHypothesisScale
        }
        guard offset.isFinite else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidHypothesisOffset
        }
        self.identifier = identifier
        self.scale = scale
        self.offset = offset
    }

    package func applying(to rawMagnitude: UInt32) -> Double? {
        let result = Double(rawMagnitude) * scale + offset
        return result.isFinite ? result : nil
    }
}

/// Caller-owned work bounds and comparison tolerance. There are deliberately no
/// ES80 defaults: choosing a tolerance is part of the physical research method.
public struct TuyaCandidateDPMarkerCorrelationPolicy: Equatable, Sendable {
    public let maximumSnapshotCount: Int
    public let maximumHypothesisCount: Int
    public let absoluteTolerance: Double

    public init(
        maximumSnapshotCount: Int,
        maximumHypothesisCount: Int,
        absoluteTolerance: Double
    ) throws {
        guard maximumSnapshotCount > 0 else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidMaximumSnapshotCount
        }
        guard maximumHypothesisCount > 0 else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidMaximumHypothesisCount
        }
        guard absoluteTolerance.isFinite, absoluteTolerance >= 0 else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidAbsoluteTolerance
        }
        self.maximumSnapshotCount = maximumSnapshotCount
        self.maximumHypothesisCount = maximumHypothesisCount
        self.absoluteTolerance = absoluteTolerance
    }
}

/// Exact structural key for one scalar-shaped DP candidate. The framing-width
/// hypothesis is part of identity so different public-family interpretations are
/// never silently collapsed into one candidate.
public struct TuyaCandidateDPScalarKey: Equatable, Hashable, Sendable {
    public let dataLengthWidth: TuyaCandidateDPDataLengthWidth
    public let identifier: UInt8
    public let rawType: UInt8
    public let declaredValueLength: Int

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.widthOrder == rhs.widthOrder
            && lhs.identifier == rhs.identifier
            && lhs.rawType == rhs.rawType
            && lhs.declaredValueLength == rhs.declaredValueLength
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(widthOrder)
        hasher.combine(identifier)
        hasher.combine(rawType)
        hasher.combine(declaredValueLength)
    }

    package var widthOrder: Int {
        switch dataLengthWidth {
        case .oneByte: 0
        case .twoByteBigEndian: 1
        }
    }

    package func matches(
        _ record: TuyaCandidateDPRecord,
        width: TuyaCandidateDPDataLengthWidth
    ) -> Bool {
        switch (dataLengthWidth, width) {
        case (.oneByte, .oneByte), (.twoByteBigEndian, .twoByteBigEndian):
            break
        default:
            return false
        }
        return identifier == record.identifier
            && rawType == record.rawType
            && declaredValueLength == record.declaredValueLength
    }
}

/// One auditable marker/candidate comparison. The raw magnitude is retained next
/// to the transformed research value so the transform never replaces evidence.
public struct TuyaCandidateDPScalarCorrelationSample: Equatable, Sendable {
    public let markerSequenceNumber: UInt64
    public let markerDisplayedValue: String
    public let numericReferenceValue: Double
    public let candidateSequenceNumber: UInt64
    public let continuityGeneration: UInt64
    public let rawUnsignedMagnitude: UInt32
    public let transformedCandidateValue: Double
    public let absoluteError: Double
    public let isWithinTolerance: Bool

    package init(
        markerSequenceNumber: UInt64,
        markerDisplayedValue: String,
        numericReferenceValue: Double,
        candidateSequenceNumber: UInt64,
        continuityGeneration: UInt64,
        rawUnsignedMagnitude: UInt32,
        transformedCandidateValue: Double,
        absoluteError: Double,
        isWithinTolerance: Bool
    ) {
        self.markerSequenceNumber = markerSequenceNumber
        self.markerDisplayedValue = markerDisplayedValue
        self.numericReferenceValue = numericReferenceValue
        self.candidateSequenceNumber = candidateSequenceNumber
        self.continuityGeneration = continuityGeneration
        self.rawUnsignedMagnitude = rawUnsignedMagnitude
        self.transformedCandidateValue = transformedCandidateValue
        self.absoluteError = absoluteError
        self.isWithinTolerance = isWithinTolerance
    }
}

/// Descriptive repeated-correlation evidence for one exact DP structural key and
/// one explicit transform hypothesis. This is a prioritization result only, not
/// field verification or protocol confidence.
public struct TuyaCandidateDPScalarCorrelationEvidence: Equatable, Sendable {
    public let key: TuyaCandidateDPScalarKey
    public let hypothesis: TuyaCandidateDPLinearTransformHypothesis
    public let markerCount: Int
    public let candidatePresentMarkerCount: Int
    public let ambiguousDuplicateMarkerCount: Int
    public let nonNumericCandidateMarkerCount: Int
    public let transformationFailureMarkerCount: Int
    public let samples: [TuyaCandidateDPScalarCorrelationSample]
    public let distinctEvaluableReferenceValueCount: Int
    public let meanAbsoluteError: Double?
    public let maximumAbsoluteError: Double?

    public var evaluableMarkerCount: Int { samples.count }
    public var matchedWithinToleranceCount: Int {
        samples.reduce(into: 0) { count, sample in
            if sample.isWithinTolerance { count += 1 }
        }
    }

    public var markerCoverageFraction: Double {
        guard markerCount > 0 else { return 0 }
        return Double(evaluableMarkerCount) / Double(markerCount)
    }

    package init(
        key: TuyaCandidateDPScalarKey,
        hypothesis: TuyaCandidateDPLinearTransformHypothesis,
        markerCount: Int,
        candidatePresentMarkerCount: Int,
        ambiguousDuplicateMarkerCount: Int,
        nonNumericCandidateMarkerCount: Int,
        transformationFailureMarkerCount: Int,
        samples: [TuyaCandidateDPScalarCorrelationSample],
        distinctEvaluableReferenceValueCount: Int,
        meanAbsoluteError: Double?,
        maximumAbsoluteError: Double?
    ) {
        self.key = key
        self.hypothesis = hypothesis
        self.markerCount = markerCount
        self.candidatePresentMarkerCount = candidatePresentMarkerCount
        self.ambiguousDuplicateMarkerCount = ambiguousDuplicateMarkerCount
        self.nonNumericCandidateMarkerCount = nonNumericCandidateMarkerCount
        self.transformationFailureMarkerCount = transformationFailureMarkerCount
        self.samples = samples
        self.distinctEvaluableReferenceValueCount = distinctEvaluableReferenceValueCount
        self.meanAbsoluteError = meanAbsoluteError
        self.maximumAbsoluteError = maximumAbsoluteError
    }
}

public enum TuyaCandidateDPMarkerCorrelationDisposition: String, Equatable, Sendable {
    case analyzed
    case noMatchingMarkers
}

/// One field-specific report over a single exact opaque source stream and a
/// single fixed DP framing-width hypothesis.
public struct TuyaCandidateDPMarkerCorrelationReport: Equatable, Sendable {
    public let disposition: TuyaCandidateDPMarkerCorrelationDisposition
    public let field: String
    public let sourceStreamIdentity: String?
    public let dataLengthWidth: TuyaCandidateDPDataLengthWidth?
    public let markerCount: Int
    public let distinctReferenceValueCount: Int
    public let representedContinuityGenerations: Set<UInt64>
    public let evidence: [TuyaCandidateDPScalarCorrelationEvidence]

    package init(
        disposition: TuyaCandidateDPMarkerCorrelationDisposition,
        field: String,
        sourceStreamIdentity: String?,
        dataLengthWidth: TuyaCandidateDPDataLengthWidth?,
        markerCount: Int,
        distinctReferenceValueCount: Int,
        representedContinuityGenerations: Set<UInt64>,
        evidence: [TuyaCandidateDPScalarCorrelationEvidence]
    ) {
        self.disposition = disposition
        self.field = field
        self.sourceStreamIdentity = sourceStreamIdentity
        self.dataLengthWidth = dataLengthWidth
        self.markerCount = markerCount
        self.distinctReferenceValueCount = distinctReferenceValueCount
        self.representedContinuityGenerations = representedContinuityGenerations
        self.evidence = evidence
    }
}
