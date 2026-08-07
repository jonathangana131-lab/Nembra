import Foundation

/// Fail-closed validation for research evidence assembled across independently
/// labelled capture sessions.
///
/// This layer is descriptive only. It does not establish that the caller's
/// subject/session identifiers prove physical independence or a stable scooter
/// identity, and it never promotes a DP candidate or transform into verified
/// AOVOPRO ES80 telemetry semantics.
public enum TuyaCandidateDPCrossSessionConsistencyError: Error, Equatable, Sendable {
    case emptySubjectIdentifier
    case emptySessionIdentifier
    case invalidMaximumSessionCount
    case sessionCountExceedsPolicy(maximum: Int)
    case insufficientSessionCount(minimum: Int)
    case duplicateSessionIdentifier(String)
    case duplicateSessionEvidence(firstIndex: Int, secondIndex: Int)
    case fieldLabelMismatch(index: Int)
    case streamIdentityMismatch(index: Int)
    case dataLengthWidthMismatch(index: Int)
    case candidateMismatch(index: Int)
    case absoluteToleranceMismatch(index: Int)
    case hypothesisNotFound(sessionIndex: Int)
    case hypothesisAmbiguous(sessionIndex: Int)
}

/// One caller-labelled capture-session report. The normalized session label is
/// experiment bookkeeping only; this type does not claim it came from a unique
/// process launch, physical ride, or physical scooter.
public struct TuyaCandidateDPCrossSessionObservation: Equatable, Sendable {
    public let sessionIdentifier: String
    public let report: TuyaCandidateDPNumericHypothesisReport

    public init(
        sessionIdentifier: String,
        report: TuyaCandidateDPNumericHypothesisReport
    ) throws {
        let normalizedIdentifier = sessionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else {
            throw TuyaCandidateDPCrossSessionConsistencyError.emptySessionIdentifier
        }
        self.sessionIdentifier = normalizedIdentifier
        self.report = report
    }
}

/// Caller-owned work limit. It is analysis policy, never a physical ES80
/// verification threshold. A non-empty cross-session report requires at least two
/// sessions, so the maximum itself cannot be configured below that invariant.
public struct TuyaCandidateDPCrossSessionConsistencyPolicy: Equatable, Sendable {
    static let minimumSessionCount = 2

    public let maximumSessionCount: Int

    public init(maximumSessionCount: Int) throws {
        guard maximumSessionCount >= Self.minimumSessionCount else {
            throw TuyaCandidateDPCrossSessionConsistencyError.invalidMaximumSessionCount
        }
        self.maximumSessionCount = maximumSessionCount
    }
}

/// Complete retained evidence from one independently labelled session.
/// Missing/ambiguous/shared parent references remain explicit beside evaluable
/// samples so aggregate counts cannot erase why evidence was unavailable.
public struct TuyaCandidateDPCrossSessionSessionEvidence: Equatable, Sendable {
    public let sessionIdentifier: String
    public let continuityGeneration: UInt64
    public let candidateIndex: Int
    public let numericReferenceCount: Int
    /// Complete canonical parent reference set, including values whose markers
    /// later become unused/ambiguous/shared exclusions rather than samples.
    public let numericReferences: [TuyaCandidateDPNumericReference]
    public let unusedReferenceMarkerIndices: [Int]
    public let ambiguousReferenceMarkerIndices: [Int]
    public let sharedObservationReferenceMarkerIndices: [Int]
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
        observation: TuyaCandidateDPCrossSessionObservation,
        evidence: TuyaCandidateDPNumericHypothesisEvidence
    ) {
        sessionIdentifier = observation.sessionIdentifier
        continuityGeneration = observation.report.correlationScope.continuityGeneration
        candidateIndex = observation.report.candidateIndex
        numericReferenceCount = observation.report.numericReferenceCount
        numericReferences = observation.report.numericReferences
        unusedReferenceMarkerIndices = observation.report.unusedReferenceMarkerIndices
        ambiguousReferenceMarkerIndices = observation.report.ambiguousReferenceMarkerIndices
        sharedObservationReferenceMarkerIndices = observation.report.sharedObservationReferenceMarkerIndices
        distinctEvaluableReferenceValueCount = evidence.distinctEvaluableReferenceValueCount
        samples = evidence.samples
        meanAbsoluteError = evidence.meanAbsoluteError
        maximumAbsoluteError = evidence.maximumAbsoluteError
    }
}

/// Cross-session research summary for one exact stream/candidate/hypothesis and
/// one exact caller-owned numeric comparison tolerance.
///
/// Counts intentionally avoid terms such as confidence, verified, authoritative,
/// field mapping, or physical identity. Multiple sessions can strengthen research
/// prioritization while still being insufficient to establish protocol truth.
public struct TuyaCandidateDPCrossSessionConsistencyReport: Equatable, Sendable {
    /// Caller-supplied experiment grouping label after whitespace normalization.
    /// This is not a verified stable scooter identity and must never be silently
    /// reused as production vehicle identity.
    public let subjectIdentifier: String
    public let fieldLabel: String
    public let streamIdentity: TuyaCandidateValueStreamIdentity
    public let dataLengthWidth: TuyaCandidateDPDataLengthWidth
    public let candidate: TuyaCandidateDPCorrelationCandidate
    public let hypothesis: TuyaCandidateDPNumericTransformHypothesis
    /// Exact caller-owned display-space tolerance retained by the numeric parent.
    /// This is research policy, not protocol resolution or physical accuracy.
    public let absoluteTolerance: Double
    public let sessions: [TuyaCandidateDPCrossSessionSessionEvidence]
    /// Distinct caller reference values across complete retained reference sets,
    /// not only values that happened to produce evaluable samples.
    public let distinctNumericReferenceValueCount: Int

    public var sessionCount: Int { sessions.count }

    public var sessionsWithEvaluableEvidenceCount: Int {
        sessions.reduce(into: 0) { count, session in
            if session.evaluableReferenceCount > 0 { count += 1 }
        }
    }

    /// Number of independently labelled sessions containing at least one sample
    /// inside the exact common caller-owned tolerance. Descriptive only.
    public var sessionsWithInToleranceSupportCount: Int {
        sessions.reduce(into: 0) { count, session in
            if session.matchedWithinToleranceCount > 0 { count += 1 }
        }
    }

    /// Sessions where every evaluable sample is inside the exact common tolerance.
    /// This does not establish protocol confidence or field identity.
    public var sessionsWithAllEvaluableSamplesWithinToleranceCount: Int {
        sessions.reduce(into: 0) { count, session in
            guard session.evaluableReferenceCount > 0 else { return }
            if session.matchedWithinToleranceCount == session.evaluableReferenceCount {
                count += 1
            }
        }
    }

    public var totalEvaluableSampleCount: Int {
        sessions.reduce(0) { $0 + $1.evaluableReferenceCount }
    }

    public var totalMatchedWithinToleranceCount: Int {
        sessions.reduce(0) { $0 + $1.matchedWithinToleranceCount }
    }

    fileprivate init(
        subjectIdentifier: String,
        fieldLabel: String,
        streamIdentity: TuyaCandidateValueStreamIdentity,
        dataLengthWidth: TuyaCandidateDPDataLengthWidth,
        candidate: TuyaCandidateDPCorrelationCandidate,
        hypothesis: TuyaCandidateDPNumericTransformHypothesis,
        absoluteTolerance: Double,
        sessions: [TuyaCandidateDPCrossSessionSessionEvidence]
    ) {
        self.subjectIdentifier = subjectIdentifier
        self.fieldLabel = fieldLabel
        self.streamIdentity = streamIdentity
        self.dataLengthWidth = dataLengthWidth
        self.candidate = candidate
        self.hypothesis = hypothesis
        self.absoluteTolerance = absoluteTolerance
        self.sessions = sessions
        distinctNumericReferenceValueCount = Set(
            sessions.flatMap { session in
                session.numericReferences.map(\.value)
            }
        ).count
    }
}

public enum TuyaCandidateDPCrossSessionConsistencyAnalyzer {
    /// Aggregates one exact explicit numeric transform across at least two
    /// independently labelled session reports without weakening any parent truth
    /// boundary.
    ///
    /// Required sameness across inputs:
    /// - exact field label;
    /// - exact GATT value-stream identity;
    /// - exact DP length-width hypothesis;
    /// - exact DP structural candidate;
    /// - exact caller-supplied numeric transform;
    /// - exact caller-owned absolute comparison tolerance.
    ///
    /// Continuity generation may differ because the purpose of this layer is to
    /// compare distinct capture/continuity epochs. Physical/session independence
    /// itself remains caller-supplied provenance. Reuse of identical selected
    /// underlying evidence is rejected even if the surrounding numeric reports
    /// differ because of unrelated hypotheses, ranking, or a relabelled
    /// continuity generation with otherwise identical retained evidence.
    public static func analyze(
        subjectIdentifier: String,
        observations: [TuyaCandidateDPCrossSessionObservation],
        hypothesis: TuyaCandidateDPNumericTransformHypothesis,
        policy: TuyaCandidateDPCrossSessionConsistencyPolicy
    ) throws -> TuyaCandidateDPCrossSessionConsistencyReport? {
        let normalizedSubjectIdentifier = subjectIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSubjectIdentifier.isEmpty else {
            throw TuyaCandidateDPCrossSessionConsistencyError.emptySubjectIdentifier
        }
        guard observations.count <= policy.maximumSessionCount else {
            throw TuyaCandidateDPCrossSessionConsistencyError.sessionCountExceedsPolicy(
                maximum: policy.maximumSessionCount
            )
        }
        guard !observations.isEmpty else { return nil }
        guard observations.count >= TuyaCandidateDPCrossSessionConsistencyPolicy.minimumSessionCount else {
            throw TuyaCandidateDPCrossSessionConsistencyError.insufficientSessionCount(
                minimum: TuyaCandidateDPCrossSessionConsistencyPolicy.minimumSessionCount
            )
        }

        try validateSessionIdentifiers(observations)

        let first = observations[0]
        let referenceScope = first.report.correlationScope
        let referenceCandidate = first.report.candidate
        let referenceTolerance = first.report.absoluteTolerance
        var resolvedSessions: [(observation: TuyaCandidateDPCrossSessionObservation, evidence: TuyaCandidateDPNumericHypothesisEvidence)] = []
        resolvedSessions.reserveCapacity(observations.count)
        var sessionEvidence: [TuyaCandidateDPCrossSessionSessionEvidence] = []
        sessionEvidence.reserveCapacity(observations.count)

        for (index, observation) in observations.enumerated() {
            let scope = observation.report.correlationScope
            guard scope.fieldLabel == referenceScope.fieldLabel else {
                throw TuyaCandidateDPCrossSessionConsistencyError.fieldLabelMismatch(index: index)
            }
            guard scope.streamIdentity == referenceScope.streamIdentity else {
                throw TuyaCandidateDPCrossSessionConsistencyError.streamIdentityMismatch(index: index)
            }
            guard scope.dataLengthWidth == referenceScope.dataLengthWidth else {
                throw TuyaCandidateDPCrossSessionConsistencyError.dataLengthWidthMismatch(index: index)
            }
            guard observation.report.candidate == referenceCandidate else {
                throw TuyaCandidateDPCrossSessionConsistencyError.candidateMismatch(index: index)
            }
            guard observation.report.absoluteTolerance == referenceTolerance else {
                throw TuyaCandidateDPCrossSessionConsistencyError.absoluteToleranceMismatch(index: index)
            }

            let matchingEvidence = observation.report.evidence.filter { $0.hypothesis == hypothesis }
            guard !matchingEvidence.isEmpty else {
                throw TuyaCandidateDPCrossSessionConsistencyError.hypothesisNotFound(sessionIndex: index)
            }
            guard matchingEvidence.count == 1 else {
                throw TuyaCandidateDPCrossSessionConsistencyError.hypothesisAmbiguous(sessionIndex: index)
            }
            let selectedEvidence = matchingEvidence[0]

            for (previousIndex, previous) in resolvedSessions.enumerated()
            where sameUnderlyingEvidence(
                previous.observation,
                previous.evidence,
                observation,
                selectedEvidence
            ) {
                throw TuyaCandidateDPCrossSessionConsistencyError.duplicateSessionEvidence(
                    firstIndex: previousIndex,
                    secondIndex: index
                )
            }

            resolvedSessions.append((observation: observation, evidence: selectedEvidence))
            sessionEvidence.append(
                TuyaCandidateDPCrossSessionSessionEvidence(
                    observation: observation,
                    evidence: selectedEvidence
                )
            )
        }

        return TuyaCandidateDPCrossSessionConsistencyReport(
            subjectIdentifier: normalizedSubjectIdentifier,
            fieldLabel: referenceScope.fieldLabel,
            streamIdentity: referenceScope.streamIdentity,
            dataLengthWidth: referenceScope.dataLengthWidth,
            candidate: referenceCandidate,
            hypothesis: hypothesis,
            absoluteTolerance: referenceTolerance,
            sessions: sessionEvidence
        )
    }

    private static func validateSessionIdentifiers(
        _ observations: [TuyaCandidateDPCrossSessionObservation]
    ) throws {
        var sessionIdentifiers: Set<String> = []
        sessionIdentifiers.reserveCapacity(observations.count)

        for observation in observations {
            guard sessionIdentifiers.insert(observation.sessionIdentifier).inserted else {
                throw TuyaCandidateDPCrossSessionConsistencyError.duplicateSessionIdentifier(
                    observation.sessionIdentifier
                )
            }
        }
    }

    /// Detects reuse of the same selected research evidence even when a caller
    /// rebuilds the surrounding numeric report with additional unrelated
    /// hypotheses, ranking changes, or a changed continuity-generation label.
    /// Candidate index and continuity generation are intentionally excluded:
    /// ranking can move, and generation is retained provenance rather than proof
    /// that the underlying marker/message evidence is physically independent.
    /// Tolerance has already been proven identical at this point.
    private static func sameUnderlyingEvidence(
        _ lhsObservation: TuyaCandidateDPCrossSessionObservation,
        _ lhsEvidence: TuyaCandidateDPNumericHypothesisEvidence,
        _ rhsObservation: TuyaCandidateDPCrossSessionObservation,
        _ rhsEvidence: TuyaCandidateDPNumericHypothesisEvidence
    ) -> Bool {
        let lhsScope = lhsObservation.report.correlationScope
        let rhsScope = rhsObservation.report.correlationScope
        return lhsScope.fieldLabel == rhsScope.fieldLabel
            && lhsScope.streamIdentity == rhsScope.streamIdentity
            && lhsScope.dataLengthWidth == rhsScope.dataLengthWidth
            && lhsObservation.report.candidate == rhsObservation.report.candidate
            && lhsObservation.report.numericReferences == rhsObservation.report.numericReferences
            && lhsObservation.report.absoluteTolerance == rhsObservation.report.absoluteTolerance
            && lhsObservation.report.unusedReferenceMarkerIndices == rhsObservation.report.unusedReferenceMarkerIndices
            && lhsObservation.report.ambiguousReferenceMarkerIndices == rhsObservation.report.ambiguousReferenceMarkerIndices
            && lhsObservation.report.sharedObservationReferenceMarkerIndices == rhsObservation.report.sharedObservationReferenceMarkerIndices
            && lhsEvidence == rhsEvidence
    }
}
