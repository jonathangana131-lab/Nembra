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
    /// - Parameters:
    ///   - session: Immutable raw capture evidence.
    ///   - field: Optional case-insensitive exact stock-app field filter.
    ///   - lookbackNanoseconds: Maximum raw-value age before the marker.
    ///   - lookaheadNanoseconds: Maximum raw-value time after the marker.
    ///
    /// Any parent-model byte-continuity break is a hard boundary. A value on the
    /// other side of a structured disconnect/Bluetooth transition/observer
    /// restart is never presented as a candidate for the marker, even if timing
    /// proximity happens to be small.
    public static func windows(
        in session: PassiveBluetoothCaptureSession,
        field: String? = nil,
        lookbackNanoseconds: UInt64 = 2_000_000_000,
        lookaheadNanoseconds: UInt64 = 2_000_000_000
    ) -> [PassiveBluetoothCorrelationWindow] {
        let records = session.records
        var segmentStart = 0
        var segmentIndexByRecord = Array(repeating: 0, count: records.count)
        var segmentStarts: [Int] = [0]
        var segmentEnds: [Int] = []
        var currentSegment = 0

        for index in records.indices {
            segmentIndexByRecord[index] = currentSegment
            if records[index].event.breaksByteContinuity {
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

    private static func signedOffsetSeconds(candidate: UInt64, marker: UInt64) -> Double {
        if candidate >= marker {
            return Double(candidate - marker) / 1_000_000_000
        }
        return -Double(marker - candidate) / 1_000_000_000
    }
}
