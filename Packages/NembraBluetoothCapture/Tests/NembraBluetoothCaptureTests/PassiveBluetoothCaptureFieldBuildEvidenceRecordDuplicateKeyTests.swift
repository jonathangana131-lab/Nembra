import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture signed field-build evidence duplicate-key rejection")
struct PassiveBluetoothCaptureFieldBuildEvidenceRecordDuplicateKeyTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)

    @Test
    func everyEvidenceMemberRejectsDuplicateSemanticKey() throws {
        let record = try json(baseEvidenceObject())
        let object = try jsonObject(record)

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
                into: record
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
    func escapeEquivalentSignedInstallableDigestKeyIsStillDuplicate() throws {
        let record = try json(baseEvidenceObject())
        let canonicalRecord = String(decoding: record, as: UTF8.self)
        let duplicated = Data(
            ("{\"signedInstallableSHA\\u0032\\u0035\\u0036\":\"\(String(repeating: "d", count: 64))\"," + canonicalRecord.dropFirst()).utf8
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
                .decodeDeclaration(duplicated)
        }
    }

    @Test
    func conflictingInstallableDigestPrecedenceCannotReachRendezvous() throws {
        var reviewerObject = baseEvidenceObject()
        reviewerObject["signedInstallableSHA256"] = String(repeating: "d", count: 64)
        let reviewerRecord = try json(reviewerObject)
        let ambiguous = try insertingDuplicateField(
            "signedInstallableSHA256",
            value: signedInstallableSHA256,
            into: reviewerRecord
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
                .decodeDeclaration(ambiguous)
        }
    }

    private func baseEvidenceObject() -> [String: Any] {
        let externalRecordData = try! JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 3,
                "buildIdentifier": buildIdentifier,
                "buildInstanceID": buildInstanceID,
                "sourceCommitSHA": sourceCommitSHA,
                "executableSHA256": executableSHA256,
                "infoPlistSHA256": infoPlistSHA256,
                "experimentRecipeID": "ES80-FINGERPRINT-v1",
                "procedureVersion": "V14",
            ],
            options: [.sortedKeys]
        )

        return [
            "schemaVersion": 1,
            "externalBuildRecordSHA256": sha256Hex(externalRecordData),
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
