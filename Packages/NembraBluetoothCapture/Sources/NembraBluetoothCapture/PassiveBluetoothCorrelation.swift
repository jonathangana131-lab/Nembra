import Foundation
import NembraCore

/// One raw characteristic-value event near a human-observed stock-app marker.
/// The payload remains opaque; proximity is correlation evidence only and never
/// establishes a Tuya DP or field meaning.
public struct PassiveBluetoothCorrelationCandidate: Equatable, Sendable {
    public let sequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let offsetSecondsFromMarker: Double
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String
    public let origin: PassiveBluetoothValueOrigin
    public let payload: Data

    public init(
        sequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        offsetSecondsFromMarker: Double,
        peripheralIdentifier: String,
        serviceUUID: String,
        characteristicUUID: String,
        origin: PassiveBluetoothValueOrigin,
        payload: Data
    ) {
        self.sequenceNumber = sequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.offsetSecondsFromMarker = offsetSecondsFromMarker
        self.peripheralIdentifier = peripheralIdentifier
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.origin = origin
        self.payload = payload
    }

    public var payloadHex: String {
        payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// A stock-app observation plus nearby raw value callbacks from the same known
/// continuity segment.
public struct PassiveBluetoothCorrelationWindow: Equatable, Sendable {
    public let markerSequenceNumber: UInt64
    public let markerUptimeNanoseconds: UInt64
    public let field: String
    public let displayedValue: String
    public let note: String?
    public let candidates: [PassiveBluetoothCorrelationCandidate]

    public init(
        markerSequenceNumber: UInt64,
        markerUptimeNanoseconds: UInt64,
        field: String,
        displayedValue: String,
        note: String?,
        candidates: [PassiveBluetoothCorrelationCandidate]
    ) {
        self.markerSequenceNumber = markerSequenceNumber
        self.markerUptimeNanoseconds = markerUptimeNanoseconds
        self.field = field
        self.displayedValue = displayedValue
        self.note = note
        self.candidates = candidates
    }
}

public enum PassiveBluetoothCorrelation {
    /// Builds time-local candidate windows around stock-app observations.
    ///
    /// This convenience fails closed when imported GATT/value/connection
    /// evidence belongs to more than one peripheral. Stock-app markers have no
    /// peripheral field, so choosing one device in a mixed session would
    /// fabricate attribution. Nearby advertisement-only noise does not create
    /// this ambiguity.
    public static func windows(
        in session: PassiveBluetoothCaptureSession,
        field: String? = nil,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> [PassiveBluetoothCorrelationWindow] {
        let peripheralIdentifiers = correlationPeripheralIdentifiers(in: session)
        guard peripheralIdentifiers.count <= 1 else { return [] }

        return buildWindows(
            in: session,
            peripheralIdentifier: peripheralIdentifiers.first,
            field: field,
            lookbackNanoseconds: lookbackNanoseconds,
            lookaheadNanoseconds: lookaheadNanoseconds
        )
    }

    /// Builds correlation windows for an explicitly selected peripheral in an
    /// imported/mixed session. Only raw value evidence from that exact target is
    /// eligible; the marker itself remains a human observation, not telemetry.
    ///
    /// Returns `nil` when the requested identifier has no correlation-attributable
    /// connection/GATT/value evidence in the artifact. This keeps a typo or stale
    /// identifier distinct from an observed target that legitimately has zero
    /// nearby candidate values. Advertisement-only observations do not establish
    /// marker attribution for this API.
    public static func windows(
        in session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String,
        field: String? = nil,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> [PassiveBluetoothCorrelationWindow]? {
        guard correlationPeripheralIdentifiers(in: session).contains(peripheralIdentifier) else {
            return nil
        }

        return buildWindows(
            in: session,
            peripheralIdentifier: peripheralIdentifier,
            field: field,
            lookbackNanoseconds: lookbackNanoseconds,
            lookaheadNanoseconds: lookaheadNanoseconds
        )
    }

    /// Generic interruption events are global observation gaps. Structured
    /// disconnects are scoped to the exact peripheral being analyzed so a
    /// disconnect from unrelated imported device B cannot split target A's
    /// otherwise-continuous correlation segment.
    private static func buildWindows(
        in session: PassiveBluetoothCaptureSession,
        peripheralIdentifier: String?,
        field: String?,
        lookbackNanoseconds: UInt64,
        lookaheadNanoseconds: UInt64
    ) -> [PassiveBluetoothCorrelationWindow] {
        let records = session.records
        var segmentStart = 0
        var segmentIndexByRecord = Array(repeating: 0, count: records.count)
        var segmentStarts: [Int] = [0]
        var segmentEnds: [Int] = []
        var currentSegment = 0

        for index in records.indices {
            segmentIndexByRecord[index] = currentSegment
            if breaksContinuity(
                records[index].event,
                peripheralIdentifier: peripheralIdentifier
            ) {
                segmentEnds.append(index)
                segmentStart = index + 1
                currentSegment += 1
                segmentStarts.append(segmentStart)
            }
        }
        segmentEnds.append(records.count)

        var result: [PassiveBluetoothCorrelationWindow] = []
        result.reserveCapacity(records.count / 4)

        for markerIndex in records.indices {
            guard case let .stockAppState(marker) = records[markerIndex].event else { continue }
            if let field,
               marker.field.caseInsensitiveCompare(field) != .orderedSame {
                continue
            }

            let segment = segmentIndexByRecord[markerIndex]
            let lowerIndex = segmentStarts[segment]
            let upperIndex = segmentEnds[segment]
            let markerUptime = records[markerIndex].receivedAtUptimeNanoseconds
            let minimumUptime = markerUptime >= lookbackNanoseconds
                ? markerUptime - lookbackNanoseconds
                : 0
            let maximumUptime = markerUptime.addingReportingOverflow(lookaheadNanoseconds)
            let upperUptime = maximumUptime.overflow ? UInt64.max : maximumUptime.partialValue

            var candidates: [PassiveBluetoothCorrelationCandidate] = []
            for candidateIndex in lowerIndex..<upperIndex {
                let record = records[candidateIndex]
                guard record.receivedAtUptimeNanoseconds >= minimumUptime,
                      record.receivedAtUptimeNanoseconds <= upperUptime,
                      case let .value(value) = record.event else { continue }
                if let peripheralIdentifier,
                   value.peripheralIdentifier != peripheralIdentifier {
                    continue
                }

                candidates.append(
                    PassiveBluetoothCorrelationCandidate(
                        sequenceNumber: record.sequenceNumber,
                        receivedAtUptimeNanoseconds: record.receivedAtUptimeNanoseconds,
                        offsetSecondsFromMarker: signedOffsetSeconds(
                            candidate: record.receivedAtUptimeNanoseconds,
                            marker: markerUptime
                        ),
                        peripheralIdentifier: value.peripheralIdentifier,
                        serviceUUID: value.serviceUUID,
                        characteristicUUID: value.characteristicUUID,
                        origin: value.origin,
                        payload: value.payload
                    )
                )
            }

            candidates.sort { lhs, rhs in
                let lhsMagnitude = abs(lhs.offsetSecondsFromMarker)
                let rhsMagnitude = abs(rhs.offsetSecondsFromMarker)
                if lhsMagnitude != rhsMagnitude { return lhsMagnitude < rhsMagnitude }
                return lhs.sequenceNumber < rhs.sequenceNumber
            }

            result.append(
                PassiveBluetoothCorrelationWindow(
                    markerSequenceNumber: records[markerIndex].sequenceNumber,
                    markerUptimeNanoseconds: markerUptime,
                    field: marker.field,
                    displayedValue: marker.displayedValue,
                    note: marker.note,
                    candidates: candidates
                )
            )
        }

        return result
    }

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

    private static func breaksContinuity(
        _ event: PassiveBluetoothCaptureEvent,
        peripheralIdentifier: String?
    ) -> Bool {
        switch event {
        case let .connection(observation):
            guard observation.state == .disconnected else { return false }
            guard let peripheralIdentifier else { return true }
            return observation.peripheralIdentifier == peripheralIdentifier
        case .interruption:
            return true
        default:
            return false
        }
    }

    private static func signedOffsetSeconds(candidate: UInt64, marker: UInt64) -> Double {
        if candidate >= marker {
            return Double(candidate - marker) / 1_000_000_000
        }
        return -Double(marker - candidate) / 1_000_000_000
    }
}