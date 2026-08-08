import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Tuya capture report v2")
struct PassiveBluetoothTuyaCaptureReportV2Tests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    @Test("report preserves scoped receipt authority and packet-zero restart")
    func preservesCurrentAnalyzerTruth() throws {
        let sessionID = UUID(uuidString: "72000000-0000-0000-0000-000000000007")!
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        try appendValue(
            to: &session,
            payload: [0, 2, 0x10, 0xAA],
            sequence: 1,
            uptime: 100
        )
        try appendValue(
            to: &session,
            payload: [0, 1, 0x10, 0xCC],
            sequence: 2,
            uptime: 110
        )

        let report = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: session,
            peripheralIdentifier: "target-A",
            policy: try TuyaCandidateFragmentReassemblyPolicy(
                maximumEncryptedMessageBytes: 64,
                maximumFragmentCount: 8
            )
        )

        #expect(report.schemaVersion == 2)
        let stream = try #require(report.streams.first)
        #expect(stream.fragments.map(\.captureSequenceNumber) == [1, 2])
        #expect(stream.fragments.map(\.receiptSequenceNumber) == [1, 2])
        #expect(stream.fragments.allSatisfy { $0.receiptSequenceScope == sessionID.uuidString })
        #expect(stream.events.count == 2)
        #expect(stream.events[0].kind == .incompleteAtBoundary)
        #expect(stream.events[0].boundary == "candidatePacketZeroRestart")
        #expect(stream.events[0].startSource?.captureSequenceNumber == 1)
        #expect(stream.events[0].nextSource?.captureSequenceNumber == 2)
        #expect(stream.events[1].kind == .completed)
        #expect(stream.events[1].completedMessage?.receiptSequenceScope == sessionID.uuidString)
        #expect(stream.events[1].completedMessage?.firstReceiptSequenceNumber == 2)
        #expect(stream.events[1].completedMessage?.lastReceiptSequenceNumber == 2)
        #expect(stream.events[1].completedMessage?.encryptedByteCount == 1)
    }

    @Test("artifact byte ceiling rejects oversized bytes before any JSON decode")
    func byteCeilingRunsBeforeDecode() throws {
        let malformedOversized = Data(repeating: 0x7B, count: 5)
        #expect(throws: PassiveBluetoothCaptureArtifactInputPolicyError
            .sourceArtifactExceedsMaximumBytes(maximumBytes: 4)) {
            try PassiveBluetoothCaptureArtifactInputPolicy.validateByteCount(
                malformedOversized.count,
                maximumBytes: 4
            )
        }
    }

    @Test("bounded file ingress accepts exact limit and rejects first excess byte")
    func boundedFileIngress() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-offline-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let exactURL = directory.appendingPathComponent("exact.bin")
        let oversizedURL = directory.appendingPathComponent("oversized.bin")
        let exact = Data([0, 1, 2, 3])
        try exact.write(to: exactURL)
        try Data([0, 1, 2, 3, 4]).write(to: oversizedURL)

        #expect(try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
            at: exactURL,
            maximumBytes: 4
        ) == exact)
        #expect(throws: PassiveBluetoothCaptureArtifactInputPolicyError
            .sourceArtifactExceedsMaximumBytes(maximumBytes: 4)) {
            _ = try PassiveBluetoothCaptureArtifactInputPolicy.readExactBytes(
                at: oversizedURL,
                maximumBytes: 4
            )
        }
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        payload: [UInt8],
        sequence: UInt64,
        uptime: UInt64
    ) throws {
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: "target-A",
                serviceUUID: "A201",
                characteristicUUID: "2B10",
                origin: .notification,
                payload: Data(payload)
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }
}
