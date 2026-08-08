import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth -> Tuya candidate bridge")
struct PassiveBluetoothTuyaCandidateBridgeTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "unknown-2025-es80"
    )

    private func makeSession(
        id: UUID = UUID()
    ) throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: id,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        peripheral: String,
        service: String = "A201",
        characteristic: String = "2B10",
        origin: PassiveBluetoothValueOrigin = .notification,
        payload: [UInt8],
        sequence: UInt64,
        uptime: UInt64
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
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }

    private func appendConnection(
        to session: inout PassiveBluetoothCaptureSession,
        peripheral: String,
        state: PassiveBluetoothConnectionState = .connected,
        sequence: UInt64,
        uptime: UInt64
    ) throws {
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: peripheral,
                state: state
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }

    private func appendAdvertisement(
        to session: inout PassiveBluetoothCaptureSession,
        peripheral: String,
        sequence: UInt64,
        uptime: UInt64
    ) throws {
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: peripheral
            )),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }

    private func appendDisconnect(
        to session: inout PassiveBluetoothCaptureSession,
        peripheral: String,
        sequence: UInt64,
        uptime: UInt64
    ) throws {
        try appendConnection(
            to: &session,
            peripheral: peripheral,
            state: .disconnected,
            sequence: sequence,
            uptime: uptime
        )
    }

    private func appendInterruption(
        to session: inout PassiveBluetoothCaptureSession,
        sequence: UInt64,
        uptime: UInt64
    ) throws {
        try session.append(
            .interruption(try PassiveBluetoothCaptureInterruption(reason: "test gap")),
            sequenceNumber: sequence,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
        )
    }

    private func policy() throws -> TuyaCandidateFragmentReassemblyPolicy {
        try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
    }

    @Test("projects selected target with exact capture sequence scope and isolates GATT plus origin")
    func projectsTargetAndPreservesScopedChronology() throws {
        let sessionID = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
        var session = try makeSession(id: sessionID)
        let expectedContext = PassiveBluetoothTuyaCandidateCaptureContext(
            sessionID: session.id,
            vehicleIdentity: session.vehicleIdentity,
            sessionStartedAt: session.startedAt,
            peripheralIdentifier: "target-A"
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            service: "FFF0",
            characteristic: "FFF1",
            payload: [0, 1, 0x10, 0xA1],
            sequence: 1,
            uptime: 100
        )
        try appendValue(
            to: &session,
            peripheral: "noise-B",
            service: "FFF0",
            characteristic: "FFF1",
            payload: [0, 1, 0x10, 0xB1],
            sequence: 2,
            uptime: 110
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            service: "ABCD",
            characteristic: "0001",
            payload: [0, 1, 0x10, 0xA2],
            sequence: 3,
            uptime: 120
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            service: "FFF0",
            characteristic: "FFF1",
            origin: .readResponse,
            payload: [0, 1, 0x10, 0xA3],
            sequence: 4,
            uptime: 130
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            service: "FFF0",
            characteristic: "FFF1",
            payload: [0, 1, 0x10, 0xA4],
            sequence: 5,
            uptime: 140
        )

        let transcripts = try PassiveBluetoothTuyaCandidateBridge.transcripts(
            in: session,
            peripheralIdentifier: "target-A"
        )

        #expect(transcripts.count == 3)
        #expect(transcripts.allSatisfy { $0.captureContext == expectedContext })
        #expect(transcripts.map(\.sourceStream.valueStreamIdentity.serviceIdentifier) == [
            "FFF0", "ABCD", "FFF0"
        ])
        #expect(transcripts.map(\.sourceStream.valueStreamIdentity.characteristicIdentifier) == [
            "FFF1", "0001", "FFF1"
        ])
        #expect(transcripts.map(\.sourceStream.origin) == [
            .notification, .notification, .readResponse
        ])
        #expect(transcripts[0].fragments.map(\.captureSequenceNumber) == [1, 5])
        #expect(transcripts[1].fragments.map(\.captureSequenceNumber) == [3])
        #expect(transcripts[2].fragments.map(\.captureSequenceNumber) == [4])
        #expect(transcripts[0].fragments.map(\.observation.receiptSequenceNumber) == [1, 5])
        #expect(transcripts[1].fragments.map(\.observation.receiptSequenceNumber) == [3])
        #expect(transcripts[2].fragments.map(\.observation.receiptSequenceNumber) == [4])
        #expect(transcripts.flatMap(\.fragments).allSatisfy {
            $0.observation.receiptSequenceScope == sessionID.uuidString
        })
        #expect(transcripts[0].fragments.map(\.receivedAtDate) == [
            Date(timeIntervalSince1970: 1),
            Date(timeIntervalSince1970: 5)
        ])
        #expect(transcripts.flatMap(\.fragments).contains { $0.captureSequenceNumber == 2 } == false)
        #expect(transcripts[0].sourceFragment(atAnalysisObservationIndex: 1)?.captureSequenceNumber == 5)
        #expect(transcripts[0].sourceFragment(atAnalysisObservationIndex: -1) == nil)
        #expect(transcripts[0].sourceFragment(atAnalysisObservationIndex: 2) == nil)
    }

    @Test("equal uptime is valid when immutable capture sequence advances")
    func equalUptimeUsesScopedCaptureSequenceAuthority() throws {
        let sessionID = UUID(uuidString: "80000000-0000-0000-0000-000000000008")!
        var session = try makeSession(id: sessionID)
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [0, 2, 0x10, 0xAA],
            sequence: 1,
            uptime: 100
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [1, 0xBB],
            sequence: 2,
            uptime: 100
        )

        let analyses = try PassiveBluetoothTuyaCandidateBridge.analyze(
            session: session,
            peripheralIdentifier: "target-A",
            policy: policy()
        )
        let analysis = try #require(analyses.first)
        #expect(analysis.transcript.fragments.map(\.captureSequenceNumber) == [1, 2])
        #expect(analysis.transcript.fragments.map(\.observation.receiptSequenceNumber) == [1, 2])
        #expect(analysis.transcript.fragments.map(\.observation.receiptUptimeNanoseconds) == [100, 100])
        #expect(analysis.transcript.fragments.allSatisfy {
            $0.observation.receiptSequenceScope == sessionID.uuidString
        })

        guard case let .completed(start, end, message) = try #require(analysis.events.first) else {
            Issue.record("Expected scoped capture sequence to preserve equal-uptime callback order")
            return
        }
        #expect(start == 0)
        #expect(end == 1)
        #expect(message.encryptedBytes == [0xAA, 0xBB])
        #expect(message.firstReceiptSequenceNumber == 1)
        #expect(message.lastReceiptSequenceNumber == 2)
        #expect(message.receiptSequenceScope == sessionID.uuidString)
        #expect(message.firstReceiptUptimeNanoseconds == 100)
        #expect(message.lastReceiptUptimeNanoseconds == 100)
    }

    @Test("advertisement-only requested peripheral is absent from target authority")
    func advertisementOnlyTargetFailsClosed() throws {
        var session = try makeSession()
        try appendAdvertisement(
            to: &session,
            peripheral: "target-A",
            sequence: 1,
            uptime: 100
        )
        try appendConnection(
            to: &session,
            peripheral: "other-B",
            sequence: 2,
            uptime: 110
        )

        #expect(throws: PassiveBluetoothTuyaCandidateProjectionError
            .requestedPeripheralNotPresent(peripheralIdentifier: "target-A")) {
            try PassiveBluetoothTuyaCandidateBridge.transcripts(
                in: session,
                peripheralIdentifier: "target-A"
            )
        }
    }

    @Test("observed target with no values is distinct from missing target")
    func observedTargetWithoutValuesReturnsEmptyTranscripts() throws {
        var session = try makeSession()
        try appendConnection(
            to: &session,
            peripheral: "target-A",
            sequence: 1,
            uptime: 100
        )

        let transcripts = try PassiveBluetoothTuyaCandidateBridge.transcripts(
            in: session,
            peripheralIdentifier: "target-A"
        )
        #expect(transcripts.isEmpty)
    }

    @Test("unrelated disconnect does not split target continuity; target and global gaps do")
    func scopesContinuityToTarget() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [0, 2, 0x10, 0xAA],
            sequence: 1,
            uptime: 100
        )
        try appendDisconnect(
            to: &session,
            peripheral: "noise-B",
            sequence: 2,
            uptime: 110
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [1, 0xBB],
            sequence: 3,
            uptime: 200
        )
        try appendInterruption(
            to: &session,
            sequence: 4,
            uptime: 210
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [0, 1, 0x10, 0xCC],
            sequence: 5,
            uptime: 300
        )
        try appendDisconnect(
            to: &session,
            peripheral: "target-A",
            sequence: 6,
            uptime: 310
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [0, 1, 0x10, 0xDD],
            sequence: 7,
            uptime: 400
        )

        let analyses = try PassiveBluetoothTuyaCandidateBridge.analyze(
            session: session,
            peripheralIdentifier: "target-A",
            policy: policy()
        )
        let analysis = try #require(analyses.first)
        #expect(analysis.transcript.fragments.map(\.observation.continuityGeneration) == [0, 0, 1, 2])
        #expect(analysis.transcript.fragments.map(\.captureSequenceNumber) == [1, 3, 5, 7])
        #expect(analysis.transcript.fragments.map(\.observation.receiptSequenceNumber) == [1, 3, 5, 7])

        #expect(analysis.events.count == 3)
        guard case let .completed(firstStart, firstEnd, firstMessage) = analysis.events[0] else {
            Issue.record("Expected unrelated-device disconnect to preserve target candidate")
            return
        }
        #expect(firstStart == 0)
        #expect(firstEnd == 1)
        #expect(firstMessage.encryptedBytes == [0xAA, 0xBB])
        #expect(firstMessage.continuityGeneration == 0)

        guard case let .completed(secondStart, secondEnd, secondMessage) = analysis.events[1] else {
            Issue.record("Expected post-interruption packet zero to begin a new candidate")
            return
        }
        #expect(secondStart == 2)
        #expect(secondEnd == 2)
        #expect(secondMessage.encryptedBytes == [0xCC])
        #expect(secondMessage.continuityGeneration == 1)

        guard case let .completed(thirdStart, thirdEnd, thirdMessage) = analysis.events[2] else {
            Issue.record("Expected post-target-disconnect packet zero to begin a new candidate")
            return
        }
        #expect(thirdStart == 3)
        #expect(thirdEnd == 3)
        #expect(thirdMessage.encryptedBytes == [0xDD])
        #expect(thirdMessage.continuityGeneration == 2)
    }

    @Test("known capture gap terminates an incomplete candidate instead of splicing")
    func gapTerminatesIncompleteCandidate() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [0, 2, 0x10, 0xAA],
            sequence: 1,
            uptime: 100
        )
        try appendInterruption(
            to: &session,
            sequence: 2,
            uptime: 150
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [1, 0xBB],
            sequence: 3,
            uptime: 200
        )

        let analyses = try PassiveBluetoothTuyaCandidateBridge.analyze(
            session: session,
            peripheralIdentifier: "target-A",
            policy: policy()
        )
        let analysis = try #require(analyses.first)
        #expect(analysis.events == [
            .incompleteAtBoundary(
                startObservationIndex: 0,
                lastAcceptedObservationIndex: 0,
                nextObservationIndex: 1,
                boundary: .continuityGenerationChanged
            ),
            .rejectedCandidate(
                startObservationIndex: 1,
                lastAcceptedObservationIndex: nil,
                failingObservationIndex: 1,
                error: .unexpectedPacketIndex(expected: 0, actual: 1)
            )
        ])
    }

    @Test("empty raw value payload fails closed instead of disappearing from evidence")
    func rejectsEmptyPayloadProjection() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            peripheral: "target-A",
            service: "FFF0",
            characteristic: "FFF1",
            origin: .subscriptionUpdate,
            payload: [],
            sequence: 1,
            uptime: 100
        )

        #expect(throws: PassiveBluetoothTuyaCandidateProjectionError.emptyValuePayload(
            captureRecordIndex: 0,
            captureSequenceNumber: 1,
            serviceUUID: "FFF0",
            characteristicUUID: "FFF1",
            origin: .subscriptionUpdate
        )) {
            try PassiveBluetoothTuyaCandidateBridge.transcripts(
                in: session,
                peripheralIdentifier: "target-A"
            )
        }
    }

    @Test("blank target identity is rejected before projection")
    func rejectsBlankTarget() throws {
        let session = try makeSession()
        #expect(throws: PassiveBluetoothTuyaCandidateProjectionError.emptyPeripheralIdentifier) {
            try PassiveBluetoothTuyaCandidateBridge.transcripts(
                in: session,
                peripheralIdentifier: "   "
            )
        }
    }
}
