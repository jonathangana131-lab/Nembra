import Foundation

public enum TuyaCandidateDPMarkerCorrelation {
    /// Correlates one caller-selected stock-app field against explicit transform
    /// hypotheses. Upstream tooling must already have paired each marker with the
    /// exact candidate payload from one stream without crossing known gaps.
    public static func analyze(
        _ snapshots: [TuyaCandidateDPMarkerSnapshot],
        field: String,
        hypotheses: [TuyaCandidateDPLinearTransformHypothesis],
        policy: TuyaCandidateDPMarkerCorrelationPolicy
    ) throws -> TuyaCandidateDPMarkerCorrelationReport {
        guard !field.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidMarkerField
        }
        guard snapshots.count <= policy.maximumSnapshotCount else {
            throw TuyaCandidateDPMarkerCorrelationError.snapshotCountExceedsPolicy(
                maximum: policy.maximumSnapshotCount
            )
        }
        guard hypotheses.count <= policy.maximumHypothesisCount else {
            throw TuyaCandidateDPMarkerCorrelationError.hypothesisCountExceedsPolicy(
                maximum: policy.maximumHypothesisCount
            )
        }

        let selected = snapshots.filter {
            $0.markerField.caseInsensitiveCompare(field) == .orderedSame
        }
        guard !selected.isEmpty else {
            return TuyaCandidateDPMarkerCorrelationReport(
                disposition: .noMatchingMarkers,
                field: field,
                sourceStreamIdentity: nil,
                dataLengthWidth: nil,
                markerCount: 0,
                distinctReferenceValueCount: 0,
                representedContinuityGenerations: [],
                evidence: []
            )
        }

        try validateUniqueMarkers(selected)
        try validateSingleStream(selected)
        try validateSingleLengthWidth(selected)

        let streamIdentity = selected[0].sourceStreamIdentity
        let width = selected[0].payload.dataLengthWidth
        let keys = scalarKeys(in: selected).sorted(by: keySort)
        let evidence = keys.flatMap { key in
            hypotheses.map { hypothesis in
                buildEvidence(
                    key: key,
                    hypothesis: hypothesis,
                    snapshots: selected,
                    tolerance: policy.absoluteTolerance
                )
            }
        }
        .sorted(by: evidenceSort)

        return TuyaCandidateDPMarkerCorrelationReport(
            disposition: .analyzed,
            field: field,
            sourceStreamIdentity: streamIdentity,
            dataLengthWidth: width,
            markerCount: selected.count,
            distinctReferenceValueCount: Set(selected.map(\.numericReferenceValue)).count,
            representedContinuityGenerations: Set(selected.map(\.continuityGeneration)),
            evidence: evidence
        )
    }

    private static func validateUniqueMarkers(
        _ snapshots: [TuyaCandidateDPMarkerSnapshot]
    ) throws {
        var seen: Set<UInt64> = []
        for snapshot in snapshots {
            guard seen.insert(snapshot.markerSequenceNumber).inserted else {
                throw TuyaCandidateDPMarkerCorrelationError.duplicateMarkerSequenceNumber(
                    snapshot.markerSequenceNumber
                )
            }
        }
    }

    private static func validateSingleStream(
        _ snapshots: [TuyaCandidateDPMarkerSnapshot]
    ) throws {
        let first = snapshots[0].sourceStreamIdentity
        guard snapshots.dropFirst().allSatisfy({ $0.sourceStreamIdentity == first }) else {
            throw TuyaCandidateDPMarkerCorrelationError.mixedSourceStreamIdentity
        }
    }

    private static func validateSingleLengthWidth(
        _ snapshots: [TuyaCandidateDPMarkerSnapshot]
    ) throws {
        let first = snapshots[0].payload.dataLengthWidth
        let allMatch = snapshots.dropFirst().allSatisfy { snapshot in
            switch (first, snapshot.payload.dataLengthWidth) {
            case (.oneByte, .oneByte), (.twoByteBigEndian, .twoByteBigEndian):
                true
            default:
                false
            }
        }
        guard allMatch else {
            throw TuyaCandidateDPMarkerCorrelationError.mixedDataLengthWidth
        }
    }

    private static func scalarKeys(
        in snapshots: [TuyaCandidateDPMarkerSnapshot]
    ) -> Set<TuyaCandidateDPScalarKey> {
        var keys: Set<TuyaCandidateDPScalarKey> = []
        for snapshot in snapshots {
            for record in snapshot.payload.records where isScalarCandidate(record) {
                keys.insert(
                    TuyaCandidateDPScalarKey(
                        dataLengthWidth: snapshot.payload.dataLengthWidth,
                        identifier: record.identifier,
                        rawType: record.rawType,
                        declaredValueLength: record.declaredValueLength
                    )
                )
            }
        }
        return keys
    }

    private static func isScalarCandidate(_ record: TuyaCandidateDPRecord) -> Bool {
        switch record.knownType {
        case .boolean, .value, .enumeration, .bitmap:
            true
        case .raw, .string, .none:
            false
        }
    }

    private static func buildEvidence(
        key: TuyaCandidateDPScalarKey,
        hypothesis: TuyaCandidateDPLinearTransformHypothesis,
        snapshots: [TuyaCandidateDPMarkerSnapshot],
        tolerance: Double
    ) -> TuyaCandidateDPScalarCorrelationEvidence {
        var candidatePresentCount = 0
        var ambiguousDuplicateCount = 0
        var nonNumericCount = 0
        var transformationFailureCount = 0
        var samples: [TuyaCandidateDPScalarCorrelationSample] = []
        var totalAbsoluteError = 0.0
        var maximumAbsoluteError: Double?
        var distinctReferences: Set<Double> = []

        for snapshot in snapshots {
            let matches = snapshot.payload.records.filter {
                key.matches($0, width: snapshot.payload.dataLengthWidth)
            }
            guard !matches.isEmpty else { continue }
            candidatePresentCount += 1

            guard matches.count == 1 else {
                ambiguousDuplicateCount += 1
                continue
            }
            guard let rawMagnitude = matches[0].candidateUnsignedBigEndianMagnitude else {
                nonNumericCount += 1
                continue
            }
            guard let transformed = hypothesis.applying(to: rawMagnitude) else {
                transformationFailureCount += 1
                continue
            }
            let absoluteError = abs(transformed - snapshot.numericReferenceValue)
            guard absoluteError.isFinite else {
                transformationFailureCount += 1
                continue
            }

            let sample = TuyaCandidateDPScalarCorrelationSample(
                markerSequenceNumber: snapshot.markerSequenceNumber,
                markerDisplayedValue: snapshot.markerDisplayedValue,
                numericReferenceValue: snapshot.numericReferenceValue,
                candidateSequenceNumber: snapshot.candidateSequenceNumber,
                continuityGeneration: snapshot.continuityGeneration,
                rawUnsignedMagnitude: rawMagnitude,
                transformedCandidateValue: transformed,
                absoluteError: absoluteError,
                isWithinTolerance: absoluteError <= tolerance
            )
            samples.append(sample)
            distinctReferences.insert(snapshot.numericReferenceValue)
            totalAbsoluteError += absoluteError
            maximumAbsoluteError = max(maximumAbsoluteError ?? absoluteError, absoluteError)
        }

        samples.sort {
            if $0.markerSequenceNumber != $1.markerSequenceNumber {
                return $0.markerSequenceNumber < $1.markerSequenceNumber
            }
            return $0.candidateSequenceNumber < $1.candidateSequenceNumber
        }

        let meanAbsoluteError = samples.isEmpty ? nil : totalAbsoluteError / Double(samples.count)
        return TuyaCandidateDPScalarCorrelationEvidence(
            key: key,
            hypothesis: hypothesis,
            markerCount: snapshots.count,
            candidatePresentMarkerCount: candidatePresentCount,
            ambiguousDuplicateMarkerCount: ambiguousDuplicateCount,
            nonNumericCandidateMarkerCount: nonNumericCount,
            transformationFailureMarkerCount: transformationFailureCount,
            samples: samples,
            distinctEvaluableReferenceValueCount: distinctReferences.count,
            meanAbsoluteError: meanAbsoluteError,
            maximumAbsoluteError: maximumAbsoluteError
        )
    }

    /// Ranking is a deterministic research convenience only. It favors repeated
    /// matches across more human-observed values, then fuller evaluable coverage
    /// and smaller error. It never upgrades a candidate into verified semantics.
    private static func evidenceSort(
        _ lhs: TuyaCandidateDPScalarCorrelationEvidence,
        _ rhs: TuyaCandidateDPScalarCorrelationEvidence
    ) -> Bool {
        if lhs.matchedWithinToleranceCount != rhs.matchedWithinToleranceCount {
            return lhs.matchedWithinToleranceCount > rhs.matchedWithinToleranceCount
        }
        if lhs.distinctEvaluableReferenceValueCount != rhs.distinctEvaluableReferenceValueCount {
            return lhs.distinctEvaluableReferenceValueCount > rhs.distinctEvaluableReferenceValueCount
        }
        if lhs.evaluableMarkerCount != rhs.evaluableMarkerCount {
            return lhs.evaluableMarkerCount > rhs.evaluableMarkerCount
        }
        let lhsMean = lhs.meanAbsoluteError ?? .infinity
        let rhsMean = rhs.meanAbsoluteError ?? .infinity
        if lhsMean != rhsMean { return lhsMean < rhsMean }
        if keySort(lhs.key, rhs.key) { return true }
        if keySort(rhs.key, lhs.key) { return false }
        return lhs.hypothesis.identifier < rhs.hypothesis.identifier
    }

    private static func keySort(
        _ lhs: TuyaCandidateDPScalarKey,
        _ rhs: TuyaCandidateDPScalarKey
    ) -> Bool {
        if lhs.widthOrder != rhs.widthOrder { return lhs.widthOrder < rhs.widthOrder }
        if lhs.identifier != rhs.identifier { return lhs.identifier < rhs.identifier }
        if lhs.rawType != rhs.rawType { return lhs.rawType < rhs.rawType }
        return lhs.declaredValueLength < rhs.declaredValueLength
    }
}
