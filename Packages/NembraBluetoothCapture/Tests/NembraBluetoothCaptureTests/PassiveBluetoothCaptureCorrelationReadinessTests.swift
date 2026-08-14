import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth capture correlation readiness")
struct PassiveBluetoothCaptureCorrelationReadinessTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("absent explicit target fails closed instead of looking like zero correlation evidence")
    func absentTargetFailsClosed() throws {
        var session = try makeSession()
        try appendConnection(
            peripheral: "observed-target",
            state: .connected,
            sequence: 1,
            uptime: 1_000,
            to: &session
        )
        try appendMarker(
            field: "Battery",
            displayedValue: "73%",
            sequence: 2,
            uptime: 1_100,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "missing-target"
        )

        #expect(report.disposition == .invalidPeripheralScope)
        #expect(!report.isReadyForOfflineCorrelation)
        #expect(report.stockAppMarkerCount == 1)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.targetValueObservationCount == 0)
        #expect(report.targetContinuityBreakCount == 0)
        #expect(report.knownByteContinuityBreakCount == 0)
        #expect(report.correlationLookbackNanoseconds == 2_000_000_000)
        #expect(report.correlationLookaheadNanoseconds == 2_000_000_000)
    }

    @Test("nonblank target identity is matched exactly instead of normalized")
    func targetIdentityRemainsOpaque() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "VALUE",
            payload: [0xAA],
            sequence: 1,
            uptime: 1_000,
            to: &session
        )
        try appendMarker(
            field: "Battery",
            displayedValue: "73%",
            sequence: 2,
            uptime: 1_100,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: " target-a "
        )

        #expect(report.disposition == .invalidPeripheralScope)
        #expect(report.peripheralIdentifier == " target-a ")
        #expect(report.targetValueObservationCount == 0)
        #expect(report.supportedMarkerCount == 0)
    }

    @Test("attributable target with no stock-app markers is not ready")
    func noMarkers() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "VALUE",
            payload: [0xAA],
            origin: .subscriptionUpdate,
            sequence: 1,
            uptime: 1_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a"
        )

        #expect(report.disposition == .noStockAppMarkers)
        #expect(report.stockAppMarkerCount == 0)
        #expect(report.targetValueObservationCount == 1)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.markerSupportFraction == 0)
    }

    @Test("connection-attributed target with markers but no values reports missing target values")
    func noTargetValues() throws {
        var session = try makeSession()
        try appendConnection(
            peripheral: "target-a",
            state: .connected,
            sequence: 1,
            uptime: 1_000,
            to: &session
        )
        try appendMarker(
            field: "Voltage",
            displayedValue: "39.8 V",
            sequence: 2,
            uptime: 1_100,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a"
        )

        #expect(report.disposition == .noTargetValueObservations)
        #expect(report.stockAppMarkerCount == 1)
        #expect(report.targetValueObservationCount == 0)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.distinctMarkerFields == ["Voltage"])
    }

    @Test("nearby target value makes the artifact structurally ready without claiming semantics")
    func localTargetValueIsReady() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "FFF1",
            payload: [0x01, 0x02],
            origin: .notification,
            sequence: 1,
            uptime: 2_900_000_000,
            to: &session
        )
        try appendMarker(
            field: "Battery",
            displayedValue: "73%",
            sequence: 2,
            uptime: 3_000_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )

        #expect(report.disposition == .readyForOfflineCorrelation)
        #expect(report.isReadyForOfflineCorrelation)
        #expect(report.peripheralIdentifier == "target-a")
        #expect(report.stockAppMarkerCount == 1)
        #expect(report.supportedMarkerCount == 1)
        #expect(report.unsupportedMarkerCount == 0)
        #expect(report.markerSupportFraction == 1)
        #expect(report.targetValueObservationCount == 1)
        #expect(report.targetContinuityBreakCount == 0)
        #expect(report.knownByteContinuityBreakCount == 0)
        #expect(report.correlationLookbackNanoseconds == 500_000_000)
        #expect(report.correlationLookaheadNanoseconds == 500_000_000)
        #expect(report.targetValueOrigins == [.notification])
        #expect(report.distinctMarkerFields == ["Battery"])
    }

    @Test("nearby unrelated peripheral values never satisfy target readiness")
    func unrelatedValuesDoNotSupportTargetMarkers() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "TARGET-FAR",
            payload: [0x01],
            sequence: 1,
            uptime: 1_000_000_000,
            to: &session
        )
        try appendValue(
            peripheral: "unrelated-b",
            characteristic: "OTHER-NEAR",
            payload: [0x02],
            sequence: 2,
            uptime: 2_950_000_000,
            to: &session
        )
        try appendMarker(
            field: "Current",
            displayedValue: "4.2 A",
            sequence: 3,
            uptime: 3_000_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 200_000_000,
            lookaheadNanoseconds: 200_000_000
        )

        #expect(report.disposition == .noMarkerLocalTargetValues)
        #expect(report.targetValueObservationCount == 1)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.targetValueOrigins == [.subscriptionUpdate])
        #expect(report.targetContinuityBreakCount == 0)
        #expect(report.knownByteContinuityBreakCount == 0)
    }

    @Test("selected-target disconnect fences pre-disconnect values from later markers")
    func targetDisconnectFencesCorrelation() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "BEFORE",
            payload: [0x10],
            sequence: 1,
            uptime: 2_900_000_000,
            to: &session
        )
        try appendConnection(
            peripheral: "target-a",
            state: .disconnected,
            sequence: 2,
            uptime: 2_950_000_000,
            to: &session
        )
        try appendMarker(
            field: "Power",
            displayedValue: "167 W",
            sequence: 3,
            uptime: 3_000_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )

        #expect(report.disposition == .noMarkerLocalTargetValues)
        #expect(report.targetValueObservationCount == 1)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.targetContinuityBreakCount == 1)
        #expect(report.knownByteContinuityBreakCount == 1)
    }

    @Test("global interruption fences correlation and is retained in readiness provenance")
    func globalInterruptionFencesCorrelation() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "BEFORE",
            payload: [0x10],
            sequence: 1,
            uptime: 2_900_000_000,
            to: &session
        )
        try appendInterruption(
            reason: "application lifecycle interrupted",
            sequence: 2,
            uptime: 2_950_000_000,
            to: &session
        )
        try appendMarker(
            field: "Power",
            displayedValue: "167 W",
            sequence: 3,
            uptime: 3_000_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )

        #expect(report.disposition == .noMarkerLocalTargetValues)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.targetContinuityBreakCount == 1)
        #expect(report.knownByteContinuityBreakCount == 1)
    }

    @Test("unrelated structured disconnect fences raw-byte readiness without becoming target attribution")
    func unrelatedDisconnectFencesRawByteReadiness() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "TARGET",
            payload: [0x10],
            sequence: 1,
            uptime: 2_900_000_000,
            to: &session
        )
        try appendConnection(
            peripheral: "unrelated-b",
            state: .disconnected,
            sequence: 2,
            uptime: 2_950_000_000,
            to: &session
        )
        try appendMarker(
            field: "Power",
            displayedValue: "167 W",
            sequence: 3,
            uptime: 3_000_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )

        #expect(report.disposition == .noMarkerLocalTargetValues)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.targetContinuityBreakCount == 0)
        #expect(report.knownByteContinuityBreakCount == 1)
    }

    @Test("post-break target evidence may support a post-break marker")
    func postBreakLocalEvidenceRemainsUsable() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "BEFORE",
            payload: [0x10],
            sequence: 1,
            uptime: 2_800_000_000,
            to: &session
        )
        try appendConnection(
            peripheral: "unrelated-b",
            state: .disconnected,
            sequence: 2,
            uptime: 2_900_000_000,
            to: &session
        )
        try appendValue(
            peripheral: "target-a",
            characteristic: "AFTER",
            payload: [0x11],
            sequence: 3,
            uptime: 2_980_000_000,
            to: &session
        )
        try appendMarker(
            field: "Power",
            displayedValue: "167 W",
            sequence: 4,
            uptime: 3_000_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 500_000_000,
            lookaheadNanoseconds: 500_000_000
        )

        #expect(report.disposition == .readyForOfflineCorrelation)
        #expect(report.supportedMarkerCount == 1)
        #expect(report.targetValueObservationCount == 2)
        #expect(report.targetContinuityBreakCount == 0)
        #expect(report.knownByteContinuityBreakCount == 1)
    }

    @Test("post-gap lookahead value cannot support a pre-gap marker")
    func lookaheadCandidateCannotCrossGap() throws {
        var session = try makeSession()
        try appendMarker(
            field: "Power",
            displayedValue: "167 W",
            sequence: 1,
            uptime: 3_000_000_000,
            to: &session
        )
        try appendConnection(
            peripheral: "unrelated-b",
            state: .disconnected,
            sequence: 2,
            uptime: 3_050_000_000,
            to: &session
        )
        try appendValue(
            peripheral: "target-a",
            characteristic: "AFTER",
            payload: [0x11],
            sequence: 3,
            uptime: 3_100_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 200_000_000,
            lookaheadNanoseconds: 200_000_000
        )

        #expect(report.disposition == .noMarkerLocalTargetValues)
        #expect(report.supportedMarkerCount == 0)
        #expect(report.targetValueObservationCount == 1)
        #expect(report.targetContinuityBreakCount == 0)
        #expect(report.knownByteContinuityBreakCount == 1)
    }

    @Test("partial marker coverage stays visible while preserving usable local evidence")
    func partialCoverage() throws {
        var session = try makeSession()
        try appendValue(
            peripheral: "target-a",
            characteristic: "BATTERY-NEAR",
            payload: [0x49],
            origin: .readResponse,
            sequence: 1,
            uptime: 1_000_000_000,
            to: &session
        )
        try appendMarker(
            field: "Battery",
            displayedValue: "73%",
            sequence: 2,
            uptime: 1_050_000_000,
            to: &session
        )
        try appendMarker(
            field: "Power",
            displayedValue: "0 W",
            sequence: 3,
            uptime: 5_000_000_000,
            to: &session
        )

        let report = PassiveBluetoothCaptureCorrelationReadiness.assess(
            session,
            peripheralIdentifier: "target-a",
            lookbackNanoseconds: 100_000_000,
            lookaheadNanoseconds: 100_000_000
        )

        #expect(report.disposition == .readyForOfflineCorrelation)
        #expect(report.stockAppMarkerCount == 2)
        #expect(report.supportedMarkerCount == 1)
        #expect(report.unsupportedMarkerCount == 1)
        #expect(report.markerSupportFraction == 0.5)
        #expect(report.correlationLookbackNanoseconds == 100_000_000)
        #expect(report.correlationLookaheadNanoseconds == 100_000_000)
        #expect(report.distinctMarkerFields == ["Battery", "Power"])
        #expect(report.targetValueOrigins == [.readResponse])
    }

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func appendValue(
        peripheral: String,
        service: String = "TEST",
        characteristic: String,
        payload: [UInt8],
        origin: PassiveBluetoothValueOrigin = .subscriptionUpdate,
        sequence: UInt64,
        uptime: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: peripheral,
                serviceUUID: service,
                characteristicUUID: characteristic,
                origin: origin,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence))
        )
    }

    private func appendMarker(
        field: String,
        displayedValue: String,
        sequence: UInt64,
        uptime: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .stockAppState(try PassiveBluetoothStockAppObservation(
                field: field,
                displayedValue: displayedValue
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence))
        )
    }

    private func appendConnection(
        peripheral: String,
        state: PassiveBluetoothConnectionState,
        sequence: UInt64,
        uptime: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: state
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence))
        )
    }

    private func appendInterruption(
        reason: String,
        sequence: UInt64,
        uptime: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: reason)),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence))
        )
    }
}
