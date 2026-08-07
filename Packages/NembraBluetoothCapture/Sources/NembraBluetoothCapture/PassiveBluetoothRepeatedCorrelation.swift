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

/// Traceable independently assigned raw-value evidence for one stock-app marker
/// and one GATT value stream. Sequence numbers point back into the immutable
/// capture artifact so a later analyst can inspect the original bytes without
/// duplicating or mutating them here.
public struct PassiveBluetoothRepeatedCorrelationHit: Equatable, Sendable {
    public let markerSequenceNumber: UInt64
    public let markerDisplayedValue: String
    public let candidateSequenceNumber: UInt64
    public let candidateOffsetSeconds: Double
    public let origin: PassiveBluetoothValueOrigin
    public let payloadByteCount: Int

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
/// `hits` are independent assignments: one immutable raw callback may support at
/// most one human marker in this report. `rawCandidateCount` is the number of
/// distinct raw callback sequence identities observed for the stream across all
/// marker windows, not the number of window incidences.
///
/// The `medianNearest...` / `maximumNearest...` fields are literal nearest-
/// candidate proximity summaries: for every marker window containing this stream,
/// they use that window's nearest raw callback before one-to-one support allocation.
/// They describe local candidate availability, not the proximity of the callbacks
/// ultimately credited as independent support.
///
/// The `medianAssigned...` / `maximumAssigned...` fields summarize the actual
/// independently assigned hits after one-to-one allocation. An assigned hit may be
/// farther away than the marker's nearest callback when augmenting reassignment is
/// required to avoid crediting the same immutable callback twice. Stream ranking
/// uses these assigned-evidence metrics rather than the pre-allocation nearest ones.
public struct PassiveBluetoothRepeatedCorrelationStreamEvidence: Equatable, Sendable, Identifiable {
    public let key: PassiveBluetoothValueStreamKey
    public let totalMarkerCount: Int
    public let rawCandidateCount: Int
    public let hits: [PassiveBluetoothRepeatedCorrelationHit]
    public let representedDisplayedValues: Set<String>
    public let medianNearestAbsoluteOffsetSeconds: Double?
    public let maximumNearestAbsoluteOffsetSeconds: Double?
    public let medianAssignedAbsoluteOffsetSeconds: Double?
    public let maximumAssignedAbsoluteOffsetSeconds: Double?

    public var id: PassiveBluetoothValueStreamKey { key }

    fileprivate init(
        key: PassiveBluetoothValueStreamKey,
        totalMarkerCount: Int,
        rawCandidateCount: Int,
        hits: [PassiveBluetoothRepeatedCorrelationHit],
        representedDisplayedValues: Set<String>,
        medianNearestAbsoluteOffsetSeconds: Double?,
        maximumNearestAbsoluteOffsetSeconds: Double?,
        medianAssignedAbsoluteOffsetSeconds: Double?,
        maximumAssignedAbsoluteOffsetSeconds: Double?
    ) {
        self.key = key
        self.totalMarkerCount = totalMarkerCount
        self.rawCandidateCount = rawCandidateCount
        self.hits = hits
        self.representedDisplayedValues = representedDisplayedValues
        self.medianNearestAbsoluteOffsetSeconds = medianNearestAbsoluteOffsetSeconds
        self.maximumNearestAbsoluteOffsetSeconds = maximumNearestAbsoluteOffsetSeconds
        self.medianAssignedAbsoluteOffsetSeconds = medianAssignedAbsoluteOffsetSeconds
        self.maximumAssignedAbsoluteOffsetSeconds = maximumAssignedAbsoluteOffsetSeconds
    }

    public var markerSupportCount: Int {
        hits.count
    }

    public var markerSupportFraction: Double {
        guard totalMarkerCount > 0 else { return 0 }
        return Double(markerSupportCount) / Double(totalMarkerCount)
    }

    /// Descriptive repeatability only. This is not protocol-field confidence.
    /// Because hits are one-to-one assignments, two hits necessarily represent
    /// two distinct immutable raw callbacks.
    public var isRepeatedAcrossMarkers: Bool {
        markerSupportCount >= 2
    }

    /// Descriptive evidence that independently repeated callbacks were assigned
    /// near markers carrying more than one human-observed display string. It does
    /// not mean the payload bytes encode or scale with those strings.
    public var isRepeatedAcrossDisplayedValues: Bool {
        markerSupportCount >= 2 && representedDisplayedValues.count >= 2
    }
}

/// Cross-marker report for one human-observed stock-app field.
///
/// The stream list is a prioritization aid for offline research only. Ranking is
/// based on independent repeated temporal support, display-value diversity, and
/// the proximity of the independently assigned callbacks; it never labels a stream
/// as battery/current/power/etc. and never decodes the opaque payload.
public struct PassiveBluetoothRepeatedCorrelationReport: Equatable, Sendable {
    public let disposition: PassiveBluetoothRepeatedCorrelationDisposition
    public let field: String
    public let markerCount: Int
    public let distinctDisplayedValues: Set<String>
    public let streamEvidence: [PassiveBluetoothRepeatedCorrelationStreamEvidence]

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
/// semantics. It does not merge callbacks across a disconnect/interruption inside
/// a marker window and does not mutate the raw evidence artifact. Repeated support
/// may aggregate the same GATT path across separately bounded marker windows; that
/// aggregate is recurrence evidence, not uninterrupted-stream evidence.
public enum PassiveBluetoothRepeatedCorrelation {
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

        // The parent correlation layer owns explicit target presence and the exact
        // attribution boundary. `nil` means the requested identifier never appears
        // in correlation-attributable connection/GATT/value evidence; an observed
        // target with zero nearby candidate values still returns non-nil windows.
        guard let windows = PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: peripheralIdentifier,
            field: field,
            lookbackNanoseconds: lookbackNanoseconds,
            lookaheadNanoseconds: lookaheadNanoseconds
        ) else {
            return emptyReport(
                disposition: .invalidPeripheralScope,
                field: field,
                markerMetadata: markerMetadata
            )
        }

        return buildReport(
            windows: windows,
            field: field,
            markerMetadata: markerMetadata
        )
    }

    private struct MarkerMetadata {
        var count = 0
        var displayedValues: Set<String> = []
    }

    private struct MarkerCandidateWindow {
        let markerSequenceNumber: UInt64
        let markerDisplayedValue: String
        let candidates: [PassiveBluetoothCorrelationCandidate]
    }

    private struct MutableStreamEvidence {
        var windows: [MarkerCandidateWindow] = []
        var rawCandidateSequenceNumbers: Set<UInt64> = []

        mutating func ingest(
            window: PassiveBluetoothCorrelationWindow,
            candidates: [PassiveBluetoothCorrelationCandidate]
        ) {
            guard !candidates.isEmpty else { return }
            let orderedCandidates = candidates.sorted(by: PassiveBluetoothRepeatedCorrelation.candidatePreference)
            windows.append(
                MarkerCandidateWindow(
                    markerSequenceNumber: window.markerSequenceNumber,
                    markerDisplayedValue: window.displayedValue,
                    candidates: orderedCandidates
                )
            )
            rawCandidateSequenceNumbers.formUnion(orderedCandidates.map(\.sequenceNumber))
        }

        func finalized(
            key: PassiveBluetoothValueStreamKey,
            totalMarkerCount: Int
        ) -> PassiveBluetoothRepeatedCorrelationStreamEvidence {
            let hits = PassiveBluetoothRepeatedCorrelation.independentHits(from: windows)
            let nearestAbsoluteOffsets = windows.compactMap { window in
                window.candidates.first.map { abs($0.offsetSecondsFromMarker) }
            }
            .sorted()
            let assignedAbsoluteOffsets = hits.map(\.absoluteOffsetSeconds).sorted()

            return PassiveBluetoothRepeatedCorrelationStreamEvidence(
                key: key,
                totalMarkerCount: totalMarkerCount,
                rawCandidateCount: rawCandidateSequenceNumbers.count,
                hits: hits,
                representedDisplayedValues: Set(hits.map(\.markerDisplayedValue)),
                medianNearestAbsoluteOffsetSeconds: PassiveBluetoothRepeatedCorrelation.median(nearestAbsoluteOffsets),
                maximumNearestAbsoluteOffsetSeconds: nearestAbsoluteOffsets.last,
                medianAssignedAbsoluteOffsetSeconds: PassiveBluetoothRepeatedCorrelation.median(assignedAbsoluteOffsets),
                maximumAssignedAbsoluteOffsetSeconds: assignedAbsoluteOffsets.last
            )
        }
    }

    /// Produces a deterministic maximum-cardinality one-to-one assignment between
    /// marker windows and immutable candidate sequence identities. Per-marker
    /// candidate preference remains absolute temporal proximity then sequence.
    /// An augmenting-path reassignment is allowed when it preserves an earlier
    /// marker with another candidate and lets a later marker gain independent
    /// support. This prevents one callback from manufacturing repeatability while
    /// avoiding unnecessary loss of legitimate independent evidence.
    private static func independentHits(
        from windows: [MarkerCandidateWindow]
    ) -> [PassiveBluetoothRepeatedCorrelationHit] {
        let orderedWindows = windows.sorted { lhs, rhs in
            lhs.markerSequenceNumber < rhs.markerSequenceNumber
        }
        guard !orderedWindows.isEmpty else { return [] }

        var candidateOwner: [UInt64: Int] = [:]
        var markerAssignment: [Int: PassiveBluetoothCorrelationCandidate] = [:]

        func assign(
            markerIndex: Int,
            visitedCandidateSequences: inout Set<UInt64>
        ) -> Bool {
            for candidate in orderedWindows[markerIndex].candidates {
                let sequence = candidate.sequenceNumber
                guard visitedCandidateSequences.insert(sequence).inserted else { continue }

                if let previousMarker = candidateOwner[sequence] {
                    if assign(
                        markerIndex: previousMarker,
                        visitedCandidateSequences: &visitedCandidateSequences
                    ) {
                        candidateOwner[sequence] = markerIndex
                        markerAssignment[markerIndex] = candidate
                        return true
                    }
                } else {
                    candidateOwner[sequence] = markerIndex
                    markerAssignment[markerIndex] = candidate
                    return true
                }
            }
            return false
        }

        for markerIndex in orderedWindows.indices {
            var visitedCandidateSequences: Set<UInt64> = []
            _ = assign(
                markerIndex: markerIndex,
                visitedCandidateSequences: &visitedCandidateSequences
            )
        }

        return markerAssignment.keys.sorted { lhs, rhs in
            orderedWindows[lhs].markerSequenceNumber < orderedWindows[rhs].markerSequenceNumber
        }
        .compactMap { markerIndex in
            guard let candidate = markerAssignment[markerIndex] else { return nil }
            let window = orderedWindows[markerIndex]
            return PassiveBluetoothRepeatedCorrelationHit(
                markerSequenceNumber: window.markerSequenceNumber,
                markerDisplayedValue: window.markerDisplayedValue,
                candidateSequenceNumber: candidate.sequenceNumber,
                candidateOffsetSeconds: candidate.offsetSecondsFromMarker,
                origin: candidate.origin,
                payloadByteCount: candidate.payload.count
            )
        }
    }

    private static func candidatePreference(
        _ lhs: PassiveBluetoothCorrelationCandidate,
        _ rhs: PassiveBluetoothCorrelationCandidate
    ) -> Bool {
        let lhsMagnitude = abs(lhs.offsetSecondsFromMarker)
        let rhsMagnitude = abs(rhs.offsetSecondsFromMarker)
        if lhsMagnitude != rhsMagnitude { return lhsMagnitude < rhsMagnitude }
        return lhs.sequenceNumber < rhs.sequenceNumber
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
                var accumulator = accumulators[key, default: MutableStreamEvidence()]
                accumulator.ingest(window: window, candidates: candidates)
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

        let lhsAssignedMedian = lhs.medianAssignedAbsoluteOffsetSeconds ?? .infinity
        let rhsAssignedMedian = rhs.medianAssignedAbsoluteOffsetSeconds ?? .infinity
        if lhsAssignedMedian != rhsAssignedMedian {
            return lhsAssignedMedian < rhsAssignedMedian
        }

        let lhsAssignedMaximum = lhs.maximumAssignedAbsoluteOffsetSeconds ?? .infinity
        let rhsAssignedMaximum = rhs.maximumAssignedAbsoluteOffsetSeconds ?? .infinity
        if lhsAssignedMaximum != rhsAssignedMaximum {
            return lhsAssignedMaximum < rhsAssignedMaximum
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

    /// Mirrors the current parent correlation attribution boundary for the
    /// unscoped disposition check. Explicit target presence is delegated directly
    /// to `PassiveBluetoothCorrelation.windows(...)` so this child does not carry
    /// a second explicit-target authority.
    private static func correlationPeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession
    ) -> Set<String> {
        var identifiers: Set<String> = []

        for record in session.records {
            switch record.event {
            case let .connection(observation):
                identifiers.insert(observation.peripheralIdentifier)
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
            case .advertisement, .stockAppState, .interruption:
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
