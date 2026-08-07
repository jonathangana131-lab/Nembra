import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth stock-app correlation")
struct PassiveBluetoothCorrelationTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("nearby opaque values are ranked by time proximity without decoding them")
    func nearbyCandidates() throws {
        var session = try PassiveBluetoothCaptureSession(
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try appendValue(to: &session, sequence: 1, uptime: 1_000_000_000, characteristic: "FFF1", payload: [0x01])
        try appendValue(to: &session, sequence: 2, uptime: 2_900_000_000, characteristic: "FFF2", payload: [0x27, 0x10])
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Voltage", displayedValue: "39.8 V")),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_003)
        )
        try appendValue(to: &session, sequence: 4, uptime: 3_050_000_000, characteristic: "FFF3", payload: [0x9B, 0x7C])
        try appendValue(to: &session, sequence: 5, uptime: 5_100_000_000, characteristic: "FFF4", payload: [0xFF])

        let windows = PassiveBluetoothCorrelation.windows(
            in: session,
            field: "voltage",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )

        #expect(windows.count == 1)
        #expect(windows[0].field == "Voltage")
        #expect(windows[0].displayedValue == "39.8 V")
        #expect(windows[0].candidates.map(\.sequenceNumber) == [4, 2])
        #expect(windows[0].candidates[0].offsetSecondsFromMarker == 0.05)
        #expect(windows[0].candidates[1].offsetSecondsFromMarker == -0.1)
        #expect(windows[0].candidates[0].payloadHex == "9B 7C")
    }

    @Test("known continuity interruption prevents cross-gap correlation")
    func interruptionIsHardBoundary() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(to: &session, sequence: 1, uptime: 10_000, characteristic: "OLD", payload: [0xAA])
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "disconnect")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 10_100,
            receivedAtDate: .now
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Current", displayedValue: "4.2 A")),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 10_200,
            receivedAtDate: .now
        )
        try appendValue(to: &session, sequence: 4, uptime: 10_300, characteristic: "NEW", payload: [0xBB])

        let window = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            lookbackNanoseconds: 1_000,
            lookaheadNanoseconds: 1_000
        ).first)

        #expect(window.candidates.map(\.characteristicUUID) == ["NEW"])
    }

    @Test("unscoped imported correlation fails closed on mixed peripheral GATT evidence")
    func mixedPeripheralEvidenceFailsClosed() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 2_900_000_000,
            characteristic: "A-VALUE",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Battery", displayedValue: "73%")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            receivedAtDate: .now
        )
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 3_050_000_000,
            characteristic: "B-VALUE",
            payload: [0x02],
            peripheralIdentifier: "unrelated-b"
        )

        let windows = PassiveBluetoothCorrelation.windows(
            in: session,
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )

        #expect(windows.isEmpty)
    }

    @Test("unscoped imported correlation treats another peripheral connection as attribution ambiguity")
    func mixedConnectionEvidenceFailsClosed() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 2_900_000_000,
            characteristic: "A-VALUE",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendConnection(
            to: &session,
            sequence: 2,
            uptime: 2_950_000_000,
            peripheralIdentifier: "unrelated-b",
            state: .connected
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Battery", displayedValue: "73%")),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            receivedAtDate: .now
        )

        #expect(PassiveBluetoothCorrelation.windows(in: session).isEmpty)

        let explicit = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: "target-a"
        )?.first)
        #expect(explicit.candidates.map(\.characteristicUUID) == ["A-VALUE"])
    }

    @Test("explicit target correlation filters mixed imported evidence")
    func explicitTargetFiltersMixedPeripheralEvidence() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 2_900_000_000,
            characteristic: "A-VALUE",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Battery", displayedValue: "73%")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            receivedAtDate: .now
        )
        try appendValue(
            to: &session,
            sequence: 3,
            uptime: 3_050_000_000,
            characteristic: "B-VALUE",
            payload: [0x02],
            peripheralIdentifier: "unrelated-b"
        )

        let window = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )?.first)

        #expect(window.candidates.map(\.peripheralIdentifier) == ["target-a"])
        #expect(window.candidates.map(\.characteristicUUID) == ["A-VALUE"])
    }

    @Test("explicit target correlation ignores unrelated peripheral disconnect boundaries")
    func unrelatedDisconnectDoesNotSplitExplicitTarget() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 2_900_000_000,
            characteristic: "A-BEFORE",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendConnection(
            to: &session,
            sequence: 2,
            uptime: 2_950_000_000,
            peripheralIdentifier: "unrelated-b",
            state: .disconnected
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Power", displayedValue: "167 W")),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            receivedAtDate: .now
        )
        try appendValue(
            to: &session,
            sequence: 4,
            uptime: 3_050_000_000,
            characteristic: "A-AFTER",
            payload: [0x02],
            peripheralIdentifier: "target-a"
        )

        let window = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )?.first)

        #expect(Set(window.candidates.map(\.characteristicUUID)) == ["A-BEFORE", "A-AFTER"])
    }

    @Test("explicit target disconnect remains a hard correlation boundary")
    func targetDisconnectStillSplitsExplicitTarget() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendValue(
            to: &session,
            sequence: 1,
            uptime: 2_900_000_000,
            characteristic: "A-BEFORE",
            payload: [0x01],
            peripheralIdentifier: "target-a"
        )
        try appendConnection(
            to: &session,
            sequence: 2,
            uptime: 2_950_000_000,
            peripheralIdentifier: "target-a",
            state: .disconnected
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Power", displayedValue: "167 W")),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3_000_000_000,
            receivedAtDate: .now
        )
        try appendValue(
            to: &session,
            sequence: 4,
            uptime: 3_050_000_000,
            characteristic: "A-AFTER",
            payload: [0x02],
            peripheralIdentifier: "target-a"
        )

        let window = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )?.first)

        #expect(window.candidates.map(\.characteristicUUID) == ["A-AFTER"])
    }

    @Test("absent explicit target is distinct from an observed target with no nearby values")
    func absentExplicitTargetFailsClosed() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try appendConnection(
            to: &session,
            sequence: 1,
            uptime: 1_000,
            peripheralIdentifier: "observed-target",
            state: .connected
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Battery", displayedValue: "73%")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 1_100,
            receivedAtDate: .now
        )

        #expect(PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: "missing-target"
        ) == nil)

        let observed = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: "observed-target"
        ))
        #expect(observed.count == 1)
        #expect(observed[0].candidates.isEmpty)
    }

    @Test("overflow-safe lookahead still includes later values")
    func uptimeOverflowSafety() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        let markerTime = UInt64.max - 5
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Power", displayedValue: "167 W")),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: markerTime,
            receivedAtDate: .now
        )
        try appendValue(
            to: &session,
            sequence: 2,
            uptime: UInt64.max - 1,
            characteristic: "POWER-CANDIDATE",
            payload: [0x00, 0xA7]
        )

        let window = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            lookbackNanoseconds: 0,
            lookaheadNanoseconds: 100
        ).first)
        #expect(window.candidates.map(\.sequenceNumber) == [2])
    }

    @Test("field filter does not reinterpret marker spelling")
    func fieldFiltering() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Battery", displayedValue: "73%")),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(field: "Voltage", displayedValue: "39.8 V")),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: .now
        )

        let windows = PassiveBluetoothCorrelation.windows(in: session, field: "BATTERY")
        #expect(windows.map(\.field) == ["Battery"])
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        characteristic: String,
        payload: [UInt8],
        peripheralIdentifier: String = "physical-es80-placeholder"
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheralIdentifier,
                serviceUUID: "TEST",
                characteristicUUID: characteristic,
                origin: .subscriptionUpdate,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }

    private func appendConnection(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64,
        peripheralIdentifier: String,
        state: PassiveBluetoothConnectionState
    ) throws {
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheralIdentifier,
                state: state
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }
}
