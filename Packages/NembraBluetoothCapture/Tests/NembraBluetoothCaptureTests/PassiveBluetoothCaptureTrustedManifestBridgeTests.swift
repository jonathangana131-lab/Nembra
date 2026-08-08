import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture trusted manifest bridge")
struct PassiveBluetoothCaptureTrustedManifestBridgeTests {
    private typealias RuntimeReader = PassiveBluetoothCaptureRuntimeBuildIdentityReader
    private typealias TrustedReader = PassiveBluetoothCaptureTrustedBuildRecordReader

    private let target = "11111111-2222-3333-4444-555555555555"
    private let preparedAt = Date(timeIntervalSince1970: 1_780_000_000)
    private let firstBuildIdentifier = "Capture Build V14-0123456789ab"
    private let firstCommit = "0123456789abcdef0123456789abcdef01234567"

    @Test("matched trusted build binding is the only build/recipe source projected into schema v2")
    func trustedBindingFlowsIntoManifest() throws {
        let binding = try makeBinding(
            buildIdentifier: firstBuildIdentifier,
            commit: firstCommit,
            executableBytes: Data("field executable a".utf8)
        )
        let captureJSON = try makeCapture()

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.makeUsingTrustedBuildBinding(
            captureJSON: captureJSON,
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            preparedAt: preparedAt,
            trustedBuildBinding: binding,
            selectedPeripheralIdentifier: target.lowercased(),
            setup: defaultSetup()
        )

        #expect(binding.experimentRecipeID == .es80FingerprintV1)
        #expect(binding.procedureVersion == "V14")
        #expect(manifest.schemaVersion == 2)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildIdentifier == firstBuildIdentifier)
        #expect(manifest.nembraBuildCommitSHA == firstCommit)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target)
        #expect(manifest.sourceArtifact.byteCount == captureJSON.count)
    }

    @Test("changing the independently matched build changes manifest provenance, not capture evidence")
    func changedTrustedBindingChangesOnlyBuildProjection() throws {
        let captureJSON = try makeCapture()
        let first = try makeManifest(
            captureJSON: captureJSON,
            binding: makeBinding(
                buildIdentifier: firstBuildIdentifier,
                commit: firstCommit,
                executableBytes: Data("field executable a".utf8)
            )
        )
        let second = try makeManifest(
            captureJSON: captureJSON,
            binding: makeBinding(
                buildIdentifier: "Capture Build V14-fedcba987654",
                commit: "fedcba9876543210fedcba9876543210fedcba98",
                executableBytes: Data("field executable b".utf8)
            )
        )

        #expect(first.nembraBuildIdentifier == firstBuildIdentifier)
        #expect(first.nembraBuildCommitSHA == firstCommit)
        #expect(second.nembraBuildIdentifier == "Capture Build V14-fedcba987654")
        #expect(second.nembraBuildCommitSHA == "fedcba9876543210fedcba9876543210fedcba98")
        #expect(first.experimentRecipeID == second.experimentRecipeID)
        #expect(first.sourceArtifact == second.sourceArtifact)
        #expect(first.evidenceSummary == second.evidenceSummary)
    }

    @Test("a self-consistent trusted record cannot be reused for different runtime executable bytes")
    func runtimeByteMismatchCannotReachManifestProjection() throws {
        let record = try decodeTrustedRecord(
            buildIdentifier: firstBuildIdentifier,
            commit: firstCommit,
            executableBytes: Data("accepted executable".utf8)
        )
        let differentRuntime = try RuntimeReader.resolveEmbeddedMetadata(
            infoDictionary: [
                RuntimeReader.buildIdentifierInfoDictionaryKey: firstBuildIdentifier,
                RuntimeReader.sourceCommitSHAInfoDictionaryKey: firstCommit,
            ],
            executableData: Data("different executable".utf8)
        )

        do {
            _ = try PassiveBluetoothCaptureBuildPreflight.evaluate(
                runtimeIdentity: differentRuntime,
                trustedRecord: record
            )
            Issue.record("a mismatched runtime must not mint the trusted binding required by manifest projection")
        } catch let error as PassiveBluetoothCaptureBuildPreflightError {
            #expect(error == .executableSHA256Mismatch)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    private func makeManifest(
        captureJSON: Data,
        binding: PassiveBluetoothCaptureRuntimeBuildBinding
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        try PassiveBluetoothStationaryCaptureManifestBuilder.makeUsingTrustedBuildBinding(
            captureJSON: captureJSON,
            preparedAt: preparedAt,
            trustedBuildBinding: binding,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )
    }

    private func makeBinding(
        buildIdentifier: String,
        commit: String,
        executableBytes: Data
    ) throws -> PassiveBluetoothCaptureRuntimeBuildBinding {
        let runtime = try RuntimeReader.resolveEmbeddedMetadata(
            infoDictionary: [
                RuntimeReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                RuntimeReader.sourceCommitSHAInfoDictionaryKey: commit.uppercased(),
            ],
            executableData: executableBytes
        )
        let record = try decodeTrustedRecord(
            buildIdentifier: buildIdentifier,
            commit: commit,
            executableBytes: executableBytes
        )
        return try PassiveBluetoothCaptureBuildPreflight.evaluate(
            runtimeIdentity: runtime,
            trustedRecord: record
        )
    }

    private func decodeTrustedRecord(
        buildIdentifier: String,
        commit: String,
        executableBytes: Data
    ) throws -> PassiveBluetoothCaptureTrustedBuildRecord {
        let executableSHA256 = try RuntimeReader.resolveEmbeddedMetadata(
            infoDictionary: [
                RuntimeReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                RuntimeReader.sourceCommitSHAInfoDictionaryKey: commit,
            ],
            executableData: executableBytes
        ).executableSHA256

        let object: [String: Any] = [
            "schemaVersion": 1,
            "buildIdentifier": buildIdentifier,
            "sourceCommitSHA": commit,
            "executableSHA256": executableSHA256,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try TrustedReader.decodeTrustedRecord(data)
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
