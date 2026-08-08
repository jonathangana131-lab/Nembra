import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture runtime manifest bridge")
struct PassiveBluetoothCaptureRuntimeManifestBridgeTests {
    private typealias Reader = PassiveBluetoothCaptureRuntimeBuildIdentityReader

    private let target = "11111111-2222-3333-4444-555555555555"
    private let buildIdentifier = "Capture Build V14-F1"
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let preparedAt = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("runtime-produced build identity is the manifest provenance source")
    func runtimeIdentityFlowsIntoManifest() throws {
        let runtimeIdentity = try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                Reader.sourceCommitSHAInfoDictionaryKey: commit.uppercased()
            ],
            executableData: Data("field executable".utf8)
        )

        let manifest = try PassiveBluetoothStationaryCaptureManifestBuilder.makeUsingRuntimeBuildIdentity(
            captureJSON: makeCapture(),
            experimentID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            runtimeBuildIdentity: runtimeIdentity,
            selectedPeripheralIdentifier: target.lowercased(),
            setup: defaultSetup()
        )

        #expect(manifest.schemaVersion == 2)
        #expect(manifest.experimentRecipeID == .es80FingerprintV1)
        #expect(manifest.nembraBuildIdentifier == buildIdentifier)
        #expect(manifest.nembraBuildCommitSHA == commit)
        #expect(manifest.sourceArtifact.selectedPeripheralIdentifier == target)
    }

    @Test("bridge cannot preserve an earlier build declaration when runtime identity changes")
    func changedRuntimeIdentityChangesManifestProvenance() throws {
        let firstCommit = commit
        let secondCommit = "fedcba9876543210fedcba9876543210fedcba98"
        let captureJSON = try makeCapture()

        let firstIdentity = try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                Reader.sourceCommitSHAInfoDictionaryKey: firstCommit
            ],
            executableData: Data("field executable a".utf8)
        )
        let secondIdentity = try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: "Capture Build V14-F2",
                Reader.sourceCommitSHAInfoDictionaryKey: secondCommit
            ],
            executableData: Data("field executable b".utf8)
        )

        let first = try makeManifest(captureJSON: captureJSON, runtimeBuildIdentity: firstIdentity)
        let second = try makeManifest(captureJSON: captureJSON, runtimeBuildIdentity: secondIdentity)

        #expect(first.nembraBuildIdentifier == buildIdentifier)
        #expect(first.nembraBuildCommitSHA == firstCommit)
        #expect(second.nembraBuildIdentifier == "Capture Build V14-F2")
        #expect(second.nembraBuildCommitSHA == secondCommit)
        #expect(first.sourceArtifact == second.sourceArtifact)
    }

    private func makeManifest(
        captureJSON: Data,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothStationaryCaptureManifest {
        try PassiveBluetoothStationaryCaptureManifestBuilder.makeUsingRuntimeBuildIdentity(
            captureJSON: captureJSON,
            experimentRecipe: .es80FingerprintV1,
            preparedAt: preparedAt,
            runtimeBuildIdentity: runtimeBuildIdentity,
            selectedPeripheralIdentifier: target,
            setup: defaultSetup()
        )
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
