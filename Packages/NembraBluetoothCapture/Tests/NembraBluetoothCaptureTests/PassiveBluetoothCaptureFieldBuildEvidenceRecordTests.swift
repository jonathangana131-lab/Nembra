import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture signed field-build evidence record")
struct PassiveBluetoothCaptureFieldBuildEvidenceRecordTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)

    @Test("canonical field record binds exact signed IPA to exact external build record")
    func canonicalRecordBindsExactInstallableAndExternalRecord() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON
            .decodeDeclaration(externalData)
        let data = try makeFieldRecordJSON(externalRecordData: externalData)
        let record = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(data)
        let reference = try record.makeSoftwareExportBuildReference(matching: externalRecord)
        let expectedReference = try PassiveBluetoothExperimentOneSoftwareExportBuildReference(
            buildIdentifier: buildIdentifier,
            buildInstanceID: buildInstanceID,
            sourceCommitSHA: sourceCommitSHA,
            executableSHA256: executableSHA256
        )

        #expect(record.schemaVersion == 1)
        #expect(record.exactEvidenceRecordSHA256 == sha256Hex(data))
        #expect(record.externalBuildRecordSHA256 == sha256Hex(externalData))
        #expect(record.signedInstallableSHA256 == signedInstallableSHA256)
        #expect(record.signedInstallableKind == "ipa")
        #expect(record.buildIdentifier == buildIdentifier)
        #expect(record.buildInstanceID == buildInstanceID)
        #expect(record.sourceCommitSHA == sourceCommitSHA)
        #expect(record.executableSHA256 == executableSHA256)
        #expect(record.infoPlistSHA256 == infoPlistSHA256)
        #expect(record.experimentRecipeID == .es80FingerprintV1)
        #expect(record.procedureVersion == "V14")
        #expect(reference == expectedReference)
    }

    @Test("field evidence exact digest tracks exact supplied bytes")
    func exactEvidenceDigestTracksExactBytes() throws {
        let externalData = try makeExternalRecordJSON()
        let object = baseFieldRecordObject(externalRecordData: externalData)
        let compact = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])

        let compactRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
            .decodeDeclaration(compact)
        let prettyRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
            .decodeDeclaration(pretty)

        #expect(compactRecord.buildInstanceID == prettyRecord.buildInstanceID)
        #expect(compactRecord.signedInstallableSHA256 == prettyRecord.signedInstallableSHA256)
        #expect(compactRecord.exactEvidenceRecordSHA256 == sha256Hex(compact))
        #expect(prettyRecord.exactEvidenceRecordSHA256 == sha256Hex(pretty))
        #expect(compactRecord.exactEvidenceRecordSHA256 != prettyRecord.exactEvidenceRecordSHA256)
    }

    @Test("authority-looking extensions fail closed")
    func authorityLookingExtensionFailsClosed() throws {
        let externalData = try makeExternalRecordJSON()
        let data = try makeFieldRecordJSON(
            externalRecordData: externalData,
            overrides: ["physicalGO": true]
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unexpectedField("physicalGO")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(data)
        }
    }

    @Test("duplicate evidence fields fail closed before decoding")
    func duplicateEvidenceFieldsFailClosedBeforeDecoding() throws {
        let externalData = try makeExternalRecordJSON()
        let canonical = try makeFieldRecordJSON(externalRecordData: externalData)
        let decodedObject = try JSONSerialization.jsonObject(with: canonical)
        let object = try #require(decodedObject as? [String: Any])

        for field in baseFieldRecordObject(externalRecordData: externalData).keys.sorted() {
            let duplicated = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: canonical
            )
            #expect(
                throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.duplicateField(field)
            ) {
                _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
                    .decodeDeclaration(duplicated)
            }
        }
    }

    @Test("escape-equivalent duplicate evidence key fails closed by semantic name")
    func escapedDuplicateEvidenceKeyFailsClosedBySemanticName() throws {
        let externalData = try makeExternalRecordJSON()
        let canonical = String(
            decoding: try makeFieldRecordJSON(externalRecordData: externalData),
            as: UTF8.self
        )
        let duplicated = Data(
            ("{\"signedInstallableSH\\u0041256\":\"\(signedInstallableSHA256)\"," +
                canonical.dropFirst()).utf8
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
                .decodeDeclaration(duplicated)
        }
    }

    @Test("unsupported schema and installable kind fail closed")
    func unsupportedSchemaAndInstallableKindFailClosed() throws {
        let externalData = try makeExternalRecordJSON()

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.unsupportedSchemaVersion(2)
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeFieldRecordJSON(
                    externalRecordData: externalData,
                    overrides: ["schemaVersion": 2]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .unsupportedSignedInstallableKind("app")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeFieldRecordJSON(
                    externalRecordData: externalData,
                    overrides: ["signedInstallableKind": "app"]
                )
            )
        }
    }

    @Test("noncanonical signed artifact and record digests fail closed")
    func noncanonicalDigestsFailClosed() throws {
        let externalData = try makeExternalRecordJSON()

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .invalidSignedInstallableSHA256
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeFieldRecordJSON(
                    externalRecordData: externalData,
                    overrides: ["signedInstallableSHA256": String(repeating: "C", count: 64)]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .invalidExternalBuildRecordSHA256
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
                try makeFieldRecordJSON(
                    externalRecordData: externalData,
                    overrides: ["externalBuildRecordSHA256": String(repeating: "z", count: 64)]
                )
            )
        }
    }

    @Test("mismatched build tuple cannot project external build authority")
    func mismatchedBuildTupleCannotProject() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON
            .decodeDeclaration(externalData)
        let mismatched = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(
            try makeFieldRecordJSON(
                externalRecordData: externalData,
                overrides: ["buildIdentifier": "Capture Build V14-different"]
            )
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.externalBuildRecordMismatch
        ) {
            _ = try mismatched.makeSoftwareExportBuildReference(matching: externalRecord)
        }
    }

    @Test("mismatched exact external-record encoding cannot project authority")
    func mismatchedExternalRecordEncodingCannotProject() throws {
        let externalData = try makeExternalRecordJSON()
        let externalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON
            .decodeDeclaration(externalData)
        let fieldData = try makeFieldRecordJSON(externalRecordData: externalData)
        let fieldRecord = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON
            .decodeDeclaration(fieldData)

        let semanticallyEquivalentExternalData = try JSONSerialization.data(
            withJSONObject: baseExternalRecordObject(),
            options: [.prettyPrinted, .sortedKeys]
        )
        let semanticallyEquivalentExternalRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON
            .decodeDeclaration(semanticallyEquivalentExternalData)
        #expect(semanticallyEquivalentExternalRecord.buildInstanceID == externalRecord.buildInstanceID)
        #expect(semanticallyEquivalentExternalRecord.exactRecordSHA256 != externalRecord.exactRecordSHA256)

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError.externalBuildRecordMismatch
        ) {
            _ = try fieldRecord.makeSoftwareExportBuildReference(
                matching: semanticallyEquivalentExternalRecord
            )
        }
    }

    private func makeExternalRecordJSON() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: baseExternalRecordObject(),
            options: [.sortedKeys]
        )
    }

    private func baseExternalRecordObject() -> [String: Any] {
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

    private func makeFieldRecordJSON(
        externalRecordData: Data,
        overrides: [String: Any] = [:]
    ) throws -> Data {
        var object = baseFieldRecordObject(externalRecordData: externalRecordData)
        for (key, value) in overrides {
            object[key] = value
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func baseFieldRecordObject(externalRecordData: Data) -> [String: Any] {
        [
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
            throw TestFixtureError.expectedJSONObject
        }

        let wrappedValue = try JSONSerialization.data(withJSONObject: [value])
        let wrappedValueJSON = String(decoding: wrappedValue, as: UTF8.self)
        guard wrappedValueJSON.first == "[", wrappedValueJSON.last == "]" else {
            throw TestFixtureError.expectedJSONObject
        }
        let valueJSON = wrappedValueJSON.dropFirst().dropLast()
        return Data(
            ("{\"\(field)\":\(valueJSON)," + canonicalObject.dropFirst()).utf8
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private enum TestFixtureError: Error {
        case expectedJSONObject
    }
}
