import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureExternalBuildRecordDuplicateKeyTests {
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)

    @Test
    func everySchemaV3MemberRejectsDuplicateSemanticKey() throws {
        let record = try json(baseRecordObject())
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
    func escapeEquivalentBuildIdentifierKeyIsStillDuplicate() throws {
        let record = try json(baseRecordObject())
        let canonicalRecord = String(decoding: record, as: UTF8.self)
        let duplicated = Data(
            ("{\"buildIdentifie\\u0072\":\"Capture Build V14-fedcba543210\"," + canonicalRecord.dropFirst()).utf8
        )

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField("buildIdentifier")) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(duplicated)
        }
    }

    @Test
    func conflictingBuildIdentifierPrecedenceCannotReachSourceBinding() throws {
        var reviewerObject = baseRecordObject()
        reviewerObject["buildIdentifier"] = "Capture Build V14-fedcba543210"
        let reviewerRecord = try json(reviewerObject)
        let ambiguous = try insertingDuplicateField(
            "buildIdentifier",
            value: buildIdentifier,
            into: reviewerRecord
        )

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField("buildIdentifier")) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(ambiguous)
        }
    }

    private func baseRecordObject() -> [String: Any] {
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

    private enum FixtureError: Error {
        case expectedJSONObject
    }
}
