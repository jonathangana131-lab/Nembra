import Foundation

/// Fail-closed validation for offline correlation between caller-bound Tuya DP
/// candidates and human-observed stock-app reference markers.
///
/// Correlation is research prioritization only. None of these errors or outputs
/// establish an AOVOPRO ES80 DP meaning, unit, scale, signedness, or cadence.
public enum TuyaCandidateDPMarkerCorrelationError: Error, Equatable, Sendable {
    case emptyFieldLabel
    case emptyDisplayedReference
    case invalidMaximumMarkerCount
    case invalidMaximumObservationCount
    case invalidMaximumCandidateOccurrenceCount
    case markerCountExceedsPolicy(maximum: Int)
    case observationCountExceedsPolicy(maximum: Int)
    case candidateOccurrenceCountExceedsPolicy(maximum: Int)
    case invalidObservationReceiptInterval(index: Int)
    case observationStreamIdentityMismatch(index: Int)
    case observationContinuityGenerationMismatch(index: Int)
    case observationLengthWidthMismatch(index: Int)
    case nonMonotonicObservationChronology(previousIndex: Int, currentIndex: Int)
    case nonMonotonicMarkerChronology(previousIndex: Int, currentIndex: Int)
}

/// Exact research scope for one DP-correlation pass.
///
/// A pass is deliberately limited to one exact GATT value stream, one caller-
/// supplied byte-continuity generation, and one explicit Tuya DP length-width
/// hypothesis. A caller must start another pass rather than mixing these
/// boundaries until they happen to produce a stronger-looking result.
public struct TuyaCandidateDPMarkerCorrelationScope: Equatable, Sendable {
    public let fieldLabel: String
    public let streamIdentity: TuyaCandidateValueStreamIdentity
    public let continuityGeneration: UInt64
    public let dataLengthWidth: TuyaCandidateDPDataLengthWidth

    public init(
        fieldLabel: String,
        streamIdentity: TuyaCandidateValueStreamIdentity,
        continuityGeneration: UInt64,
        dataLengthWidth: TuyaCandidateDPDataLengthWidth
    ) throws {
        guard !fieldLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPMarkerCorrelationError.emptyFieldLabel
        }
        self.fieldLabel = fieldLabel
        self.streamIdentity = streamIdentity
        self.continuityGeneration = continuityGeneration
        self.dataLengthWidth = dataLengthWidth
    }
}

/// One human-observed stock-app value/reference inserted into the same monotonic
/// capture timeline. The text is intentionally preserved exactly as supplied.
/// `"41.3 V"` and `"41.30 V"` are therefore distinct reference anchors; this
/// layer does not normalize units, precision, locale, or formatting.
public struct TuyaCandidateDPStockAppMarker: Equatable, Sendable {
    public let receiptUptimeNanoseconds: UInt64
    public let displayedReference: String

    public init(receiptUptimeNanoseconds: UInt64, displayedReference: String) throws {
        guard !displayedReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TuyaCandidateDPMarkerCorrelationError.emptyDisplayedReference
        }
        self.receiptUptimeNanoseconds = receiptUptimeNanoseconds
        self.displayedReference = displayedReference
    }
}

/// Caller-owned analysis/resource bounds. These are not ES80 defaults.
public struct TuyaCandidateDPMarkerCorrelationPolicy: Equatable, Sendable {
    /// Maximum monotonic-time distance from a marker to the nearest point of a
    /// candidate message's accepted receipt interval. Zero is a valid exact-only
    /// policy.
    public let maximumMarkerDistanceNanoseconds: UInt64
    public let maximumMarkerCount: Int
    public let maximumObservationCount: Int
    public let maximumCandidateOccurrenceCount: Int

    public init(
        maximumMarkerDistanceNanoseconds: UInt64,
        maximumMarkerCount: Int,
        maximumObservationCount: Int,
        maximumCandidateOccurrenceCount: Int
    ) throws {
        guard maximumMarkerCount > 0 else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidMaximumMarkerCount
        }
        guard maximumObservationCount > 0 else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidMaximumObservationCount
        }
        guard maximumCandidateOccurrenceCount > 0 else {
            throw TuyaCandidateDPMarkerCorrelationError.invalidMaximumCandidateOccurrenceCount
        }
        self.maximumMarkerDistanceNanoseconds = maximumMarkerDistanceNanoseconds
        self.maximumMarkerCount = maximumMarkerCount
        self.maximumObservationCount = maximumObservationCount
        self.maximumCandidateOccurrenceCount = maximumCandidateOccurrenceCount
    }
}

/// One parsed DP payload explicitly associated by the caller with the exact
/// reassembled-message evidence from which its legitimate plaintext was derived.
///
/// This association is intentionally transparent: Nembra does not decrypt or
/// authenticate here, and this type cannot prove that caller-supplied plaintext
/// came from the encrypted bytes. It only preserves the reassembled message's
/// exact stream, continuity generation, and receipt interval alongside #238's
/// structural DP parse for subsequent offline correlation.
public struct TuyaCandidateDPMessageObservation: Equatable, Sendable {
    public let streamIdentity: TuyaCandidateValueStreamIdentity
    public let continuityGeneration: UInt64
    public let firstReceiptUptimeNanoseconds: UInt64
    public let lastReceiptUptimeNanoseconds: UInt64
    public let payload: TuyaCandidateDPPayload

    public init(
        reassembledMessage: TuyaCandidateReassembledMessage,
        parsedPayload: TuyaCandidateDPPayload
    ) {
        self.streamIdentity = reassembledMessage.streamIdentity
        self.continuityGeneration = reassembledMessage.continuityGeneration
        self.firstReceiptUptimeNanoseconds = reassembledMessage.firstReceiptUptimeNanoseconds
        self.lastReceiptUptimeNanoseconds = reassembledMessage.lastReceiptUptimeNanoseconds
        self.payload = parsedPayload
    }
}

/// Structural identity used for repeatability comparison. Same numeric DP ID is
/// not silently merged across a different raw type or declared width.
public struct TuyaCandidateDPCorrelationCandidate: Equatable, Sendable {
    public let identifier: UInt8
    public let rawType: UInt8
    public let knownType: TuyaCandidateDPKnownType?
    public let declaredValueLength: Int

    fileprivate init(identifier: UInt8, rawType: UInt8, declaredValueLength: Int) {
        self.identifier = identifier
        self.rawType = rawType
        self.knownType = TuyaCandidateDPKnownType(rawValue: rawType)
        self.declaredValueLength = declaredValueLength
    }
}

/// Exact accepted nearest-match evidence for one stock-app marker. Raw DP bytes
/// are preserved; no engineering unit or numeric scale is assigned here.
public struct TuyaCandidateDPMarkerHit: Equatable, Sendable {
    public let markerIndex: Int
    public let markerReceiptUptimeNanoseconds: UInt64
    public let displayedReference: String
    public let observationIndex: Int
    public let observationFirstReceiptUptimeNanoseconds: UInt64
    public let observationLastReceiptUptimeNanoseconds: UInt64
    public let temporalDistanceNanoseconds: UInt64
    public let headerByteOffset: Int
    public let valueByteOffset: Int
    public let endByteOffsetExclusive: Int
    public let valueBytes: [UInt8]

    fileprivate init(
        markerIndex: Int,
        marker: TuyaCandidateDPStockAppMarker,
        occurrence: CandidateOccurrence,
        temporalDistanceNanoseconds: UInt64
    ) {
        self.markerIndex = markerIndex
        self.markerReceiptUptimeNanoseconds = marker.receiptUptimeNanoseconds
        self.displayedReference = marker.displayedReference
        self.observationIndex = occurrence.observationIndex
        self.observationFirstReceiptUptimeNanoseconds = occurrence.firstReceiptUptimeNanoseconds
        self.observationLastReceiptUptimeNanoseconds = occurrence.lastReceiptUptimeNanoseconds
        self.temporalDistanceNanoseconds = temporalDistanceNanoseconds
        self.headerByteOffset = occurrence.headerByteOffset
        self.valueByteOffset = occurrence.valueByteOffset
        self.endByteOffsetExclusive = occurrence.endByteOffsetExclusive
        self.valueBytes = occurrence.valueBytes
    }
}

/// Repeatability evidence for one structural DP candidate.
///
/// Pair counts compare exact stock-app reference strings with exact raw DP value
/// bytes. They are intentionally not a confidence score and never prove the
/// candidate carries the named field. For example, a coincidentally changing DP
/// can score well and still be unrelated to battery/voltage/current/power.
public struct TuyaCandidateDPMarkerCandidateEvidence: Equatable, Sendable {
    public let candidate: TuyaCandidateDPCorrelationCandidate
    public let matchedMarkerCount: Int
    public let ambiguousNearestMarkerIndices: [Int]
    public let distinctDisplayedReferenceCount: Int
    public let distinctRawValueCount: Int
    public let sameReferencePairCount: UInt64
    public let sameReferenceSameRawValuePairCount: UInt64
    public let differentReferencePairCount: UInt64
    public let differentReferenceDifferentRawValuePairCount: UInt64
    public let maximumTemporalDistanceNanoseconds: UInt64?
    public let hits: [TuyaCandidateDPMarkerHit]

    fileprivate init(
        candidate: TuyaCandidateDPCorrelationCandidate,
        ambiguousNearestMarkerIndices: [Int],
        hits: [TuyaCandidateDPMarkerHit]
    ) {
        var sameReferencePairCount: UInt64 = 0
        var sameReferenceSameRawValuePairCount: UInt64 = 0
        var differentReferencePairCount: UInt64 = 0
        var differentReferenceDifferentRawValuePairCount: UInt64 = 0

        if hits.count > 1 {
            for firstIndex in 0..<(hits.count - 1) {
                for secondIndex in (firstIndex + 1)..<hits.count {
                    let first = hits[firstIndex]
                    let second = hits[secondIndex]
                    if first.displayedReference == second.displayedReference {
                        sameReferencePairCount += 1
                        if first.valueBytes == second.valueBytes {
                            sameReferenceSameRawValuePairCount += 1
                        }
                    } else {
                        differentReferencePairCount += 1
                        if first.valueBytes != second.valueBytes {
                            differentReferenceDifferentRawValuePairCount += 1
                        }
                    }
                }
            }
        }

        self.candidate = candidate
        self.matchedMarkerCount = hits.count
        self.ambiguousNearestMarkerIndices = ambiguousNearestMarkerIndices
        self.distinctDisplayedReferenceCount = Set(hits.map(\.displayedReference)).count
        self.distinctRawValueCount = Set(hits.map { Data($0.valueBytes) }).count
        self.sameReferencePairCount = sameReferencePairCount
        self.sameReferenceSameRawValuePairCount = sameReferenceSameRawValuePairCount
        self.differentReferencePairCount = differentReferencePairCount
        self.differentReferenceDifferentRawValuePairCount = differentReferenceDifferentRawValuePairCount
        self.maximumTemporalDistanceNanoseconds = hits.map(\.temporalDistanceNanoseconds).max()
        self.hits = hits
    }
}

/// Deterministically ranked correlation report for one exact research scope.
/// Rank is prioritization evidence only; index zero is not a decoded ES80 field.
public struct TuyaCandidateDPMarkerCorrelationReport: Equatable, Sendable {
    public let scope: TuyaCandidateDPMarkerCorrelationScope
    public let markerCount: Int
    public let observationCount: Int
    public let candidateOccurrenceCount: Int
    public let candidates: [TuyaCandidateDPMarkerCandidateEvidence]

    fileprivate init(
        scope: TuyaCandidateDPMarkerCorrelationScope,
        markerCount: Int,
        observationCount: Int,
        candidateOccurrenceCount: Int,
        candidates: [TuyaCandidateDPMarkerCandidateEvidence]
    ) {
        self.scope = scope
        self.markerCount = markerCount
        self.observationCount = observationCount
        self.candidateOccurrenceCount = candidateOccurrenceCount
        self.candidates = candidates
    }
}

public enum TuyaCandidateDPMarkerCorrelator {
    /// Correlates exact-reference stock-app markers against DP records observed in
    /// one already-selected stream/continuity/length-width scope.
    ///
    /// For each marker/candidate pair, at most one support hit is counted. If two
    /// equally-near candidate occurrences disagree in raw bytes, that marker is
    /// recorded as ambiguous instead of choosing the value that best fits the
    /// desired stock-app field. High callback rate therefore cannot manufacture
    /// extra marker support.
    public static func analyze(
        scope: TuyaCandidateDPMarkerCorrelationScope,
        markers: [TuyaCandidateDPStockAppMarker],
        observations: [TuyaCandidateDPMessageObservation],
        policy: TuyaCandidateDPMarkerCorrelationPolicy
    ) throws -> TuyaCandidateDPMarkerCorrelationReport {
        guard markers.count <= policy.maximumMarkerCount else {
            throw TuyaCandidateDPMarkerCorrelationError.markerCountExceedsPolicy(
                maximum: policy.maximumMarkerCount
            )
        }
        guard observations.count <= policy.maximumObservationCount else {
            throw TuyaCandidateDPMarkerCorrelationError.observationCountExceedsPolicy(
                maximum: policy.maximumObservationCount
            )
        }

        try validateMarkerChronology(markers)
        try validateObservationChronologyAndScope(observations, scope: scope)

        var occurrenceCount = 0
        var occurrencesByCandidate: [CandidateKey: [CandidateOccurrence]] = [:]

        for (observationIndex, observation) in observations.enumerated() {
            for record in observation.payload.records {
                occurrenceCount += 1
                guard occurrenceCount <= policy.maximumCandidateOccurrenceCount else {
                    throw TuyaCandidateDPMarkerCorrelationError.candidateOccurrenceCountExceedsPolicy(
                        maximum: policy.maximumCandidateOccurrenceCount
                    )
                }

                let key = CandidateKey(record: record)
                occurrencesByCandidate[key, default: []].append(
                    CandidateOccurrence(
                        observationIndex: observationIndex,
                        firstReceiptUptimeNanoseconds: observation.firstReceiptUptimeNanoseconds,
                        lastReceiptUptimeNanoseconds: observation.lastReceiptUptimeNanoseconds,
                        headerByteOffset: record.headerByteOffset,
                        valueByteOffset: record.valueByteOffset,
                        endByteOffsetExclusive: record.endByteOffsetExclusive,
                        valueBytes: record.valueBytes
                    )
                )
            }
        }

        var candidateEvidence: [TuyaCandidateDPMarkerCandidateEvidence] = []
        candidateEvidence.reserveCapacity(occurrencesByCandidate.count)

        for (key, occurrences) in occurrencesByCandidate {
            var hits: [TuyaCandidateDPMarkerHit] = []
            var ambiguousMarkerIndices: [Int] = []

            for (markerIndex, marker) in markers.enumerated() {
                let nearest = nearestOccurrences(
                    to: marker.receiptUptimeNanoseconds,
                    occurrences: occurrences,
                    maximumDistanceNanoseconds: policy.maximumMarkerDistanceNanoseconds
                )
                guard let minimumDistance = nearest.minimumDistanceNanoseconds,
                      !nearest.occurrences.isEmpty else {
                    continue
                }

                let firstValue = nearest.occurrences[0].valueBytes
                if nearest.occurrences.dropFirst().contains(where: { $0.valueBytes != firstValue }) {
                    ambiguousMarkerIndices.append(markerIndex)
                    continue
                }

                let selected = nearest.occurrences.min(by: deterministicOccurrenceOrder)!
                hits.append(
                    TuyaCandidateDPMarkerHit(
                        markerIndex: markerIndex,
                        marker: marker,
                        occurrence: selected,
                        temporalDistanceNanoseconds: minimumDistance
                    )
                )
            }

            guard !hits.isEmpty || !ambiguousMarkerIndices.isEmpty else {
                continue
            }

            candidateEvidence.append(
                TuyaCandidateDPMarkerCandidateEvidence(
                    candidate: TuyaCandidateDPCorrelationCandidate(
                        identifier: key.identifier,
                        rawType: key.rawType,
                        declaredValueLength: key.declaredValueLength
                    ),
                    ambiguousNearestMarkerIndices: ambiguousMarkerIndices,
                    hits: hits
                )
            )
        }

        candidateEvidence.sort(by: evidenceRanksBefore)

        return TuyaCandidateDPMarkerCorrelationReport(
            scope: scope,
            markerCount: markers.count,
            observationCount: observations.count,
            candidateOccurrenceCount: occurrenceCount,
            candidates: candidateEvidence
        )
    }

    private static func validateMarkerChronology(
        _ markers: [TuyaCandidateDPStockAppMarker]
    ) throws {
        guard markers.count > 1 else { return }
        for currentIndex in 1..<markers.count {
            let previousIndex = currentIndex - 1
            guard markers[currentIndex].receiptUptimeNanoseconds
                    > markers[previousIndex].receiptUptimeNanoseconds else {
                throw TuyaCandidateDPMarkerCorrelationError.nonMonotonicMarkerChronology(
                    previousIndex: previousIndex,
                    currentIndex: currentIndex
                )
            }
        }
    }

    private static func validateObservationChronologyAndScope(
        _ observations: [TuyaCandidateDPMessageObservation],
        scope: TuyaCandidateDPMarkerCorrelationScope
    ) throws {
        for (index, observation) in observations.enumerated() {
            guard observation.firstReceiptUptimeNanoseconds
                    <= observation.lastReceiptUptimeNanoseconds else {
                throw TuyaCandidateDPMarkerCorrelationError.invalidObservationReceiptInterval(index: index)
            }
            guard observation.streamIdentity == scope.streamIdentity else {
                throw TuyaCandidateDPMarkerCorrelationError.observationStreamIdentityMismatch(index: index)
            }
            guard observation.continuityGeneration == scope.continuityGeneration else {
                throw TuyaCandidateDPMarkerCorrelationError.observationContinuityGenerationMismatch(index: index)
            }
            guard observation.payload.dataLengthWidth == scope.dataLengthWidth else {
                throw TuyaCandidateDPMarkerCorrelationError.observationLengthWidthMismatch(index: index)
            }

            if index > 0 {
                let previousIndex = index - 1
                guard observation.firstReceiptUptimeNanoseconds
                        > observations[previousIndex].lastReceiptUptimeNanoseconds else {
                    throw TuyaCandidateDPMarkerCorrelationError.nonMonotonicObservationChronology(
                        previousIndex: previousIndex,
                        currentIndex: index
                    )
                }
            }
        }
    }

    private static func nearestOccurrences(
        to markerUptimeNanoseconds: UInt64,
        occurrences: [CandidateOccurrence],
        maximumDistanceNanoseconds: UInt64
    ) -> NearestOccurrences {
        var minimumDistance: UInt64?
        var nearest: [CandidateOccurrence] = []

        for occurrence in occurrences {
            let distance = temporalDistance(
                markerUptimeNanoseconds,
                toClosedIntervalFrom: occurrence.firstReceiptUptimeNanoseconds,
                through: occurrence.lastReceiptUptimeNanoseconds
            )
            guard distance <= maximumDistanceNanoseconds else { continue }

            if let minimumDistance {
                if distance < minimumDistance {
                    nearest = [occurrence]
                    // Shadowing keeps the branch concise but cannot mutate the
                    // outer binding. Reassign explicitly below.
                    return replacingNearestIfNeeded(
                        markerUptimeNanoseconds: markerUptimeNanoseconds,
                        occurrences: occurrences,
                        maximumDistanceNanoseconds: maximumDistanceNanoseconds
                    )
                } else if distance == minimumDistance {
                    nearest.append(occurrence)
                }
            } else {
                minimumDistance = distance
                nearest = [occurrence]
            }
        }

        return NearestOccurrences(
            minimumDistanceNanoseconds: minimumDistance,
            occurrences: nearest
        )
    }

    /// Separate implementation avoids subtle optional-shadow mutation mistakes
    /// while keeping nearest-match selection deterministic and allocation-bounded.
    private static func replacingNearestIfNeeded(
        markerUptimeNanoseconds: UInt64,
        occurrences: [CandidateOccurrence],
        maximumDistanceNanoseconds: UInt64
    ) -> NearestOccurrences {
        var bestDistance: UInt64?
        var bestOccurrences: [CandidateOccurrence] = []

        for occurrence in occurrences {
            let distance = temporalDistance(
                markerUptimeNanoseconds,
                toClosedIntervalFrom: occurrence.firstReceiptUptimeNanoseconds,
                through: occurrence.lastReceiptUptimeNanoseconds
            )
            guard distance <= maximumDistanceNanoseconds else { continue }

            switch bestDistance {
            case nil:
                bestDistance = distance
                bestOccurrences = [occurrence]
            case let current? where distance < current:
                bestDistance = distance
                bestOccurrences = [occurrence]
            case let current? where distance == current:
                bestOccurrences.append(occurrence)
            default:
                break
            }
        }

        return NearestOccurrences(
            minimumDistanceNanoseconds: bestDistance,
            occurrences: bestOccurrences
        )
    }

    private static func temporalDistance(
        _ marker: UInt64,
        toClosedIntervalFrom first: UInt64,
        through last: UInt64
    ) -> UInt64 {
        if marker < first {
            return first - marker
        }
        if marker > last {
            return marker - last
        }
        return 0
    }

    private static func deterministicOccurrenceOrder(
        _ lhs: CandidateOccurrence,
        _ rhs: CandidateOccurrence
    ) -> Bool {
        if lhs.observationIndex != rhs.observationIndex {
            return lhs.observationIndex < rhs.observationIndex
        }
        if lhs.headerByteOffset != rhs.headerByteOffset {
            return lhs.headerByteOffset < rhs.headerByteOffset
        }
        if lhs.valueByteOffset != rhs.valueByteOffset {
            return lhs.valueByteOffset < rhs.valueByteOffset
        }
        return lhs.endByteOffsetExclusive < rhs.endByteOffsetExclusive
    }

    private static func evidenceRanksBefore(
        _ lhs: TuyaCandidateDPMarkerCandidateEvidence,
        _ rhs: TuyaCandidateDPMarkerCandidateEvidence
    ) -> Bool {
        if lhs.matchedMarkerCount != rhs.matchedMarkerCount {
            return lhs.matchedMarkerCount > rhs.matchedMarkerCount
        }
        if lhs.sameReferenceSameRawValuePairCount != rhs.sameReferenceSameRawValuePairCount {
            return lhs.sameReferenceSameRawValuePairCount > rhs.sameReferenceSameRawValuePairCount
        }
        if lhs.differentReferenceDifferentRawValuePairCount != rhs.differentReferenceDifferentRawValuePairCount {
            return lhs.differentReferenceDifferentRawValuePairCount > rhs.differentReferenceDifferentRawValuePairCount
        }
        if lhs.ambiguousNearestMarkerIndices.count != rhs.ambiguousNearestMarkerIndices.count {
            return lhs.ambiguousNearestMarkerIndices.count < rhs.ambiguousNearestMarkerIndices.count
        }

        switch (lhs.maximumTemporalDistanceNanoseconds, rhs.maximumTemporalDistanceNanoseconds) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.candidate.identifier != rhs.candidate.identifier {
            return lhs.candidate.identifier < rhs.candidate.identifier
        }
        if lhs.candidate.rawType != rhs.candidate.rawType {
            return lhs.candidate.rawType < rhs.candidate.rawType
        }
        return lhs.candidate.declaredValueLength < rhs.candidate.declaredValueLength
    }
}

private struct CandidateKey: Hashable {
    let identifier: UInt8
    let rawType: UInt8
    let declaredValueLength: Int

    init(record: TuyaCandidateDPRecord) {
        self.identifier = record.identifier
        self.rawType = record.rawType
        self.declaredValueLength = record.declaredValueLength
    }
}

private struct CandidateOccurrence: Equatable, Sendable {
    let observationIndex: Int
    let firstReceiptUptimeNanoseconds: UInt64
    let lastReceiptUptimeNanoseconds: UInt64
    let headerByteOffset: Int
    let valueByteOffset: Int
    let endByteOffsetExclusive: Int
    let valueBytes: [UInt8]
}

private struct NearestOccurrences {
    let minimumDistanceNanoseconds: UInt64?
    let occurrences: [CandidateOccurrence]
}
