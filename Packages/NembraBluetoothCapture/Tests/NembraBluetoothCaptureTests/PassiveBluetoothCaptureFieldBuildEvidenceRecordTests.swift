import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureFieldBuildEvidenceRecordTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)
    private let ipaSHA256 = String(repeating: "c", count: 64)

    @Test
    func canonicalProducerEvidenceBindsExactExternalRecordAndProjectsBuildReference() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidenceData = try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(evidenceData)
        let reference = try evidence.makeSoftwareExportBuildReference(matching: externalRecord)
        let expectedReference = try externalRecord.makeSoftwareExportBuildReference()

        #expect(evidence.exactEvidenceRecordSHA256 == sha256Hex(evidenceData))
        #expect(evidence.schemaVersion == 1)
        #expect(evidence.authority == "signed-field-artifact-evidence-not-field-authorization")
        #expect(evidence.buildIdentifier == buildIdentifier)
        #expect(evidence.buildInstanceID == buildInstanceID)
        #expect(evidence.sourceCommitSHA == sourceCommitSHA)
        #expect(evidence.bundleIdentifier == "com.jonathangana131.nembra")
        #expect(evidence.platformName == "iphoneos")
        #expect(evidence.supportedPlatforms == ["iPhoneOS"])
        #expect(evidence.teamIdentifier == "ABCDE12345")
        #expect(evidence.signingAuthorities == ["Apple Development: Nembra Test"])
        #expect(evidence.ipaSHA256 == ipaSHA256)
        #expect(evidence.ipaByteCount == 123_456)
        #expect(evidence.executableSHA256 == executableSHA256)
        #expect(evidence.infoPlistSHA256 == infoPlistSHA256)
        #expect(evidence.externalBuildRecordSHA256 == sha256Hex(externalData))
        #expect(evidence.experimentRecipeID == .es80FingerprintV1)
        #expect(evidence.procedureVersion == "V14")
        #expect(reference == expectedReference)
    }

    @Test
    func externalRecordBindingUsesExactBytesNotOnlyDecodedSemantics() throws {
        let object = externalRecordObject()
        let compact = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let prettyRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(pretty)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(compact))
        )

        #expect(compact != pretty)
        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.externalBuildRecordMismatch) {
            _ = try evidence.makeSoftwareExportBuildReference(matching: prettyRecord)
        }
    }

    @Test
    func producerAuthorityAndPlatformContractFailClosed() throws {
        let externalDigest = sha256Hex(try makeExternalRecordJSON())

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedAuthority("accepted-for-field-use")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["authority": "accepted-for-field-use"]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedPlatformName("iphonesimulator")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["platformName": "iphonesimulator"]
                )
            )
        }

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSupportedPlatforms) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["supportedPlatforms": ["iPhoneSimulator"]]
                )
            )
        }
    }

    @Test
    func signingAndIPAFieldsFailClosedWhenMalformed() throws {
        let externalDigest = sha256Hex(try makeExternalRecordJSON())

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidTeamIdentifier) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["teamIdentifier": ""]
                )
            )
        }

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSigningAuthorities) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["signingAuthorities": []]
                )
            )
        }

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidIPASHA256) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["ipaSHA256": String(repeating: "A", count: 64)]
                )
            )
        }

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidIPAByteCount) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["ipaByteCount": 0]
                )
            )
        }
    }

    @Test
    func authorityLookingExtensionsFailClosed() throws {
        let externalDigest = sha256Hex(try makeExternalRecordJSON())

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unexpectedField("physicalGO")) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["physicalGO": true]
                )
            )
        }
        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unexpectedField("accepted")) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["accepted": true]
                )
            )
        }
    }

    @Test
    func detachedBuildTupleAndNoncanonicalBuildLabelFailClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(
                externalBuildRecordSHA256: sha256Hex(externalData),
                overrides: ["executableSHA256": String(repeating: "d", count: 64)]
            )
        )

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.externalBuildRecordMismatch) {
            _ = try evidence.makeSoftwareExportBuildReference(matching: externalRecord)
        }

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidBuildIdentifier) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: sha256Hex(externalData),
                    overrides: ["buildIdentifier": "Capture Build V14-deadbeefdead"]
                )
            )
        }
    }

    @Test
    func currentParserCannotMintFieldAuthorization() throws {
        let externalData = try makeExternalRecordJSON()
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        )

        #expect(evidence.experimentRecipeID == PassiveBluetoothExperimentOneFieldExecutionGate.recipeID)
        #expect(PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure == false)
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
    }

    private func makeEvidenceJSON(
        externalBuildRecordSHA256: String,
        overrides: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = [
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
        for (key, value) in overrides {
            object[key] = value
        }
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
