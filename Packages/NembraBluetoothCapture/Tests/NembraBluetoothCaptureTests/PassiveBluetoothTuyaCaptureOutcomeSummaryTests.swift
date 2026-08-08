import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Tuya capture outcome summary")
struct PassiveBluetoothTuyaCaptureOutcomeSummaryTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "capture-test-only"
    )

    private func session() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func policy() throws -> TuyaCandidateFragmentReassemblyPolicy {
        try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
    }

    private func appendValue(
        _ payload: [UInt8],
        service: String,
        characteristic: String,
        sequence: UInt64,
        to session: inout PassiveBluetoothCaptureSession
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: "target-A",
                serviceUUID: service,
                characteristicUUID: characteristic,
                origin: .notification,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: sequence * 100,
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }

    @Test("summary counts analyzer outcomes without reinterpreting them")
    func countsOutcomes() throws {
        var capture = try session()

        // Stream 1: completed candidate, malformed candidate, then one truncated
        // candidate at end-of-capture.
        try appendValue(
            [0x00, 0x01, 0x30, 0xAA],
            service: "A201",
            characteristic: "2B10",
            sequence: 1,
            to: &capture
        )
        try appendValue(
            [0x80],
            service: "A201",
            characteristic: "2B10",
            sequence: 2,
            to: &capture
        )
        try appendValue(
            [0x00, 0x02, 0x30, 0xAA],
            service: "A201",
            characteristic: "2B10",
            sequence: 3,
            to: &capture
        )

        // Stream 2: one independent completed candidate.
        try appendValue(
            [0x00, 0x01, 0x30, 0xBB],
            service: "A201",
            characteristic: "2B11",
            sequence: 4,
            to: &capture
        )

        let report = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: capture,
            peripheralIdentifier: "target-A",
            policy: policy()
        )
        let summary = report.outcomeSummary

        #expect(summary.streamCount == 2)
        #expect(summary.fragmentCount == 4)
        #expect(summary.completedCandidateCount == 2)
        #expect(summary.rejectedCandidateCount == 1)
        #expect(summary.incompleteAtBoundaryCount == 0)
        #expect(summary.incompleteAtEndCount == 1)
        #expect(summary.incompleteCandidateCount == 1)
        #expect(summary.unexpectedAnalyzerFailureCount == 0)
    }

    @Test("report with target evidence but no value streams summarizes to zero outcomes")
    func emptyAnalysisIsExplicitlyZero() throws {
        var capture = try session()
        try capture.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "target-A",
                state: .connected
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1)
        )

        let report = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: capture,
            peripheralIdentifier: "target-A",
            policy: policy()
        )
        let summary = report.outcomeSummary

        #expect(summary == .init(
            streamCount: 0,
            fragmentCount: 0,
            completedCandidateCount: 0,
            rejectedCandidateCount: 0,
            incompleteAtBoundaryCount: 0,
            incompleteAtEndCount: 0,
            unexpectedAnalyzerFailureCount: 0
        ))
    }
}
