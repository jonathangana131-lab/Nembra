import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth capture recorder")
struct PassiveCoreBluetoothCaptureRecorderTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("recorder supplies a strict sequence while preserving equal monotonic timestamps")
    func orderedTimeline() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            id: UUID(uuidString: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB")!,
            vehicleIdentity: identity,
            startedAt: startedAt
        )

        let first = PassiveBluetoothCaptureEvent.stockAppState(
            try PassiveBluetoothStockAppObservation(
                field: "battery",
                displayedValue: "73%"
            )
        )
        let second = PassiveBluetoothCaptureEvent.stockAppState(
            try PassiveBluetoothStockAppObservation(
                field: "voltage",
                displayedValue: "39.8 V"
            )
        )

        try await recorder.record(
            first,
            receivedAtUptimeNanoseconds: 42,
            receivedAtDate: startedAt
        )
        try await recorder.record(
            second,
            receivedAtUptimeNanoseconds: 42,
            receivedAtDate: startedAt.addingTimeInterval(0.001)
        )

        let snapshot = await recorder.snapshot()
        #expect(snapshot.startedAt == startedAt)
        #expect(snapshot.records.map(\.sequenceNumber) == [1, 2])
        #expect(snapshot.records.map(\.receivedAtUptimeNanoseconds) == [42, 42])
        #expect(snapshot.records.map(\.event) == [first, second])
    }

    @Test("recorder rejects monotonic time moving backward through core validation")
    func backwardClockRejected() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let event = PassiveBluetoothCaptureEvent.interruption(
            try PassiveBluetoothCaptureInterruption(reason: "test")
        )

        try await recorder.record(
            event,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_001)
        )

        await #expect(throws: PassiveBluetoothCaptureValidationError.nonMonotonicReceiptTime) {
            try await recorder.record(
                event,
                receivedAtUptimeNanoseconds: 99,
                receivedAtDate: Date(timeIntervalSince1970: 1_700_000_002)
            )
        }

        let snapshot = await recorder.snapshot()
        #expect(snapshot.records.count == 1)
    }

    @Test("JSON export round trips through the versioned core codec")
    func jsonExport() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let observation = try PassiveBluetoothAdvertisementObservation(
            peripheralIdentifier: "11111111-2222-3333-4444-555555555555",
            localName: "ES80-test",
            serviceUUIDs: ["FD50"]
        )
        try await recorder.record(
            .advertisement(observation),
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_000.125)
        )

        let encoded = try await recorder.encodedJSON(prettyPrinted: false)
        let decoded = try PassiveBluetoothCaptureJSON.decode(encoded)
        let snapshot = await recorder.snapshot()

        #expect(decoded == snapshot)
    }
}
