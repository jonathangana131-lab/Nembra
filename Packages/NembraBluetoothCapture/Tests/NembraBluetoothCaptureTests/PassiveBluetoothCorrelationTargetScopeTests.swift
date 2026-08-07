import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth correlation target scope")
struct PassiveBluetoothCorrelationTargetScopeTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("unscoped correlation refuses mixed-peripheral value evidence")
    func unscopedMixedPeripheralsFailClosed() throws {
        var session = try makeSession()
        try appendValue(peripheral: "target-a", sequence: 1, uptime: 900, payload: [0xAA], to: &session)
        try appendMarker(sequence: 2, uptime: 1_000, to: &session)
        try appendValue(peripheral: "nearby-b", sequence: 3, uptime: 1_100, payload: [0xBB], to: &session)

        let windows = PassiveBluetoothCorrelation.windows(
            in: session,
            lookbackNanoseconds: 500,
            lookaheadNanoseconds: 500
        )

        #expect(windows.isEmpty)
    }

    @Test("explicit target correlation excludes nearby peripheral values")
    func explicitTargetFiltersCandidates() throws {
        var session = try makeSession()
        try appendValue(peripheral: "target-a", sequence: 1, uptime: 950, payload: [0xAA], to: &session)
        try appendMarker(sequence: 2, uptime: 1_000, to: &session)
        try appendValue(peripheral: "nearby-b", sequence: 3, uptime: 1_010, payload: [0xBB], to: &session)
        try appendValue(peripheral: "target-a", sequence: 4, uptime: 1_050, payload: [0xCC], to: &session)

        let window = try #require(PassiveBluetoothCorrelation.windows(
            in: session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 100,
            lookaheadNanoseconds: 100
        ).first)

        #expect(window.candidates.map(\.peripheralIdentifier) == ["target-a", "target-a"])
        #expect(window.candidates.map(\.sequenceNumber) == [1, 4])
        #expect(window.candidates.map(\.payload) == [Data([0xAA]), Data([0xCC])])
    }

    @Test("marker-only unscoped capture remains inspectable")
    func markerOnlySessionStillProducesWindow() throws {
        var session = try makeSession()
        try appendMarker(sequence: 1, uptime: 1_000, to: &session)

        let window = try #require(PassiveBluetoothCorrelation.windows(in: session).first)
        #expect(window.field == "Battery")
        #expect(window.displayedValue == "73%")
        #expect(window.candidates.isEmpty)
    }

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(vehicleIdentity: identity, startedAt: .now)
    }

    private func appendMarker(
        sequence: UInt64,
        uptime: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(
                field: "Battery",
                displayedValue: "73%"
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }

    private func appendValue(
        peripheral: String,
        sequence: UInt64,
        uptime: UInt64,
        payload: [UInt8],
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: "TEST",
                characteristicUUID: "FFF1",
                origin: .subscriptionUpdate,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: .now
        )
    }
}
