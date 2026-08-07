import Foundation

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

/// One deliberately narrow correlation scope. Mixing streams, continuity
/// generations, or DP length-width hypotheses fails closed instead of improving
/// a candidate by combining incompatible evidence.
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

/// Human-observed stock-app reference placed on the same monotonic capture clock.
/// The displayed text is preserved exactly. No unit, locale, precision, or scale
/// normalization occurs in this layer.
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

/// Caller-owned resource and timing bounds. These values are analysis policy,
/// never AOVOPRO ES80 protocol defaults.
public struct TuyaCandidateDPMarkerCorrelationPolicy: Equatable, Sendable {
    /// Maximum absolute distance from a marker to the accepted completion receipt
    /// of a candidate message. The message's earlier fragment interval remains
    /// provenance only and is never treated as if the completed DP value existed
    /// throughout that interval.
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

/// A #238 structural DP parse caller-bound to the exact #219 reassembled-message
/// provenance from which legitimate plaintext was derived.
///
/// This association is explicit rather than magical: this layer performs no
/// decryption/authentication and cannot prove caller-supplied plaintext belongs
/// to the encrypted message. It preserves the source/timing boundary so later
/// correlation does not erase it.
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
        streamIdentity = reassembledMessage.streamIdentity
        continuityGeneration = reassembledMessage.continuityGeneration
        firstReceiptUptimeNanoseconds = reassembledMessage.firstReceiptUptimeNanoseconds
        lastReceiptUptimeNanoseconds = reassembledMessage.lastReceiptUptimeNanoseconds
        payload = parsedPayload
    }
}

/// Same numeric DP ID is not merged across a different raw type or declared
/// value width. The report's scope separately preserves the DP framing width.
public struct TuyaCandidateDPCorrelationCandidate: Equatable, Sendable {
    public let identifier: UInt8
    public let rawType: UInt8
    public let knownType: TuyaCandidateDPKnownType?
    public let declaredValueLength: Int

    fileprivate init(key: CandidateKey) {
        identifier = key.identifier
        rawType = key.rawType
        knownType = TuyaCandidateDPKnownType(rawValue: key.rawType)
        declaredValueLength = key.declaredValueLength
    }
}

public enum TuyaCandidateDPMarkerTemporalRelation: Equatable, Sendable {
    case messageBeforeMarker
    case sameReceipt
    case messageAfterMarker
}

/// One unambiguous nearest raw-value match for one stock-app marker.
public struct TuyaCandidateDPMarkerHit: Equatable, Sendable {
    public let markerIndex: Int
    public let markerReceiptUptimeNanoseconds: UInt64
    public let displayedReference: String
    public let observationIndex: Int
    public let observationFirstReceiptUptimeNanoseconds: UInt64
    public let observationLastReceiptUptimeNanoseconds: UInt64
    public let temporalDistanceNanoseconds: UInt64
    public let temporalRelation: TuyaCandidateDPMarkerTemporalRelation
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
        markerReceiptUptimeNanoseconds = marker.receiptUptimeNanoseconds
        displayedReference = marker.displayedReference
        observationIndex = occurrence.observationIndex
        observationFirstReceiptUptimeNanoseconds = occurrence.firstReceiptUptimeNanoseconds
        observationLastReceiptUptimeNanoseconds = occurrence.lastReceiptUptimeNanoseconds
        self.temporalDistanceNanoseconds = temporalDistanceNanoseconds
        if occurrence.lastReceiptUptimeNanoseconds < marker.receiptUptimeNanoseconds {
            temporalRelation = .messageBeforeMarker
        } else if occurrence.lastReceiptUptimeNanoseconds == marker.receiptUptimeNanoseconds {
            temporalRelation = .sameReceipt
        } else {
            temporalRelation = .messageAfterMarker
        }
        headerByteOffset = occurrence.headerByteOffset
        valueByteOffset = occurrence.valueByteOffset
        endByteOffsetExclusive = occurrence.endByteOffsetExclusive
        valueBytes = occurrence.valueBytes
    }
}

/// Equality-pattern evidence only. Pair counts compare exact displayed reference
/// strings against exact raw DP bytes; they are not a confidence score and never
/// prove that this candidate carries the named stock-app field.
public struct TuyaCandidateDPMarkerCandidateEvidence: Equatable, Sendable {
    public let candidate: TuyaCandidateDPCorrelationCandidate
    public let matchedMarkerCount: Int
    /// Marker indices rejected because equally-near observations disagreed in
    /// raw bytes for this candidate.
    public let ambiguousNearestMarkerIndices: [Int]
    /// Marker indices that could only reuse a candidate message already proposed
    /// for another marker. One physical candidate message may support at most one
    /// human marker in repeated-evidence counts.
    public let sharedObservationMarkerIndices: [Int]
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
        sharedObservationMarkerIndices: [Int],
        hits: [TuyaCandidateDPMarkerHit]
    ) {
        var sameReferencePairs: UInt64 = 0
        var sameReferenceSameRawPairs: UInt64 = 0
        var differentReferencePairs: UInt64 = 0
        var differentReferenceDifferentRawPairs: UInt64 = 0

        if hits.count > 1 {
            for firstIndex in 0..<(hits.count - 1) {
                for secondIndex in (firstIndex + 1)..<hits.count {
                    let first = hits[firstIndex]
                    let second = hits[secondIndex]
                    if first.displayedReference == second.displayedReference {
                        sameReferencePairs += 1
                        if first.valueBytes == second.valueBytes {
                            sameReferenceSameRawPairs += 1
                        }
                    } else {
                        differentReferencePairs += 1
                        if first.valueBytes != second.valueBytes {
                            differentReferenceDifferentRawPairs += 1
                        }
                    }
                }
            }
        }

        self.candidate = candidate
        matchedMarkerCount = hits.count
        self.ambiguousNearestMarkerIndices = ambiguousNearestMarkerIndices
        self.sharedObservationMarkerIndices = sharedObservationMarkerIndices
        distinctDisplayedReferenceCount = Set(hits.map(\.displayedReference)).count
        distinctRawValueCount = Set(hits.map { Data($0.valueBytes) }).count
        sameReferencePairCount = sameReferencePairs
        sameReferenceSameRawValuePairCount = sameReferenceSameRawPairs
        differentReferencePairCount = differentReferencePairs
        differentReferenceDifferentRawValuePairCount = differentReferenceDifferentRawPairs
        maximumTemporalDistanceNanoseconds = hits.map(\.temporalDistanceNanoseconds).max()
        self.hits = hits
    }
}

/// Deterministically ranked research-prioritization evidence. Candidate order is
/// useful for deciding what to inspect next; it is never a decoded-field claim.
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
    /// A high-rate candidate receives at most one support hit per human marker,
    /// and one physical candidate message can support at most one human marker.
    /// Equally-near occurrences that disagree in raw bytes are marked ambiguous
    /// rather than choosing whichever value best matches a desired hypothesis.
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

        try validateMarkers(markers)
        try validateObservations(observations, scope: scope)

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
                occurrencesByCandidate[CandidateKey(record: record), default: []].append(
                    CandidateOccurrence(
                        observationIndex: observationIndex,
                        observation: observation,
                        record: record
                    )
                )
            }
        }

        var evidence: [TuyaCandidateDPMarkerCandidateEvidence] = []
        evidence.reserveCapacity(occurrencesByCandidate.count)

        for (key, occurrences) in occurrencesByCandidate {
            var proposals: [MarkerHitProposal] = []
            var ambiguousIndices: [Int] = []

            for (markerIndex, marker) in markers.enumerated() {
                let nearest = nearestOccurrences(
                    markerUptimeNanoseconds: marker.receiptUptimeNanoseconds,
                    occurrences: occurrences,
                    maximumDistanceNanoseconds: policy.maximumMarkerDistanceNanoseconds
                )
                guard let distance = nearest.minimumDistanceNanoseconds,
                      let first = nearest.occurrences.first else {
                    continue
                }

                if nearest.occurrences.dropFirst().contains(where: { $0.valueBytes != first.valueBytes }) {
                    ambiguousIndices.append(markerIndex)
                    continue
                }

                proposals.append(
                    MarkerHitProposal(
                        markerIndex: markerIndex,
                        marker: marker,
                        occurrence: nearest.occurrences.min(by: deterministicOccurrenceOrder) ?? first,
                        temporalDistanceNanoseconds: distance
                    )
                )
            }

            let resolved = resolveSharedObservations(proposals)
            guard !resolved.hits.isEmpty
                    || !ambiguousIndices.isEmpty
                    || !resolved.sharedObservationMarkerIndices.isEmpty else {
                continue
            }
            evidence.append(
                TuyaCandidateDPMarkerCandidateEvidence(
                    candidate: TuyaCandidateDPCorrelationCandidate(key: key),
                    ambiguousNearestMarkerIndices: ambiguousIndices,
                    sharedObservationMarkerIndices: resolved.sharedObservationMarkerIndices,
                    hits: resolved.hits
                )
            )
        }

        evidence.sort(by: evidenceRanksBefore)
        return TuyaCandidateDPMarkerCorrelationReport(
            scope: scope,
            markerCount: markers.count,
            observationCount: observations.count,
            candidateOccurrenceCount: occurrenceCount,
            candidates: evidence
        )
    }

    private static func resolveSharedObservations(
        _ proposals: [MarkerHitProposal]
    ) -> ResolvedMarkerHits {
        var byObservation: [Int: [MarkerHitProposal]] = [:]
        for proposal in proposals {
            byObservation[proposal.occurrence.observationIndex, default: []].append(proposal)
        }

        var hits: [TuyaCandidateDPMarkerHit] = []
        var sharedMarkerIndices: [Int] = []

        for proposalsForObservation in byObservation.values {
            guard proposalsForObservation.count > 1 else {
                if let proposal = proposalsForObservation.first {
                    hits.append(proposal.makeHit())
                }
                continue
            }

            let minimumDistance = proposalsForObservation
                .map(\.temporalDistanceNanoseconds)
                .min()!
            let closest = proposalsForObservation.filter {
                $0.temporalDistanceNanoseconds == minimumDistance
            }

            if closest.count == 1, let winner = closest.first {
                hits.append(winner.makeHit())
                sharedMarkerIndices.append(
                    contentsOf: proposalsForObservation.compactMap { proposal in
                        proposal.markerIndex == winner.markerIndex ? nil : proposal.markerIndex
                    }
                )
            } else {
                sharedMarkerIndices.append(
                    contentsOf: proposalsForObservation.map(\.markerIndex)
                )
            }
        }

        hits.sort { $0.markerIndex < $1.markerIndex }
        sharedMarkerIndices.sort()
        return ResolvedMarkerHits(
            hits: hits,
            sharedObservationMarkerIndices: sharedMarkerIndices
        )
    }

    private static func validateMarkers(_ markers: [TuyaCandidateDPStockAppMarker]) throws {
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

    private static func validateObservations(
        _ observations: [TuyaCandidateDPMessageObservation],
        scope: TuyaCandidateDPMarkerCorrelationScope
    ) throws {
        for (index, observation) in observations.enumerated() {
            guard observation.firstReceiptUptimeNanoseconds <= observation.lastReceiptUptimeNanoseconds else {
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
        markerUptimeNanoseconds: UInt64,
        occurrences: [CandidateOccurrence],
        maximumDistanceNanoseconds: UInt64
    ) -> NearestOccurrences {
        var minimumDistance: UInt64?
        var nearest: [CandidateOccurrence] = []

        for occurrence in occurrences {
            let distance = temporalDistance(
                markerUptimeNanoseconds,
                acceptedReceiptUptimeNanoseconds: occurrence.lastReceiptUptimeNanoseconds
            )
            guard distance <= maximumDistanceNanoseconds else { continue }

            if minimumDistance == nil || distance < minimumDistance! {
                minimumDistance = distance
                nearest = [occurrence]
            } else if distance == minimumDistance {
                nearest.append(occurrence)
            }
        }
        return NearestOccurrences(
            minimumDistanceNanoseconds: minimumDistance,
            occurrences: nearest
        )
    }

    private static func temporalDistance(
        _ marker: UInt64,
        acceptedReceiptUptimeNanoseconds: UInt64
    ) -> UInt64 {
        if marker >= acceptedReceiptUptimeNanoseconds {
            return marker - acceptedReceiptUptimeNanoseconds
        }
        return acceptedReceiptUptimeNanoseconds - marker
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
        let lhsAmbiguityCount = lhs.ambiguousNearestMarkerIndices.count
            + lhs.sharedObservationMarkerIndices.count
        let rhsAmbiguityCount = rhs.ambiguousNearestMarkerIndices.count
            + rhs.sharedObservationMarkerIndices.count
        if lhsAmbiguityCount != rhsAmbiguityCount {
            return lhsAmbiguityCount < rhsAmbiguityCount
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
        identifier = record.identifier
        rawType = record.rawType
        declaredValueLength = record.declaredValueLength
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

    init(
        observationIndex: Int,
        observation: TuyaCandidateDPMessageObservation,
        record: TuyaCandidateDPRecord
    ) {
        self.observationIndex = observationIndex
        firstReceiptUptimeNanoseconds = observation.firstReceiptUptimeNanoseconds
        lastReceiptUptimeNanoseconds = observation.lastReceiptUptimeNanoseconds
        headerByteOffset = record.headerByteOffset
        valueByteOffset = record.valueByteOffset
        endByteOffsetExclusive = record.endByteOffsetExclusive
        valueBytes = record.valueBytes
    }
}

private struct NearestOccurrences {
    let minimumDistanceNanoseconds: UInt64?
    let occurrences: [CandidateOccurrence]
}

private struct MarkerHitProposal {
    let markerIndex: Int
    let marker: TuyaCandidateDPStockAppMarker
    let occurrence: CandidateOccurrence
    let temporalDistanceNanoseconds: UInt64

    func makeHit() -> TuyaCandidateDPMarkerHit {
        TuyaCandidateDPMarkerHit(
            markerIndex: markerIndex,
            marker: marker,
            occurrence: occurrence,
            temporalDistanceNanoseconds: temporalDistanceNanoseconds
        )
    }
}

private struct ResolvedMarkerHits {
    let hits: [TuyaCandidateDPMarkerHit]
    let sharedObservationMarkerIndices: [Int]
}
