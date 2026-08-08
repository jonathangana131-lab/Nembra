import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture exact-byte JSON parser ambiguity rejection")
struct PassiveBluetoothCaptureStrictJSONParserTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)

    @Test
    func everySchemaV3ExternalRecordMemberRejectsDuplicates() throws {
        let record = try json(externalRecordObject())
        let object = try jsonObject(record)

        for field in [
            "schemaVersion",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "executableSHA256",
            "infoPlistSHA256",
            "experimentRecipeID",
            "procedureVersion",
        ] {
            let duplicated = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: record
            )
            #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField(field)) {
                _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(duplicated)
            }
        }
    }

    @Test
    func everyCanonicalFieldBuildEvidenceMemberRejectsDuplicates() throws {
        let externalRecord = try json(externalRecordObject())
        let evidence = try json(
            fieldEvidenceObject(externalRecordSHA256: sha256Hex(externalRecord))
        )
        let object = try jsonObject(evidence)

        for field in [
            "schemaVersion",
            "externalBuildRecordSHA256",
            "signedInstallableSHA256",
            "signedInstallableKind",
            "buildIdentifier",
            "buildInstanceID",
            "sourceCommitSHA",
            "executableSHA256",
            "infoPlistSHA256",
            "experimentRecipeID",
            "procedureVersion",
        ] {
            let duplicated = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: evidence
            )
            #expect(
                throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.duplicateField(field)
            ) {
                _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
                    .decodeDeclaration(duplicated)
            }
        }
    }

    @Test
    func escapeEquivalentExternalAndIPAKeysRejectBySemanticName() throws {
        let record = try json(externalRecordObject())
        let canonicalRecord = String(decoding: record, as: UTF8.self)
        let duplicatedRecord = Data(
            ("{\"buildIdentifie\\u0072\":\"Capture Build V14-fedcba543210\"," + canonicalRecord.dropFirst()).utf8
        )
        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField("buildIdentifier")) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(duplicatedRecord)
        }

        let evidence = try json(
            fieldEvidenceObject(externalRecordSHA256: sha256Hex(record))
        )
        let canonicalEvidence = String(decoding: evidence, as: UTF8.self)
        let duplicatedEvidence = Data(
            ("{\"signedInstallableSHA\\u0032\\u0035\\u0036\":\"\(String(repeating: "d", count: 64))\"," + canonicalEvidence.dropFirst()).utf8
        )
        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
                .decodeDeclaration(duplicatedEvidence)
        }
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

    private func fieldEvidenceObject(externalRecordSHA256: String) -> [String: Any] {
        [
            "schemaVersion": 1,
            "externalBuildRecordSHA256": externalRecordSHA256,
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
    }

    private func insertingDuplicateField(
        _ field: String,
        value: Any,
        into objectData: Data
    ) throws -> Data {
        let canonicalObject = String(decoding: objectData, as: UTF8.self)
        guard canonicalObject.first == "{" else {
            throw FixtureError.expectedJSONObject
        }
        let wrappedValue = try JSONSerialization.data(withJSONObject: [value])
        let wrappedJSON = String(decoding: wrappedValue, as: UTF8.self)
        guard wrappedJSON.first == "[", wrappedJSON.last == "]" else {
            throw FixtureError.expectedJSONObject
        }
        let valueJSON = wrappedJSON.dropFirst().dropLast()
        return Data(("{\"\(field)\":\(valueJSON)," + canonicalObject.dropFirst()).utf8)
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw FixtureError.expectedJSONObject
        }
        return dictionary
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private enum FixtureError: Error {
        case expectedJSONObject
    }
}
