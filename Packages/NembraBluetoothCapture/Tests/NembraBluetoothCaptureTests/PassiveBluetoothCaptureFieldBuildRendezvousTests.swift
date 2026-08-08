import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureFieldBuildRendezvousTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let runtimeExecutableData = Data("field-runtime".utf8)
    private let runtimeInfoPlistData = Data("field-info-plist".utf8)
    private let ipaSHA256 = String(repeating: "c", count: 64)

    private var executableSHA256: String {
        sha256Hex(runtimeExecutableData)
    }

    private var infoPlistSHA256: String {
        sha256Hex(runtimeInfoPlistData)
    }

    @Test
    func exactEvidenceExternalRecordAndRunningBundleMintRendezvous() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        )
        let runtimeIdentity = try makeRuntimeIdentity()

        let rendezvous = try evidence.makeRuntimeBoundRendezvous(
            matching: externalRecord,
            running: runtimeIdentity
        )
        let reference = try rendezvous.makeSoftwareExportBuildReference()
        let expectedReference = try externalRecord.makeSoftwareExportBuildReference()

        #expect(rendezvous.exactEvidenceRecordSHA256 == evidence.exactEvidenceRecordSHA256)
        #expect(rendezvous.externalBuildRecordSHA256 == externalRecord.exactRecordSHA256)
        #expect(rendezvous.ipaSHA256 == ipaSHA256)
        #expect(rendezvous.ipaByteCount == 123_456)
        #expect(rendezvous.buildIdentifier == buildIdentifier)
        #expect(rendezvous.buildInstanceID == buildInstanceID)
        #expect(rendezvous.sourceCommitSHA == sourceCommitSHA)
        #expect(rendezvous.executableSHA256 == executableSHA256)
        #expect(rendezvous.infoPlistSHA256 == infoPlistSHA256)
        #expect(rendezvous.teamIdentifier == "ABCDE12345")
        #expect(rendezvous.experimentRecipeID == .es80FingerprintV1)
        #expect(rendezvous.procedureVersion == "V14")
        #expect(reference == expectedReference)
    }

    @Test
    func detachedRunningExecutableFailsEvenWhenExternalEvidenceAgrees() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        )
        let detachedRuntime = try makeRuntimeIdentity(
            executableData: Data("detached-runtime".utf8)
        )

        #expect(throws: PassiveBluetoothCaptureFieldBuildRendezvousError.runningBuildMismatch) {
            _ = try evidence.makeRuntimeBoundRendezvous(
                matching: externalRecord,
                running: detachedRuntime
            )
        }
    }

    @Test
    func detachedRuntimeInfoPlistFailsEvenWhenExecutableMatches() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        )
        let detachedRuntime = try makeRuntimeIdentity(
            infoPlistData: Data("detached-info-plist".utf8)
        )

        #expect(throws: PassiveBluetoothCaptureFieldBuildRendezvousError.runningBuildMismatch) {
            _ = try evidence.makeRuntimeBoundRendezvous(
                matching: externalRecord,
                running: detachedRuntime
            )
        }
    }

    @Test
    func exactExternalRecordBytesRemainPartOfRendezvous() throws {
        let object = externalRecordObject()
        let compact = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let prettyRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(pretty)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(compact))
        )

        #expect(throws: PassiveBluetoothCaptureFieldBuildRendezvousError.externalBuildRecordMismatch) {
            _ = try evidence.makeRuntimeBoundRendezvous(
                matching: prettyRecord,
                running: try makeRuntimeIdentity()
            )
        }
    }

    @Test
    func runtimeBoundRendezvousStillCannotOpenPhysicalGate() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        )

        _ = try evidence.makeRuntimeBoundRendezvous(
            matching: externalRecord,
            running: try makeRuntimeIdentity()
        )

        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
    }

    private func makeRuntimeIdentity(
        executableData: Data? = nil,
        infoPlistData: Data? = nil
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: sourceCommitSHA,
            ],
            executableData: executableData ?? runtimeExecutableData,
            infoPlistData: infoPlistData ?? runtimeInfoPlistData
        )
    }

    private func makeEvidenceJSON(
        externalBuildRecordSHA256: String
    ) throws -> Data {
        let object: [String: Any] = [
            "schemaVersion": 1,
            "authority": "signed-field-artifact-evidence-not-field-authorization",
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "bundleIdentifier": "com.jonathangana131.nembra",
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": "ABCDE12345",
            "signingAuthorities": ["Apple Development: Nembra Test"],
            "ipaSHA256": ipaSHA256,
            "ipaByteCount": 123_456,
            "executableSHA256": executableSHA256,
            "infoPlistSHA256": infoPlistSHA256,
            "externalBuildRecordSHA256": externalBuildRecordSHA256,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
            "executableSHA256": executableSHA256,
            "infoPlistSHA256": infoPlistSHA256,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
