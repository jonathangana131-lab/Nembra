import Foundation
import NembraCore

/// Exact raw-value stream identity for offline analysis.
///
/// Acquisition origin is part of the identity on purpose. A read response and a
/// notification/subscription callback from the same GATT characteristic are not
/// interchangeable evidence and must never be silently spliced into one byte
/// stream.
public struct PassiveBluetoothOfflineStreamIdentity: Equatable, Hashable, Sendable {
    public let peripheralIdentifier: String
    public let serviceUUID: String
    public let characteristicUUID: String
    public let origin: PassiveBluetoothValueOrigin

    public init(_ observation: PassiveBluetoothValueObservation) {
        peripheralIdentifier = observation.peripheralIdentifier
        serviceUUID = observation.serviceUUID
        characteristicUUID = observation.characteristicUUID
        origin = observation.origin
    }
}

/// One raw value observation projected from an immutable capture record.
/// Sequence is the strict source order. Uptime remains original receipt metadata
/// and is intentionally allowed to tie with another observation.
public struct PassiveBluetoothOfflineValueRecord: Equatable, Sendable {
    public let sourceRecordIndex: Int
    public let sequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let continuityGeneration: UInt64
    public let streamIdentity: PassiveBluetoothOfflineStreamIdentity
    public let payload: Data
}

/// Human-observed stock-app correlation marker preserved on the same source
/// timeline as raw Bluetooth evidence. A marker never assigns protocol meaning to
/// any byte by itself.
public struct PassiveBluetoothOfflineStockAppMarker: Equatable, Sendable {
    public let sourceRecordIndex: Int
    public let sequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let continuityGeneration: UInt64
    public let observation: PassiveBluetoothStockAppObservation
}

/// Exact source event that split byte continuity. Keeping the original event
/// prevents a later analyzer from turning a disconnect/interruption into an
/// inferred reason or silently joining values across the gap.
public struct PassiveBluetoothOfflineContinuityBoundary: Equatable, Sendable {
    public let sourceRecordIndex: Int
    public let sequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let receivedAtDate: Date
    public let generationBefore: UInt64
    public let generationAfter: UInt64
    public let sourceEvent: PassiveBluetoothCaptureEvent
}

/// Lossless analysis-facing projection of the evidence needed for offline byte
/// framing and stock-app correlation. This is derived data, not a replacement
/// durable capture format; `PassiveBluetoothCaptureJSON` remains the authoritative
/// versioned artifact.
public struct PassiveBluetoothOfflineTranscript: Equatable, Sendable {
    public let captureSessionID: UUID
    public let captureStartedAt: Date
    public let sourceRecordCount: Int
    public let values: [PassiveBluetoothOfflineValueRecord]
    public let stockAppMarkers: [PassiveBluetoothOfflineStockAppMarker]
    public let continuityBoundaries: [PassiveBluetoothOfflineContinuityBoundary]
}

public enum PassiveBluetoothOfflineTranscriptProjectionError: Error, Equatable, Sendable {
    case continuityGenerationExhausted
}

/// Projects already validated capture records without changing bytes, clocks,
/// sequence numbers, GATT identity, acquisition origin, or gap topology.
///
/// The projection deliberately does not:
/// - guess a Tuya/ZYDTECH transport family;
/// - search for packet offsets;
/// - infer DP IDs/scales/units;
/// - merge read and subscription origins;
/// - synthesize strictly increasing timestamps;
/// - treat a stock-app marker as decoded protocol truth.
public enum PassiveBluetoothOfflineTranscriptProjector {
    public static func project(
        _ session: PassiveBluetoothCaptureSession
    ) throws -> PassiveBluetoothOfflineTranscript {
        var generation: UInt64 = 0
        var values: [PassiveBluetoothOfflineValueRecord] = []
        var markers: [PassiveBluetoothOfflineStockAppMarker] = []
        var boundaries: [PassiveBluetoothOfflineContinuityBoundary] = []

        values.reserveCapacity(session.records.count)

        for (index, record) in session.records.enumerated() {
            switch record.event {
            case let .value(observation):
                values.append(
                    PassiveBluetoothOfflineValueRecord(
                        sourceRecordIndex: index,
                        sequenceNumber: record.sequenceNumber,
                        receivedAtUptimeNanoseconds: record.receivedAtUptimeNanoseconds,
                        receivedAtDate: record.receivedAtDate,
                        continuityGeneration: generation,
                        streamIdentity: PassiveBluetoothOfflineStreamIdentity(observation),
                        payload: observation.payload
                    )
                )

            case let .stockAppState(observation):
                markers.append(
                    PassiveBluetoothOfflineStockAppMarker(
                        sourceRecordIndex: index,
                        sequenceNumber: record.sequenceNumber,
                        receivedAtUptimeNanoseconds: record.receivedAtUptimeNanoseconds,
                        receivedAtDate: record.receivedAtDate,
                        continuityGeneration: generation,
                        observation: observation
                    )
                )

            default:
                break
            }

            guard record.event.breaksByteContinuity else { continue }
            let (nextGeneration, overflow) = generation.addingReportingOverflow(1)
            guard !overflow else {
                throw PassiveBluetoothOfflineTranscriptProjectionError.continuityGenerationExhausted
            }
            boundaries.append(
                PassiveBluetoothOfflineContinuityBoundary(
                    sourceRecordIndex: index,
                    sequenceNumber: record.sequenceNumber,
                    receivedAtUptimeNanoseconds: record.receivedAtUptimeNanoseconds,
                    receivedAtDate: record.receivedAtDate,
                    generationBefore: generation,
                    generationAfter: nextGeneration,
                    sourceEvent: record.event
                )
            )
            generation = nextGeneration
        }

        return PassiveBluetoothOfflineTranscript(
            captureSessionID: session.id,
            captureStartedAt: session.startedAt,
            sourceRecordCount: session.records.count,
            values: values,
            stockAppMarkers: markers,
            continuityBoundaries: boundaries
        )
    }
}
