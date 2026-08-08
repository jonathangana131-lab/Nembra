import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureFieldBuildEvidenceRecordTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)

    @Test
    func canonicalEvidenceBindsExactExternalRecordAndProjectsBuildReference() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidenceData = try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(externalData))
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(evidenceData)
        let reference = try evidence.makeSoftwareExportBuildReference(matching: externalRecord)
        let expectedReference = try externalRecord.makeSoftwareExportBuildReference()

        #expect(evidence.exactEvidenceRecordSHA256 == sha256Hex(evidenceData))
        #expect(evidence.externalBuildRecordSHA256 == sha256Hex(externalData))
        #expect(evidence.signedInstallableSHA256 == signedInstallableSHA256)
        #expect(evidence.signedInstallableKind == "ipa")
        #expect(evidence.schemaVersion == 1)
        #expect(evidence.buildIdentifier == buildIdentifier)
        #expect(evidence.buildInstanceID == buildInstanceID)
        #expect(evidence.sourceCommitSHA == sourceCommitSHA)
        #expect(evidence.executableSHA256 == executableSHA256)
        #expect(evidence.infoPlistSHA256 == infoPlistSHA256)
        #expect(evidence.experimentRecipeID == .es80FingerprintV1)
        #expect(evidence.procedureVersion == "V14")
        #expect(reference == expectedReference)
    }

    @Test
    func externalRecordBindingUsesExactBytesNotOnlyDecodedSemantics() throws {
        let externalObject = externalRecordObject()
        let compact = try JSONSerialization.data(withJSONObject: externalObject, options: [.sortedKeys])
        let pretty = try JSONSerialization.data(withJSONObject: externalObject, options: [.prettyPrinted, .sortedKeys])
        let prettyRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(pretty)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(externalBuildRecordSHA256: sha256Hex(compact))
        )

        #expect(compact != pretty)
        #expect(sha256Hex(compact) != sha256Hex(pretty))
        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.externalBuildRecordMismatch
        ) {
            _ = try evidence.makeSoftwareExportBuildReference(matching: prettyRecord)
        }
    }

    @Test
    func detachedBuildTupleFailsEvenWhenExternalRecordDigestMatches() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(externalData)
        let evidence = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeEvidenceJSON(
                externalBuildRecordSHA256: sha256Hex(externalData),
                overrides: ["executableSHA256": String(repeating: "d", count: 64)]
            )
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.externalBuildRecordMismatch
        ) {
            _ = try evidence.makeSoftwareExportBuildReference(matching: externalRecord)
        }
    }

    @Test
    func authorityLookingFieldsFailClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let externalDigest = sha256Hex(externalData)

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unexpectedField("physicalGO")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["physicalGO": true]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unexpectedField("accepted")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["accepted": true]
                )
            )
        }
    }

    @Test
    func malformedHashesKindRecipeAndProcedureFailClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let externalDigest = sha256Hex(externalData)

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidExternalBuildRecordSHA256) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: String(repeating: "A", count: 64)
                )
            )
        }

        #expect(throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.invalidSignedInstallableSHA256) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["signedInstallableSHA256": String(repeating: "z", count: 64)]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedSignedInstallableKind("app")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["signedInstallableKind": "app"]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedExperimentRecipe("ES80-ELECTRICAL-CORRELATION-v1")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["experimentRecipeID": "ES80-ELECTRICAL-CORRELATION-v1"]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedProcedureVersion("V15")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeEvidenceJSON(
                    externalBuildRecordSHA256: externalDigest,
                    overrides: ["procedureVersion": "V15"]
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
            "externalBuildRecordSHA256": externalBuildRecordSHA256,
            "signedInstallableSHA256": signedInstallableSHA256,
            "signedInstallableKind": "ipa",
            "buildIdentifier": buildIdentifier,
            "buildInstanceID": buildInstanceID,
            "sourceCommitSHA": sourceCommitSHA,
            "executableSHA256": executableSHA256,
            "infoPlistSHA256": infoPlistSHA256,
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
