public enum TuyaCandidateTranscriptBoundary: Equatable, Sendable {
    case streamIdentityChanged
    case continuityGenerationChanged
    case streamIdentityAndContinuityGenerationChanged
    /// Under the candidate framing hypothesis, packet index zero is an explicit
    /// new-message start. If it arrives while a prior candidate is incomplete on
    /// the same stream/generation, preserve the old candidate as truncated and
    /// let this exact observation start the new candidate instead of discarding it.
    case candidatePacketZeroRestart
}

/// Lossless analysis outcomes for an ordered capture transcript. Candidate
/// failures are retained as evidence instead of being silently skipped until a
/// parse succeeds. Observation indices refer to the caller's immutable input.
public enum TuyaCandidateTranscriptEvent: Equatable, Sendable {
    case completed(
        startObservationIndex: Int,
        endObservationIndex: Int,
        message: TuyaCandidateReassembledMessage
    )
    case rejectedCandidate(
        startObservationIndex: Int,
        lastAcceptedObservationIndex: Int?,
        failingObservationIndex: Int,
        error: TuyaCandidateOfflineAnalysisError
    )
    case incompleteAtBoundary(
        startObservationIndex: Int,
        lastAcceptedObservationIndex: Int,
        nextObservationIndex: Int,
        boundary: TuyaCandidateTranscriptBoundary
    )
    case incompleteAtEnd(
        startObservationIndex: Int,
        lastAcceptedObservationIndex: Int
    )
    case unexpectedAnalyzerFailure(failingObservationIndex: Int)
}

/// Batch adapter for immutable passive-capture value transcripts. It never
/// repairs, reorders, merges, or drops raw observations. Each completed message,
/// rejection, evidence boundary, and end-of-capture truncation remains explicit.
public enum TuyaCandidateTranscriptAnalyzer {
    public static func analyze(
        _ observations: [TuyaCandidateFragmentObservation],
        policy: TuyaCandidateFragmentReassemblyPolicy
    ) -> [TuyaCandidateTranscriptEvent] {
        var events: [TuyaCandidateTranscriptEvent] = []
        var reassembler: TuyaCandidateFragmentReassembler?
        var boundStreamIdentity: TuyaCandidateValueStreamIdentity?
        var boundContinuityGeneration: UInt64?
        var startObservationIndex: Int?
        var lastAcceptedObservationIndex: Int?

        for (index, observation) in observations.enumerated() {
            if let currentStreamIdentity = boundStreamIdentity,
               let currentContinuityGeneration = boundContinuityGeneration {
                let streamChanged = currentStreamIdentity != observation.streamIdentity
                let generationChanged = currentContinuityGeneration != observation.continuityGeneration

                if streamChanged || generationChanged {
                    if let startObservationIndex, let lastAcceptedObservationIndex {
                        let boundary: TuyaCandidateTranscriptBoundary
                        if streamChanged && generationChanged {
                            boundary = .streamIdentityAndContinuityGenerationChanged
                        } else if streamChanged {
                            boundary = .streamIdentityChanged
                        } else {
                            boundary = .continuityGenerationChanged
                        }
                        events.append(
                            .incompleteAtBoundary(
                                startObservationIndex: startObservationIndex,
                                lastAcceptedObservationIndex: lastAcceptedObservationIndex,
                                nextObservationIndex: index,
                                boundary: boundary
                            )
                        )
                    }
                    reassembler = nil
                    resetState(
                        streamIdentity: &boundStreamIdentity,
                        continuityGeneration: &boundContinuityGeneration,
                        startObservationIndex: &startObservationIndex,
                        lastAcceptedObservationIndex: &lastAcceptedObservationIndex
                    )
                }
            }

            // A packet-zero prefix is an explicit new-message marker in this
            // candidate framing family. When one appears while another candidate
            // is still open on the same exact stream/generation, the prior code
            // fed it to the old reassembler, rejected it as an unexpected index,
            // then discarded the very observation needed to start the next
            // message. Detect only the candidate packet index here; the fresh
            // reassembler below still validates the complete first-fragment
            // structure and can reject it normally without mutating raw evidence.
            if reassembler != nil,
               beginsWithCandidatePacketZero(observation),
               let priorStartObservationIndex = startObservationIndex,
               let priorLastAcceptedObservationIndex = lastAcceptedObservationIndex {
                events.append(
                    .incompleteAtBoundary(
                        startObservationIndex: priorStartObservationIndex,
                        lastAcceptedObservationIndex: priorLastAcceptedObservationIndex,
                        nextObservationIndex: index,
                        boundary: .candidatePacketZeroRestart
                    )
                )
                reassembler = nil
                resetState(
                    streamIdentity: &boundStreamIdentity,
                    continuityGeneration: &boundContinuityGeneration,
                    startObservationIndex: &startObservationIndex,
                    lastAcceptedObservationIndex: &lastAcceptedObservationIndex
                )
            }

            if reassembler == nil {
                reassembler = TuyaCandidateFragmentReassembler(policy: policy)
                boundStreamIdentity = observation.streamIdentity
                boundContinuityGeneration = observation.continuityGeneration
                startObservationIndex = index
            }

            do {
                guard var current = reassembler else {
                    events.append(.unexpectedAnalyzerFailure(failingObservationIndex: index))
                    return events
                }
                let progress = try current.ingest(observation)
                lastAcceptedObservationIndex = index

                switch progress {
                case .awaitingMore:
                    reassembler = current
                case let .complete(message):
                    events.append(
                        .completed(
                            startObservationIndex: startObservationIndex ?? index,
                            endObservationIndex: index,
                            message: message
                        )
                    )
                    reassembler = nil
                    resetState(
                        streamIdentity: &boundStreamIdentity,
                        continuityGeneration: &boundContinuityGeneration,
                        startObservationIndex: &startObservationIndex,
                        lastAcceptedObservationIndex: &lastAcceptedObservationIndex
                    )
                }
            } catch let error as TuyaCandidateOfflineAnalysisError {
                events.append(
                    .rejectedCandidate(
                        startObservationIndex: startObservationIndex ?? index,
                        lastAcceptedObservationIndex: lastAcceptedObservationIndex,
                        failingObservationIndex: index,
                        error: error
                    )
                )
                reassembler = nil
                resetState(
                    streamIdentity: &boundStreamIdentity,
                    continuityGeneration: &boundContinuityGeneration,
                    startObservationIndex: &startObservationIndex,
                    lastAcceptedObservationIndex: &lastAcceptedObservationIndex
                )
            } catch {
                // All current ingest failures are typed. If that contract changes,
                // stop instead of silently dropping evidence and continuing.
                events.append(.unexpectedAnalyzerFailure(failingObservationIndex: index))
                return events
            }
        }

        if reassembler != nil,
           let startObservationIndex,
           let lastAcceptedObservationIndex {
            events.append(
                .incompleteAtEnd(
                    startObservationIndex: startObservationIndex,
                    lastAcceptedObservationIndex: lastAcceptedObservationIndex
                )
            )
        }

        return events
    }

    private static func beginsWithCandidatePacketZero(
        _ observation: TuyaCandidateFragmentObservation
    ) -> Bool {
        var cursor = 0
        return (try? TuyaCandidateFragmentReassembler.decodeCandidateVarint(
            observation.bytes,
            cursor: &cursor
        )) == 0
    }

    private static func resetState(
        streamIdentity: inout TuyaCandidateValueStreamIdentity?,
        continuityGeneration: inout UInt64?,
        startObservationIndex: inout Int?,
        lastAcceptedObservationIndex: inout Int?
    ) {
        streamIdentity = nil
        continuityGeneration = nil
        startObservationIndex = nil
        lastAcceptedObservationIndex = nil
    }
}
