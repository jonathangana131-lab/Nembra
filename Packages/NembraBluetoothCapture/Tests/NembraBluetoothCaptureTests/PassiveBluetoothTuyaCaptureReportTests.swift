import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Tuya capture report")
struct PassiveBluetoothTuyaCaptureReportTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "capture-test-only"
    )

    private func makeSession() throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func appendValue(
        to session: inout PassiveBluetoothCaptureSession,
        peripheral: String = "target-A",
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

    private func policy() throws -> TuyaCandidateFragmentReassemblyPolicy {
        try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
    }

    @Test("completed framing summary retains exact source provenance without raw byte duplication")
    func completedReportRetainsProvenance() throws {
        var session = try makeSession()
        let rawCallbackPayload: [UInt8] = [0x00, 0x02, 0x30, 0xAA, 0xBB]
        let candidateEncryptedPayload: [UInt8] = [0xAA, 0xBB]
        try appendValue(
            to: &session,
            payload: rawCallbackPayload,
            sequence: 7,
            uptime: 700
        )

        let report = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: session,
            peripheralIdentifier: "target-A",
            policy: policy()
        )

        #expect(report.schemaVersion == 1)
        #expect(report.capture.sessionID == session.id)
        #expect(report.capture.vehicleIdentity == identity)
        #expect(report.capture.sessionStartedAt == Date(timeIntervalSince1970: 1_000))
        #expect(report.capture.peripheralIdentifier == "target-A")
        #expect(report.capture.totalCaptureRecordCount == 1)
        #expect(report.analysisPolicy.maximumEncryptedMessageBytes == 64)
        #expect(report.analysisPolicy.maximumFragmentCount == 8)
        #expect(report.streams.count == 1)

        let stream = report.streams[0]
        #expect(stream.serviceIdentifier == "A201")
        #expect(stream.characteristicIdentifier == "2B10")
        #expect(stream.valueOrigin == PassiveBluetoothValueOrigin.notification.rawValue)
        #expect(stream.fragmentCount == 1)
        #expect(stream.fragments == [
            .init(
                analysisObservationIndex: 0,
                captureRecordIndex: 0,
                captureSequenceNumber: 7,
                receivedAtUptimeNanoseconds: 700,
                receivedAtDate: Date(timeIntervalSince1970: 7),
                continuityGeneration: 0,
                payloadByteCount: rawCallbackPayload.count
            )
        ])
        #expect(stream.events.count == 1)

        let event = stream.events[0]
        #expect(event.kind == .completed)
        #expect(event.startObservationIndex == 0)
        #expect(event.endObservationIndex == 0)
        #expect(event.lastAcceptedObservationIndex == 0)
        #expect(event.startSource == stream.fragments[0])
        #expect(event.endSource == stream.fragments[0])
        #expect(event.lastAcceptedSource == stream.fragments[0])
        #expect(event.completedMessage == .init(
            continuityGeneration: 0,
            protocolVersionByte: 0x30,
            protocolVersionHighNibble: 0x03,
            encryptedByteCount: candidateEncryptedPayload.count,
            fragmentCount: 1,
            firstReceiptUptimeNanoseconds: 700,
            lastReceiptUptimeNanoseconds: 700
        ))

        let data = try report.jsonData(prettyPrinted: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        #expect(try decoder.decode(PassiveBluetoothTuyaCaptureReport.self, from: data) == report)

        let encodedJSON = String(decoding: data, as: UTF8.self)
        #expect(encodedJSON.contains(Data(rawCallbackPayload).base64EncodedString()) == false)
        #expect(encodedJSON.contains(Data(candidateEncryptedPayload).base64EncodedString()) == false)
    }

    @Test("rejected candidates remain explicit and map back to the failing capture record")
    func rejectedCandidateRemainsExplicit() throws {
        var session = try makeSession()
        try appendValue(
            to: &session,
            payload: [0x80],
            sequence: 3,
            uptime: 300
        )

        let report = try PassiveBluetoothTuyaCaptureReportBuilder.make(
            session: session,
            peripheralIdentifier: "target-A",
            policy: policy()
        )

        #expect(report.streams.count == 1)
        #expect(report.streams[0].events.count == 1)
        let event = report.streams[0].events[0]
        #expect(event.kind == .rejectedCandidate)
        #expect(event.error == "malformedVarint")
        #expect(event.failingObservationIndex == 0)
        #expect(event.failingSource?.captureSequenceNumber == 3)
        #expect(event.completedMessage == nil)
    }

    @Test("automatic peripheral candidates ignore broad-scan advertisement-only devices")
    func attributablePeripheralSelectionIgnoresAdvertisements() throws {
        var session = try makeSession()
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "scan-noise",
                localName: "Nearby device"
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1)
        )
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "target-A",
                state: .connected
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 200,
            receivedAtDate: Date(timeIntervalSince1970: 2)
        )
        try appendValue(
            to: &session,
            peripheral: "target-A",
            payload: [0x00, 0x01, 0x30, 0xAA],
            sequence: 3,
            uptime: 300
        )

        #expect(
            PassiveBluetoothTuyaCaptureReportBuilder.attributablePeripheralIdentifiers(in: session)
                == ["target-A"]
        )
    }

    @Test("multiple attributable peripherals remain ambiguous instead of being guessed")
    func multiplePeripheralCandidatesRemainVisible() throws {
        var session = try makeSession()
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "target-A",
                state: .connected
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1)
        )
        try session.append(
            .connection(try PassiveBluetoothConnectionObservation(
                peripheralIdentifier: "target-B",
                state: .connected
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 200,
            receivedAtDate: Date(timeIntervalSince1970: 2)
        )

        #expect(
            PassiveBluetoothTuyaCaptureReportBuilder.attributablePeripheralIdentifiers(in: session)
                == ["target-A", "target-B"]
        )
    }
}
