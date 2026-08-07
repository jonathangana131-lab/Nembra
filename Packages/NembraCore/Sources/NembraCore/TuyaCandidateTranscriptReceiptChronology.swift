/// Transcript-wide source-order authority for immutable candidate observations.
///
/// This state intentionally outlives individual candidate reassemblers. Candidate
/// completion, framing rejection, packet-zero restart, and real stream/continuity
/// boundaries do not erase already-seen receipt chronology. That prevents a later
/// delayed or replayed callback from becoming "fresh" merely because candidate
/// framing state restarted.
///
/// Ordering has the same truth law as the direct reassembler:
/// - legacy observations use strict seen uptime;
/// - receipt-backed observations use one immutable nonblank scope + strict
///   sequence, while uptime is nondecreasing metadata;
/// - a newly seen sequence is consumed before backward-uptime rejection, so the
///   same callback cannot be replayed with rewritten clock metadata;
/// - authority/scope mismatch is rejected before watermarks mutate.
///
/// This is software capture provenance only. It assigns no Tuya, DP, telemetry,
/// vehicle, or physical-hardware meaning to an observation.
struct TuyaCandidateTranscriptReceiptChronology: Sendable {
    private var receiptOrderingUsesSequence: Bool?
    private var receiptSequenceScope: String?
    private var highestSeenReceiptSequenceNumber: UInt64?
    private var highestSeenReceiptUptimeNanoseconds: UInt64?

    mutating func admit(
        _ observation: TuyaCandidateFragmentObservation
    ) throws {
        let usesSequence = observation.receiptSequenceNumber != nil

        if let receiptOrderingUsesSequence {
            guard receiptOrderingUsesSequence == usesSequence else {
                throw TuyaCandidateOfflineAnalysisError.receiptOrderingAuthorityChanged
            }
            if usesSequence,
               receiptSequenceScope != observation.receiptSequenceScope {
                throw TuyaCandidateOfflineAnalysisError.receiptSequenceScopeChanged(
                    expected: receiptSequenceScope,
                    actual: observation.receiptSequenceScope
                )
            }
        } else {
            receiptOrderingUsesSequence = usesSequence
            if usesSequence {
                receiptSequenceScope = observation.receiptSequenceScope
            }
        }

        if let sequence = observation.receiptSequenceNumber {
            if let previous = highestSeenReceiptSequenceNumber {
                guard sequence > previous else {
                    throw TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptSequence(
                        previous: previous,
                        actual: sequence
                    )
                }
            }

            // Immutable callback identity is consumed before clock validation.
            // A callback rejected for backward uptime cannot later be replayed
            // with the same sequence and a rewritten timestamp.
            highestSeenReceiptSequenceNumber = sequence

            if let uptimeFloor = highestSeenReceiptUptimeNanoseconds,
               observation.receiptUptimeNanoseconds < uptimeFloor {
                throw TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptUptime
            }
            highestSeenReceiptUptimeNanoseconds = observation.receiptUptimeNanoseconds
            return
        }

        if let uptimeFloor = highestSeenReceiptUptimeNanoseconds,
           observation.receiptUptimeNanoseconds <= uptimeFloor {
            throw TuyaCandidateOfflineAnalysisError.nonMonotonicReceiptUptime
        }

        // With no scoped sequence, uptime is the only source-order authority.
        highestSeenReceiptUptimeNanoseconds = observation.receiptUptimeNanoseconds
    }
}
