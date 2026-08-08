import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureSignedFieldArtifactEvidenceTests {
    private let sourceCommitSHA = "1111111111111111111111111111111111111111"
    private let buildInstanceID = "12345678-1234-4234-8234-123456789abc"
    private let executableData = Data("field-runtime".utf8)
    private let infoPlistData = Data("field-info-plist".utf8)

    private var buildIdentifier: String { "Capture Build V14-\(sourceCommitSHA.prefix(12))" }
    private var executableSHA256: String { sha256Hex(executableData) }
    private var infoPlistSHA256: String { sha256Hex(infoPlistData) }

    @Test
    func canonicalSchemaV2BindsExactEvidenceExternalRecordAndRunningBundle() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidenceData = try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        let evidence = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(evidenceData)
        let runtimeIdentity = try makeRuntimeIdentity()

        let reference = try evidence.makeMechanicallyBoundSoftwareExportReference(
            matching: externalRecord,
            running: runtimeIdentity
        )
        let expectedReference = try externalRecord.makeSoftwareExportBuildReference()

        #expect(evidence.exactEvidenceRecordSHA256 == sha256Hex(evidenceData))
        #expect(evidence.schemaVersion == 2)
        #expect(evidence.authority == "signed-field-artifact-evidence-not-field-authorization")
        #expect(evidence.teamIdentifier == "ABCDEFGHIJ")
        #expect(evidence.codeDirectoryHash == String(repeating: "c", count: 40))
        #expect(evidence.ipaByteCount == 123_456)
        #expect(reference == expectedReference)
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)
    }

    @Test
    func schemaOneAndAuthorityLookingFieldsFailClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let digest = sha256Hex(externalData)

        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.unsupportedSchemaVersion(1)
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(
                try makeEvidenceJSON(externalBuildRecordSHA256: digest, overrides: ["schemaVersion": 1])
            )
        }
        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.unexpectedField("physicalGO")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(
                try makeEvidenceJSON(externalBuildRecordSHA256: digest, overrides: ["physicalGO": true])
            )
        }
        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.unexpectedField("authorized")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(
                try makeEvidenceJSON(externalBuildRecordSHA256: digest, overrides: ["authorized": true])
            )
        }
    }

    @Test
    func malformedSigningPlatformAndInstallableFactsFailClosed() throws {
        let digest = sha256Hex(try makeExternalRecordJSON())
        let cases: [(String, Any, PassiveBluetoothCaptureSignedFieldArtifactEvidenceError)] = [
            ("bundleIdentifier", "example.wrong", .invalidBundleIdentifier),
            ("platformName", "iphonesimulator", .invalidPlatformName),
            ("supportedPlatforms", ["iPhoneSimulator"], .invalidSupportedPlatforms),
            ("teamIdentifier", "abc", .invalidTeamIdentifier),
            ("codeDirectoryHash", String(repeating: "G", count: 40), .invalidCodeDirectoryHash),
            ("ipaSHA256", String(repeating: "A", count: 64), .invalidIPASHA256),
            ("ipaByteCount", 0, .invalidIPAByteCount),
        ]
        for (key, value, error) in cases {
            #expect(throws: error) {
                _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(
                    try makeEvidenceJSON(externalBuildRecordSHA256: digest, overrides: [key: value])
                )
            }
        }
    }

    @Test
    func exactExternalRecordBytesRemainPartOfMechanicalBinding() throws {
        let compact = try makeExternalRecordJSON(options: [.sortedKeys])
        let pretty = try makeExternalRecordJSON(options: [.prettyPrinted, .sortedKeys])
        let prettyRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(pretty)
        let evidence = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(compact))
        )

        #expect(compact != pretty)
        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.externalBuildRecordDigestMismatch
        ) {
            _ = try evidence.makeMechanicallyBoundSoftwareExportReference(
                matching: prettyRecord,
                running: try makeRuntimeIdentity()
            )
        }
    }

    @Test
    func externalTupleMismatchFailsBeforeRuntimePromotion() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(
            try makeEvidenceJSON(
                externalBuildRecordSHA256: sha256Hex(externalData),
                overrides: ["executableSHA256": String(repeating: "d", count: 64)]
            )
        )

        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.externalBuildTupleMismatch
        ) {
            _ = try evidence.makeMechanicallyBoundSoftwareExportReference(
                matching: externalRecord,
                running: try makeRuntimeIdentity()
            )
        }
    }

    @Test
    func detachedRunningInfoPlistFailsClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        )
        let detachedRuntime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: runtimeInfoDictionary(),
            executableData: executableData,
            infoPlistData: Data("different-installed-plist".utf8)
        )

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRuntimeBindingError.infoPlistSHA256Mismatch
        ) {
            _ = try evidence.makeMechanicallyBoundSoftwareExportReference(
                matching: externalRecord,
                running: detachedRuntime
            )
        }
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)
    }

    private func makeRuntimeIdentity() throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: runtimeInfoDictionary(),
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    private func runtimeInfoDictionary() -> [String: Any] {
        [
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
            PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: sourceCommitSHA,
        ]
    }

    private func makeExternalRecordJSON(
        options: JSONSerialization.WritingOptions = [.sortedKeys]
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 3,
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": executableSHA256,
            "infoPlistSHA256": infoPlistSHA256,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ], options: options)
    }

    private func makeEvidenceJSON(
        externalBuildRecordSHA256: String,
        overrides: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": 2,
            "authority": "signed-field-artifact-evidence-not-field-authorization",
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "bundleIdentifier": "com.jonathangana131.nembra",
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": "ABCDEFGHIJ",
            "signingAuthorities": ["Apple Development: Nembra"],
            "codeDirectoryHash": String(repeating: "c", count: 40),
            "provisioningProfileUUID": "12345678-1234-4234-8234-123456789abc",
            "provisioningProfileExpirationUTC": "2030-01-01T00:00:00Z",
            "ipaSHA256": String(repeating: "a", count: 64),
            "ipaByteCount": 123_456,
            "executableSHA256": executableSHA256,
            "infoPlistSHA256": infoPlistSHA256,
            "externalBuildRecordSHA256": externalBuildRecordSHA256,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
        for (key, value) in overrides { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
