import Dispatch
import Foundation
import NembraCore

/// Serializes platform capture callbacks into one monotonic Nembra evidence
/// timeline. It owns ordering only; it does not infer DP meanings or reconstruct
/// fragmented Tuya messages.
public actor PassiveCoreBluetoothCaptureRecorder {
    private var session: PassiveBluetoothCaptureSession
    private var nextSequenceNumber: UInt64 = 1

    public init(
        id: UUID = UUID(),
        vehicleIdentity: VehicleIdentity,
        startedAt: Date = Date()
    ) throws {
        session = try PassiveBluetoothCaptureSession(
            id: id,
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
    }

    /// Records one event using the system-boot-relative monotonic uptime clock
    /// for ordering and wall-clock Date only as correlation metadata.
    public func record(_ event: PassiveBluetoothCaptureEvent) throws {
        try record(
            event,
            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            receivedAtDate: Date()
        )
    }

    /// Deterministic/testable recording path. Callers may supply equal monotonic
    /// timestamps for callbacks delivered in the same clock tick; sequence
    /// number remains the strict total-order tiebreaker.
    public func record(
        _ event: PassiveBluetoothCaptureEvent,
        receivedAtUptimeNanoseconds: UInt64,
        receivedAtDate: Date
    ) throws {
        guard nextSequenceNumber != UInt64.max else {
            throw PassiveCoreBluetoothCaptureRecorderError.sequenceNumberExhausted
        }

        try session.append(
            event,
            sequenceNumber: nextSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            receivedAtDate: receivedAtDate
        )
        nextSequenceNumber += 1
    }

    /// Records a Nembra observation-session boundary on the same actor and
    /// system-boot-relative monotonic clock as raw CoreBluetooth callback
    /// receipts. The watermark is captured atomically from the final raw record
    /// sequence already accepted by this recorder. This does not create a BLE
    /// event, claim an RF emission time, or infer scooter state.
    public func recordObservationBoundary(
        _ kind: PassiveBluetoothObservationBoundaryKind
    ) throws {
        try recordObservationBoundary(
            kind,
            observedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            observedAtDate: Date()
        )
    }

    /// Package-internal deterministic boundary path for focused recorder tests.
    /// Production clients intentionally cannot supply boundary clocks: the public
    /// producer above owns the monotonic receipt clock used for duration evidence.
    func recordObservationBoundary(
        _ kind: PassiveBluetoothObservationBoundaryKind,
        observedAtUptimeNanoseconds: UInt64,
        observedAtDate: Date
    ) throws {
        let recordSequenceWatermark = nextSequenceNumber - 1
        try session.appendObservationBoundary(
            PassiveBluetoothObservationBoundary(
                kind: kind,
                recordSequenceWatermark: recordSequenceWatermark,
                observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
                observedAtDate: observedAtDate
            )
        )
    }

    public func snapshot() -> PassiveBluetoothCaptureSession {
        session
    }

    public func encodedJSON(prettyPrinted: Bool = true) throws -> Data {
        try PassiveBluetoothCaptureJSON.encode(
            session,
            prettyPrinted: prettyPrinted
        )
    }
}

public enum PassiveCoreBluetoothCaptureRecorderError: Error, Equatable, Sendable {
    case sequenceNumberExhausted
}
