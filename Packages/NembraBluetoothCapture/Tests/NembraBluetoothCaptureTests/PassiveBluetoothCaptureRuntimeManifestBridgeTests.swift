import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture trusted runtime manifest bridge")
struct PassiveBluetoothCaptureRuntimeManifestBridgeTests {
    private typealias Reader = PassiveBluetoothCaptureRuntimeBuildIdentityReader
    private typealias RecordReader = PassiveBluetoothCaptureTrustedBuildRecordReader

    private let target = "11111111-2222-3333-4444-555555555555"
    private let buildIdentifier = "Capture Build V14-F1"
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let preparedAt = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("trusted runtime binding is the manifest provenance source")
    func trustedBindingFlowsIntoManifest() throws {
        let binding = try makeBinding(
            buildIdentifier: buildIdentifier,
            sourceCommit: commit.uppercased(),
            executableData: Data("field executable".utf8)
        )

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.makeUsingRuntimeBuildBinding(
            captureJSON: makeCapture(),
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            runtimeBuildBinding: binding,
            selectedPeripheralIdentifier: target.lowercased(),
            setup: defaultSetup()
        )

        #expect(binding.experimentRecipeID == .es80FingerprintV1)
        #expect(binding.procedureVersion == "V14")
        #expect(manifest.schemaVersion == 2)
        #expect(manifest.experimentRecipeID == binding.experimentRecipeID)
        #expect(manifest.nembraBuildIdentifier == binding.buildIdentifier)
        #expect(manifest.nembraBuildCommitSHA == binding.sourceCommitSHA)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target)
    }

    @Test("changing the accepted trusted binding changes provenance without changing capture evidence")
    func changedTrustedBindingChangesManifestProvenance() throws {
        let firstCommit = commit
        let secondCommit = "fedcba9876543210fedcba9876543210fedcba98"
        let captureJSON = try makeCapture()

        let firstBinding = try makeBinding(
            buildIdentifier: buildIdentifier,
            sourceCommit: firstCommit,
            executableData: Data("field executable a".utf8)
        )
        let secondBinding = try makeBinding(
            buildIdentifier: "Capture Build V14-F2",
            sourceCommit: secondCommit,
            executableData: Data("field executable b".utf8)
        )

        let first = try makeManifest(captureJSON: captureJSON, runtimeBuildBinding: firstBinding)
        let second = try makeManifest(captureJSON: captureJSON, runtimeBuildBinding: secondBinding)

        #expect(first.nembraBuildIdentifier == buildIdentifier)
        #expect(first.nembraBuildCommitSHA == firstCommit)
        #expect(second.nembraBuildIdentifier == "Capture Build V14-F2")
        #expect(second.nembraBuildCommitSHA == secondCommit)
        #expect(first.sourceArtifact == second.sourceArtifact)
    }

    @Test("unmatched runtime declarations cannot mint manifest authority")
    func unmatchedRuntimeIdentityCannotBecomeBinding() throws {
        let runtimeIdentity = try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                Reader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: Data("field executable".utf8)
        )
        let trustedRecord = try makeTrustedRecord(
            buildIdentifier: buildIdentifier,
            sourceCommit: "fedcba9876543210fedcba9876543210fedcba98",
            executableSHA256: runtimeIdentity.executableSHA256
        )

        do {
            _ = try PassiveBluetoothCaptureBuildPreflight.evaluate(
                runtimeIdentity: runtimeIdentity,
                trustedRecord: trustedRecord
            )
            Issue.record("expected trusted build preflight to reject an unmatched source declaration")
        } catch let error as PassiveBluetoothCaptureBuildPreflightError {
            #expect(error == .sourceCommitSHAMismatch)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    private func makeManifest(
        captureJSON: Data,
        runtimeBuildBinding: PassiveBluetoothCaptureRuntimeBuildBinding
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        try PassiveBluetoothStationaryCaptureManifestBuilder.makeUsingRuntimeBuildBinding(
            captureJSON: captureJSON,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            runtimeBuildBinding: runtimeBuildBinding,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )
    }

    private func makeBinding(
        buildIdentifier: String,
        sourceCommit: String,
        executableData: Data
    ) throws -> PassiveBluetoothCaptureRuntimeBuildBinding {
        let runtimeIdentity = try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                Reader.sourceCommitSHAInfoDictionaryKey: sourceCommit,
            ],
            executableData: executableData
        )
        let trustedRecord = try makeTrustedRecord(
            buildIdentifier: buildIdentifier,
            sourceCommit: sourceCommit.lowercased(),
            executableSHA256: runtimeIdentity.executableSHA256
        )
        return try PassiveBluetoothCaptureBuildPreflight.evaluate(
            runtimeIdentity: runtimeIdentity,
            trustedRecord: trustedRecord
        )
    }

    private func makeTrustedRecord(
        buildIdentifier: String,
        sourceCommit: String,
        executableSHA256: String
    ) throws -> PassiveBluetoothCaptureTrustedBuildRecord {
        let object: [String: Any] = [
            "schemaVersion": 1,
            "buildIdentifier": buildIdentifier,
            "sourceCommitSHA": sourceCommit,
            "executableSHA256": executableSHA256,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try RecordReader.decodeTrustedRecord(data)
    }

    private func defaultSetup() -> PassiveBluetoothStationaryCaptureSetup {
        .init(
            chargerState: .disconnected,
            executionContext: .foregroundUnlockedScreenOn,
            stockAppReferenceSetup: .none
        )
    }

    private func makeCapture() throws -> Data {
        let startedAt = Date(timeIntervalSince1970: 1_780_000_000)
        var session = try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            vehicleIdentity: VehicleIdentity(
                manufacturer: "AOVOPRO",
                model: "ES80",
                displayName: "AOVOPRO ES80",
                protocolFamily: "unverified-tuya"
            ),
            startedAt: startedAt
        )

        try session.append(
            .service(try PassiveBluetoothServiceObservation(
                peripheralIdentifier: target,
                serviceUUID: "FFE0",
                isPrimary: true
            )),
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: startedAt.addingTimeInterval(1)
        )
        try session.append(
            .characteristic(try PassiveBluetoothCharacteristicObservation(
                peripheralIdentifier: target,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                properties: [.notify]
            )),
            sequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2,
            receivedAtDate: startedAt.addingTimeInterval(2)
        )
        try session.append(
            .value(try PassiveBluetoothValueObservation(
                peripheralIdentifier: target,
                serviceUUID: "FFE0",
                characteristicUUID: "FFE1",
                origin: .subscriptionUpdate,
                payload: Data([0x01, 0x02])
            )),
            sequenceNumber: 3,
            receivedAtUptimeNanoseconds: 3,
            receivedAtDate: startedAt.addingTimeInterval(3)
        )

        return try PassiveBluetoothCaptureJSON.encode(session)
    }
}
