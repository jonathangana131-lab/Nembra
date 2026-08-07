import Foundation
import NembraCore

/// Outcome of repeated stock-app correlation analysis.
///
/// `analyzed` means the capture was structurally eligible for analysis. It does
/// not mean any characteristic has been decoded or physically mapped to the
/// stock-app field.
public enum PassiveBluetoothRepeatedCorrelationDisposition: String, Equatable, Sendable {
    case analyzed
    case noMatchingMarkers
    case ambiguousPeripheralScope
    case invalidPeripheralScope
}

/// Traceable nearest raw-value evidence for one stock-app marker and one GATT
/// value stream. Sequence numbers point back into the immutable capture artifact
/// so a later analyst can inspect the original bytes without duplicating or
/// mutating them here.
public struct PassiveBluetoothRepeatedCorrelationHit: Equatable, Sendable {
    public let markerSequenceNumber: UInt64
    public let markerDisplayedValue: String
    public let candidateSequenceNumber: UInt64
    public let candidateOffsetSeconds: Double
    public let origin: PassiveBluetoothValueOrigin
    public let payloadByteCount: Int

    /// Analyzer output only. File-private construction prevents unrelated callers
    /// from minting correlation evidence that was never derived from a capture.
    fileprivate init(
        markerSequenceNumber: UInt64,
        markerDisplayedValue: String,
        candidateSequenceNumber: UInt64,
        candidateOffsetSeconds: Double,
        origin: PassiveBluetoothValueOrigin,
        payloadByteCount: Int
    ) {
        self.markerSequenceNumber = markerSequenceNumber
        self.markerDisplayedValue = markerDisplayedValue
        self.candidateSequenceNumber = candidateSequenceNumber
        self.candidateOffsetSeconds = candidateOffsetSeconds
        self.origin = origin
        self.payloadByteCount = payloadByteCount
    }

    public var absoluteOffsetSeconds: Double {
        abs(candidateOffsetSeconds)
    }
}

/// Repeated time-correlation evidence for one exact peripheral/service/
/// characteristic stream.
///
/// Support counts are deliberately marker-based: a high-rate characteristic can
/// emit many callbacks inside one window, but it receives at most one support hit
/// for that marker. `rawCandidateCount` remains available so callback density is
/// visible instead of being hidden by the de-duplication.
public struct PassiveBluetoothRepeatedCorrelationStreamEvidence: Equatable, Sendable, Identifiable {
    public let key: PassiveBluetoothValueStreamKey
    public let totalMarkerCount: Int
    public let rawCandidateCount: Int
    public let hits: [PassiveBluetoothRepeatedCorrelationHit]
    public let representedDisplayedValues: Set<String>
    public let medianNearestAbsoluteOffsetSeconds: Double?
    public let maximumNearestAbsoluteOffsetSeconds: Double?

    public var id: PassiveBluetoothValueStreamKey { key }

    /// Analyzer output only. Keeping construction in this file makes support
    /// counts, hit provenance, and summary statistics read-only evidence outside
    /// the producer boundary.
    fileprivate init(
        key: PassiveBluetoothValueStreamKey,
        totalMarkerCount: Int,
        rawCandidateCount: Int,
        hits: [PassiveBluetoothRepeatedCorrelationHit],
        representedDisplayedValues: Set<String>,
        medianNearestAbsoluteOffsetSeconds: Double?,
        maximumNearestAbsoluteOffsetSeconds: Double?
    ) {
        self.key = key
        self.totalMarkerCount = totalMarkerCount
        self.rawCandidateCount = rawCandidateCount
        self.hits = hits
        self.representedDisplayedValues = representedDisplayedValues
        self.medianNearestAbsoluteOffsetSeconds = medianNearestAbsoluteOffsetSeconds
        self.maximumNearestAbsoluteOffsetSeconds = maximumNearestAbsoluteOffsetSeconds
    }

    public var markerSupportCount: Int {
        hits.count
    }

    public var markerSupportFraction: Double {
        guard totalMarkerCount > 0 else { return 0 }
        return Double(markerSupportCount) / Double(totalMarkerCount)
    }

    /// Descriptive repeatability only. This is not protocol-field confidence.
    public var isRepeatedAcrossMarkers: Bool {
        markerSupportCount >= 2
    }

    /// Descriptive evidence that the stream recurred near markers carrying more
    /// than one human-observed display string. It does not mean the payload bytes
    /// encode or scale with those strings.
    public var isRepeatedAcrossDisplayedValues: Bool {
        markerSupportCount >= 2 && representedDisplayedValues.count >= 2
    }
}

/// Cross-marker report for one human-observed stock-app field.
///
/// The stream list is a prioritization aid for offline research only. Ranking is
/// based on repeated temporal support, display-value diversity, and proximity;
/// it never labels a stream as battery/current/power/etc. and never decodes the
/// opaque payload.
public struct PassiveBluetoothRepeatedCorrelationReport: Equatable, Sendable {
    public let disposition: PassiveBluetoothRepeatedCorrelationDisposition
    public let field: String
    public let markerCount: Int
    public let distinctDisplayedValues: Set<String>
    public let streamEvidence: [PassiveBluetoothRepeatedCorrelationStreamEvidence]

    /// Analyzer output only. Callers consume reports read-only rather than
    /// manufacturing an `.analyzed` result disconnected from capture evidence.
    fileprivate init(
        disposition: PassiveBluetoothRepeatedCorrelationDisposition,
        field: String,
        markerCount: Int,
        distinctDisplayedValues: Set<String>,
        streamEvidence: [PassiveBluetoothRepeatedCorrelationStreamEvidence]
    ) {
        self.disposition = disposition
        self.field = field
        self.markerCount = markerCount
        self.distinctDisplayedValues = distinctDisplayedValues
        self.streamEvidence = streamEvidence
    }
}

/// Builds deterministic repeated-correlation evidence from the already lossless
/// passive-capture timeline.
///
/// This layer intentionally depends on `PassiveBluetoothCorrelation` for each
/// marker window so known byte-continuity boundaries keep the same fail-closed
/// semantics. It does not merge callbacks across a disconnect/interruption and
/// does not mutate the raw evidence artifact.
public enum PassiveBluetoothRepeatedCorrelation {
    /// Analyze an unscoped capture only when its GATT/value evidence resolves to
    /// zero or one peripheral identifier. A mixed imported capture fails closed
    /// because stock-app markers themselves do not carry a peripheral identity.
    public static func analyze(
        _ session: PassiveBluetoothCaptureSession,
        field: String,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> PassiveBluetoothRepeatedCorrelationReport {
        let markerMetadata = matchingMarkerMetadata(in: session, field: field)
        guard markerMetadata.count > 0 else {
            return emptyReport(
                disposition: .noMatchingMarkers,
                field: field,
                markerMetadata: markerMetadata
            )
        }

        let peripheralIdentifiers = correlationPeripheralIdentifiers(in: session)
        guard peripheralIdentifiers.count <= 1 else {
            return emptyReport(
                disposition: .ambiguousPeripheralScope,
                field: field,
                markerMetadata: markerMetadata
            )
        }

        return buildReport(
            windows: PassiveBluetoothCorrelation.windows(
                in: session,
                field: field,
                lookbackNanoseconds: lookbackNanoseconds,
                lookaheadNanoseconds: lookaheadNanoseconds
            ),
            field: field,
            markerMetadata: markerMetadata
        )
    }

    /// Analyze one explicitly selected peripheral in an imported/mixed capture.
    /// Only raw value evidence from that exact identifier is eligible. The
    /// CoreBluetooth identifier remains observed transport identity evidence; it
    /// is not promoted to a globally stable physical scooter identity.
    public static func analyze(
        _ session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String,
        field: String,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> PassiveBluetoothRepeatedCorrelationReport {
        let markerMetadata = matchingMarkerMetadata(in: session, field: field)
        guard markerMetadata.count > 0 else {
            return emptyReport(
                disposition: .noMatchingMarkers,
                field: field,
                markerMetadata: markerMetadata
            )
        }
        guard !peripheralIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return emptyReport(
                disposition: .invalidPeripheralScope,
                field: field,
                markerMetadata: markerMetadata
            )
        }

        return buildReport(
            windows: PassiveBluetoothCorrelation.windows(
                in: session,
                peripheralIdentifier: peripheralIdentifier,
                field: field,
                lookbackNanoseconds: lookbackNanoseconds,
                lookaheadNanoseconds: lookaheadNanoseconds
            ),
            field: field,
            markerMetadata: markerMetadata
        )
    }

    private struct MarkerMetadata {
        var count = 0
        var displayedValues: Set<String> = []
    }

    private struct MutableStreamEvidence {
        var rawCandidateCount = 0
        var hits: [PassiveBluetoothRepeatedCorrelationHit] = []

        mutating func ingest(
            window: PassiveBluetoothCorrelationWindow,
            nearestCandidate: PassiveBluetoothCorrelationCandidate,
            rawCandidateCount: Int
        ) {
            self.rawCandidateCount += rawCandidateCount
            hits.append(
                PassiveBluetoothRepeatedCorrelationHit(
                    markerSequenceNumber: window.markerSequenceNumber,
                    markerDisplayedValue: window.displayedValue,
                    candidateSequenceNumber: nearestCandidate.sequenceNumber,
                    candidateOffsetSeconds: nearestCandidate.offsetSecondsFromMarker,
                    origin: nearestCandidate.origin,
                    payloadByteCount: nearestCandidate.payload.count
                )
            )
        }

        func finalized(
            key: PassiveBluetoothValueStreamKey,
            totalMarkerCount: Int
        ) -> PassiveBluetoothRepeatedCorrelationStreamEvidence {
            let orderedHits = hits.sorted { lhs, rhs in
                if lhs.markerSequenceNumber != rhs.markerSequenceNumber {
                    return lhs.markerSequenceNumber < rhs.markerSequenceNumber
                }
                return lhs.candidateSequenceNumber < rhs.candidateSequenceNumber
            }
            let absoluteOffsets = orderedHits.map(\.absoluteOffsetSeconds).sorted()

            return PassiveBluetoothRepeatedCorrelationStreamEvidence(
                key: key,
                totalMarkerCount: totalMarkerCount,
                rawCandidateCount: rawCandidateCount,
                hits: orderedHits,
                representedDisplayedValues: Set(orderedHits.map(\.markerDisplayedValue)),
                medianNearestAbsoluteOffsetSeconds: median(absoluteOffsets),
                maximumNearestAbsoluteOffsetSeconds: absoluteOffsets.last
            )
        }
    }

    private static func buildReport(
        windows: [PassiveBluetoothCorrelationWindow],
        field: String,
        markerMetadata: MarkerMetadata
    ) -> PassiveBluetoothRepeatedCorrelationReport {
        var accumulators: [PassiveBluetoothValueStreamKey: MutableStreamEvidence] = [:]

        for window in windows {
            var candidatesByStream: [PassiveBluetoothValueStreamKey: [PassiveBluetoothCorrelationCandidate]] = [:]
            for candidate in window.candidates {
                let key = PassiveBluetoothValueStreamKey(
                    peripheralIdentifier: candidate.peripheralIdentifier,
                    serviceUUID: candidate.serviceUUID,
                    characteristicUUID: candidate.characteristicUUID
                )
                candidatesByStream[key, default: []].append(candidate)
            }

            for (key, candidates) in candidatesByStream {
                // `PassiveBluetoothCorrelation` already sorts each window by
                // absolute marker offset then sequence number. Filtering that
                // stable order by stream preserves the deterministic nearest hit.
                guard let nearest = candidates.first else { continue }
                var accumulator = accumulators[key, default: MutableStreamEvidence()]
                accumulator.ingest(
                    window: window,
                    nearestCandidate: nearest,
                    rawCandidateCount: candidates.count
                )
                accumulators[key] = accumulator
            }
        }

        let streamEvidence = accumulators.map { key, accumulator in
            accumulator.finalized(key: key, totalMarkerCount: markerMetadata.count)
        }
        .sorted(by: evidenceSort)

        return PassiveBluetoothRepeatedCorrelationReport(
            disposition: .analyzed,
            field: field,
            markerCount: markerMetadata.count,
            distinctDisplayedValues: markerMetadata.displayedValues,
            streamEvidence: streamEvidence
        )
    }

    /// Sorting is a research convenience, not a semantic confidence score.
    /// Repeated marker support is prioritized first; diversity and temporal
    /// proximity break ties before deterministic stream identity ordering.
    private static func evidenceSort(
        _ lhs: PassiveBluetoothRepeatedCorrelationStreamEvidence,
        _ rhs: PassiveBluetoothRepeatedCorrelationStreamEvidence
    ) -> Bool {
        if lhs.markerSupportCount != rhs.markerSupportCount {
            return lhs.markerSupportCount > rhs.markerSupportCount
        }
        if lhs.representedDisplayedValues.count != rhs.representedDisplayedValues.count {
            return lhs.representedDisplayedValues.count > rhs.representedDisplayedValues.count
        }

        let lhsMedian = lhs.medianNearestAbsoluteOffsetSeconds ?? .infinity
        let rhsMedian = rhs.medianNearestAbsoluteOffsetSeconds ?? .infinity
        if lhsMedian != rhsMedian {
            return lhsMedian < rhsMedian
        }
        return lhs.key < rhs.key
    }

    private static func matchingMarkerMetadata(
        in session: PassiveBluetoothCaptureSession,
        field: String
    ) -> MarkerMetadata {
        var metadata = MarkerMetadata()
        for record in session.records {
            guard case let .stockAppState(marker) = record.event,
                  marker.field.caseInsensitiveCompare(field) == .orderedSame else {
                continue
            }
            metadata.count += 1
            metadata.displayedValues.insert(marker.displayedValue)
        }
        return metadata
    }

    /// Mirrors the existing correlation layer's attribution boundary. Only GATT
    /// and raw-value evidence participates in ambiguity detection; advertisement
    /// noise and connection callbacks alone do not assign a marker to a target.
    private static func correlationPeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession
    ) -> Set<String> {
        var identifiers: Set<String> = []

        for record in session.records {
            switch record.event {
            case let .service(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .includedService(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .characteristic(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .descriptor(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .subscription(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .value(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case .advertisement, .connection, .stockAppState, .interruption:
                break
            }
        }

        return identifiers
    }

    private static func emptyReport(
        disposition: PassiveBluetoothRepeatedCorrelationDisposition,
        field: String,
        markerMetadata: MarkerMetadata
    ) -> PassiveBluetoothRepeatedCorrelationReport {
        PassiveBluetoothRepeatedCorrelationReport(
            disposition: disposition,
            field: field,
            markerCount: markerMetadata.count,
            distinctDisplayedValues: markerMetadata.displayedValues,
            streamEvidence: []
        )
    }

    private static func median(_ sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}
