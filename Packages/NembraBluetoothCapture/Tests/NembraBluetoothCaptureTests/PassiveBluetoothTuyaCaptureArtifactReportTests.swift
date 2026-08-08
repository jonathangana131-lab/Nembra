import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Tuya artifact report")
struct PassiveBluetoothTuyaCaptureArtifactReportTests {
    private let identity = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "capture-test-only"
    )

    private func makeSession(peripherals: [String] = ["target-A"]) throws -> PassiveBluetoothCaptureSession {
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            vehicleIdentity: identity,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        for (offset, peripheral) in peripherals.enumerated() {
            let sequence = UInt64(offset + 1)
            try session.append(
                .connection(try PassiveBluetoothConnectionObservation(
                    peripheralIdentifier: peripheral,
                    state: .connected
                )),
                sequenceNumber: sequence,
                receivedAtUptimeNanoseconds: sequence * 100,
                receivedAtDate: Date(timeIntervalSince1970: Double(sequence))
            )
        }

        let valueSequence = UInt64(peripherals.count + 1)
        if let firstPeripheral = peripherals.first {
            try session.append(
                .value(try PassiveBluetoothValueObservation(
                    peripheralIdentifier: firstPeripheral,
                    serviceUUID: "A201",
                    characteristicUUID: "2B10",
                    origin: .notification,
                    payload: Data([0x00, 0x01, 0x30, 0xAA])
                )),
                sequenceNumber: valueSequence,
                receivedAtUptimeNanoseconds: valueSequence * 100,
                receivedAtDate: Date(timeIntervalSince1970: Double(valueSequence))
            )
        }

        return session
    }

    private func policy() throws -> TuyaCandidateFragmentReassemblyPolicy {
        try TuyaCandidateFragmentReassemblyPolicy(
            maximumEncryptedMessageBytes: 64,
            maximumFragmentCount: 8
        )
    }

    @Test("SHA-256 helper emits canonical lowercase digest")
    func canonicalSHA256() {
        let digest = PassiveBluetoothTuyaCaptureArtifactReportBuilder.sha256Hex(
            of: Data("abc".utf8)
        )
        #expect(
            digest == "ba7816bf8f01cfea414140de5dae2223" +
                "b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("artifact report binds analysis to the exact exported JSON bytes")
    func exactArtifactBinding() throws {
        let session = try makeSession()
        let compactArtifact = try PassiveBluetoothCaptureJSON.encode(
            session,
            prettyPrinted: false
        )
        let prettyArtifact = try PassiveBluetoothCaptureJSON.encode(
            session,
            prettyPrinted: true
        )

        let report = try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
            captureJSON: compactArtifact,
            policy: policy()
        )

        #expect(report.schemaVersion == 1)
        #expect(report.sourceArtifact.byteCount == compactArtifact.count)
        #expect(
            report.sourceArtifact.sha256 ==
                PassiveBluetoothTuyaCaptureArtifactReportBuilder.sha256Hex(of: compactArtifact)
        )
        #expect(
            report.sourceArtifact.sha256 !=
                PassiveBluetoothTuyaCaptureArtifactReportBuilder.sha256Hex(of: prettyArtifact)
        )
        #expect(report.analysis.capture.sessionID == session.id)
        #expect(report.analysis.capture.peripheralIdentifier == "target-A")
        #expect(report.analysis.streams.count == 1)

        let encoded = try report.jsonData(prettyPrinted: false)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        #expect(
            try decoder.decode(
                PassiveBluetoothTuyaCaptureArtifactReport.self,
                from: encoded
            ) == report
        )
    }

    @Test("advertisement-only artifacts never become target evidence")
    func advertisementOnlyArtifactHasNoAttributableTarget() throws {
        var session = try makeSession(peripherals: [])
        try session.append(
            .advertisement(try PassiveBluetoothAdvertisementObservation(
                peripheralIdentifier: "scan-noise",
                localName: "Nearby device",
                rssi: -44,
                isConnectable: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1)
        )
        let artifact = try PassiveBluetoothCaptureJSON.encode(
            session,
            prettyPrinted: false
        )

        #expect(throws: PassiveBluetoothTuyaCaptureArtifactReportError.noAttributablePeripheral) {
            try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
                captureJSON: artifact,
                policy: policy()
            )
        }
    }

    @Test("multiple target-attributable peripherals fail closed until explicitly selected")
    func ambiguousTargetRequiresExplicitSelection() throws {
        let session = try makeSession(peripherals: ["target-A", "target-B"])
        let artifact = try PassiveBluetoothCaptureJSON.encode(
            session,
            prettyPrinted: false
        )

        #expect(throws: PassiveBluetoothTuyaCaptureArtifactReportError.ambiguousPeripherals([
            "target-A", "target-B"
        ])) {
            try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
                captureJSON: artifact,
                policy: policy()
            )
        }

        let explicit = try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
            captureJSON: artifact,
            peripheralIdentifier: "target-A",
            policy: policy()
        )
        #expect(explicit.analysis.capture.peripheralIdentifier == "target-A")
    }

    @Test("requested peripheral must exist in attributable evidence")
    func requestedPeripheralMustBeAttributable() throws {
        let session = try makeSession()
        let artifact = try PassiveBluetoothCaptureJSON.encode(
            session,
            prettyPrinted: false
        )

        #expect(throws: PassiveBluetoothTuyaCaptureArtifactReportError
            .requestedPeripheralNotPresent(
                requested: "scan-noise",
                available: ["target-A"]
            )) {
            try PassiveBluetoothTuyaCaptureArtifactReportBuilder.make(
                captureJSON: artifact,
                peripheralIdentifier: "scan-noise",
                policy: policy()
            )
        }
    }
}
