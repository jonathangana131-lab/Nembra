import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-build runtime rendezvous")
struct PassiveBluetoothCaptureFieldBuildRendezvousTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableData = Data("accepted-field-executable".utf8)
    private let infoPlistData = Data("accepted-field-info-plist".utf8)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)

    @Test("exact field record, external record, and running bundle mint evidence-only rendezvous")
    func exactThreeWayRendezvous() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let fieldRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeFieldRecordJSON(externalData: externalData)
        )
        let runtime = try makeRuntimeIdentity(executableData: executableData, infoPlistData: infoPlistData)

        let rendezvous = try fieldRecord.makeRuntimeBoundRendezvous(
            matching: externalRecord,
            running: runtime
        )

        #expect(rendezvous.externalBuildRecordSHA256 == externalRecord.exactRecordSHA256)
        #expect(rendezvous.signedInstallableSHA256 == signedInstallableSHA256)
        #expect(rendezvous.buildIdentifier == buildIdentifier)
        #expect(rendezvous.buildInstanceID == buildInstanceID)
        #expect(rendezvous.sourceCommitSHA == sourceCommitSHA)
        #expect(rendezvous.executableSHA256 == sha256Hex(executableData))
        #expect(rendezvous.infoPlistSHA256 == sha256Hex(infoPlistData))
        #expect(rendezvous.experimentRecipeID == .es80FingerprintV1)
        #expect(rendezvous.procedureVersion == "V14")
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)
    }

    @Test("detached running executable fails closed")
    func detachedExecutableFailsClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let fieldRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeFieldRecordJSON(externalData: externalData)
        )
        let runtime = try makeRuntimeIdentity(
            executableData: Data("detached-executable".utf8),
            infoPlistData: infoPlistData
        )

        #expect(throws: PassiveBluetoothCaptureFieldBuildRendezvousError.runningBuildMismatch) {
            _ = try fieldRecord.makeRuntimeBoundRendezvous(matching: externalRecord, running: runtime)
        }
    }

    @Test("detached running raw Info.plist fails closed")
    func detachedInfoPlistFailsClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let fieldRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeFieldRecordJSON(externalData: externalData)
        )
        let runtime = try makeRuntimeIdentity(
            executableData: executableData,
            infoPlistData: Data("detached-info-plist".utf8)
        )

        #expect(throws: PassiveBluetoothCaptureFieldBuildRendezvousError.runningBuildMismatch) {
            _ = try fieldRecord.makeRuntimeBoundRendezvous(matching: externalRecord, running: runtime)
        }
    }

    @Test("same semantic external record with different exact bytes fails closed")
    func exactExternalRecordBytesRemainBound() throws {
        let compact = try makeExternalRecordJSON()
        let fieldRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeFieldRecordJSON(externalData: compact)
        )
        let pretty = try JSONSerialization.data(
            withJSONObject: externalRecordObject(),
            options: [.prettyPrinted, .sortedKeys]
        )
        let prettyRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(pretty)
        let runtime = try makeRuntimeIdentity(executableData: executableData, infoPlistData: infoPlistData)

        #expect(sha256Hex(compact) != sha256Hex(pretty))
        #expect(throws: PassiveBluetoothCaptureFieldBuildRendezvousError.externalBuildRecordMismatch) {
            _ = try fieldRecord.makeRuntimeBoundRendezvous(matching: prettyRecord, running: runtime)
        }
    }

    private func makeRuntimeIdentity(
        executableData: Data,
        infoPlistData: Data
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: sourceCommitSHA,
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    private func makeExternalRecordJSON() throws -> Data {
        try JSONSerialization.data(withJSONObject: externalRecordObject(), options: [.sortedKeys])
    }

    private func externalRecordObject() -> [String: Any] {
        [
            "schemaVersion": 3,
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func makeFieldRecordJSON(externalData: Data) throws -> Data {
        let object: [String: Any] = [
            "schemaVersion": 1,
            "externalBuildRecordSHA256": sha256Hex(externalData),
            "signedInstallableSHA256": signedInstallableSHA256,
            "signedInstallableKind": "ipa",
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": sha256Hex(executableData),
            "infoPlistSHA256": sha256Hex(infoPlistData),
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
