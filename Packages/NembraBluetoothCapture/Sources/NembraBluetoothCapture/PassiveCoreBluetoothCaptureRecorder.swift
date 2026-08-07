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
