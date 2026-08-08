import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureExternalBuildRecordTests {
    private typealias RuntimeReader = PassiveBluetoothCaptureRuntimeBuildIdentityReader
    private typealias BindingError = PassiveBluetoothCaptureExternalBuildRuntimeBindingError

    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)

    @Test
    func canonicalV3RecordParsesAndProjectsExactSoftwareExportBuildReference() throws {
        let data = try makeRecordJSON()
        let record = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(data)
        let reference = try record.makeSoftwareExportBuildReference()
        let expectedReference = try PassiveBluetoothExperimentOneSoftwareExportBuildReference(
            buildIdentifier: buildIdentifier,
            buildInstanceID: buildInstanceID,
            sourceCommitSHA: sourceCommitSHA,
            executableSHA256: executableSHA256
        )

        #expect(record.exactRecordSHA256 == sha256Hex(data))
        #expect(record.schemaVersion == 3)
        #expect(record.buildIdentifier == buildIdentifier)
        #expect(record.buildInstanceID == buildInstanceID)
        #expect(record.sourceCommitSHA == sourceCommitSHA)
        #expect(record.executableSHA256 == executableSHA256)
        #expect(record.infoPlistSHA256 == infoPlistSHA256)
        #expect(record.experimentRecipeID == .es80FingerprintV1)
        #expect(record.procedureVersion == "V14")
        #expect(reference == expectedReference)
    }

    @Test
    func exactRecordDigestTracksAttestedBytesRatherThanDecodedSemantics() throws {
        let object = baseRecordObject()
        let compact = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])

        let compactRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(compact)
        let prettyRecord = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(pretty)

        #expect(compactRecord.buildIdentifier == prettyRecord.buildIdentifier)
        #expect(compactRecord.buildInstanceID == prettyRecord.buildInstanceID)
        #expect(compactRecord.executableSHA256 == prettyRecord.executableSHA256)
        #expect(compactRecord.exactRecordSHA256 == sha256Hex(compact))
        #expect(prettyRecord.exactRecordSHA256 == sha256Hex(pretty))
        #expect(compactRecord.exactRecordSHA256 != prettyRecord.exactRecordSHA256)
    }

    @Test
    func buildIdentifierMustDeriveFromTheExactSourceCommit() throws {
        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.buildIdentifierSourceMismatch) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(
                    overrides: ["buildIdentifier": "Capture Build V14-111111111111"]
                )
            )
        }

        let differentSource = "123456789abc6789abcdef0123456789abcdef01"
        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.buildIdentifierSourceMismatch) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["sourceCommitSHA": differentSource])
            )
        }
    }

    @Test
    func parsedRecordMechanicallyBindsEveryMeasuredRuntimeBuildFact() throws {
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try makeRuntimeBoundRecord(runtimeIdentity: runtimeIdentity)

        try record.validateRuntimeBinding(to: runtimeIdentity)
    }

    @Test
    func runtimeBindingFailsClosedForEveryMismatchedBuildFact() throws {
        let runtimeIdentity = try makeRuntimeIdentity()
        let record = try makeRuntimeBoundRecord(runtimeIdentity: runtimeIdentity)

        try expectRuntimeBindingFailure(
            .buildIdentifierMismatch,
            record: record,
            runtimeIdentity: makeRuntimeIdentity(
                buildIdentifier: "Capture Build V14-detached"
            )
        )
        try expectRuntimeBindingFailure(
            .buildInstanceIDMismatch,
            record: record,
            runtimeIdentity: makeRuntimeIdentity(
                buildInstanceID: "11111111-2222-3333-4444-555555555555"
            )
        )
        try expectRuntimeBindingFailure(
            .sourceCommitSHAMismatch,
            record: record,
            runtimeIdentity: makeRuntimeIdentity(
                sourceCommitSHA: String(repeating: "c", count: 40)
            )
        )
        try expectRuntimeBindingFailure(
            .executableSHA256Mismatch,
            record: record,
            runtimeIdentity: makeRuntimeIdentity(
                executableData: Data("different runtime executable".utf8)
            )
        )
        try expectRuntimeBindingFailure(
            .infoPlistSHA256Mismatch,
            record: record,
            runtimeIdentity: makeRuntimeIdentity(
                infoPlistData: Data("different runtime Info.plist".utf8)
            )
        )
    }

    @Test
    func authorityLookingUnknownFieldFailsClosed() throws {
        let data = try makeRecordJSON(overrides: ["physicalGO": true])

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError.unexpectedField("physicalGO")
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(data)
        }
    }

    @Test
    func duplicateBuildRecordFieldsFailClosedBeforeDecoding() throws {
        let canonical = try makeRecordJSON()
        let decodedObject = try JSONSerialization.jsonObject(with: canonical)
        let object = try #require(decodedObject as? [String: Any])

        for field in baseRecordObject().keys.sorted() {
            let duplicated = try insertingDuplicateField(
                field,
                value: try #require(object[field]),
                into: canonical
            )
            #expect(
                throws: PassiveBluetoothCaptureExternalBuildRecordError.duplicateField(field)
            ) {
                _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(duplicated)
            }
        }
    }

    @Test
    func escapedDuplicateBuildRecordKeyFailsClosedBySemanticName() throws {
        let canonical = String(decoding: try makeRecordJSON(), as: UTF8.self)
        let duplicated = Data(
            ("{\"sourceCommitSH\\u0041\":\"\(sourceCommitSHA)\"," + canonical.dropFirst()).utf8
        )

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError
                .duplicateField("sourceCommitSHA")
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(duplicated)
        }
    }

    @Test
    func unsupportedSchemaRecipeAndProcedureFailClosed() throws {
        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError.unsupportedSchemaVersion(4)
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["schemaVersion": 4])
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError
                .unsupportedExperimentRecipe("ES80-ELECTRICAL-CORRELATION-v1")
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(
                    overrides: ["experimentRecipeID": "ES80-ELECTRICAL-CORRELATION-v1"]
                )
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError
                .unsupportedProcedureVersion("V15")
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["procedureVersion": "V15"])
            )
        }
    }

    @Test
    func noncanonicalBuildIdentityAndDigestsFailClosed() throws {
        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.invalidBuildIdentifier) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["buildIdentifier": " Capture Build V14-bad"])
            )
        }

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.invalidBuildInstanceID) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["buildInstanceID": buildInstanceID.uppercased()])
            )
        }

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.invalidSourceCommitSHA) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["sourceCommitSHA": sourceCommitSHA.uppercased()])
            )
        }

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.invalidExecutableSHA256) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["executableSHA256": String(repeating: "A", count: 64)])
            )
        }

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.invalidInfoPlistSHA256) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                try makeRecordJSON(overrides: ["infoPlistSHA256": String(repeating: "z", count: 64)])
            )
        }
    }

    @Test
    func malformedOrMissingRequiredFieldsDoNotMintADeclaration() throws {
        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.malformedJSON) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
                Data("[]".utf8)
            )
        }

        var object = baseRecordObject()
        object.removeValue(forKey: "executableSHA256")
        let missing = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: PassiveBluetoothCaptureExternalBuildRecordError.malformedJSON) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(missing)
        }
    }

    private func makeRuntimeIdentity(
        buildIdentifier: String? = nil,
        buildInstanceID: String? = nil,
        sourceCommitSHA: String? = nil,
        executableData: Data = Data("runtime executable fixture".utf8),
        infoPlistData: Data = Data("runtime Info.plist fixture".utf8)
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try RuntimeReader.resolveEmbeddedMetadata(
            infoDictionary: [
                RuntimeReader.buildIdentifierInfoDictionaryKey: buildIdentifier ?? self.buildIdentifier,
                RuntimeReader.buildInstanceIDInfoDictionaryKey: buildInstanceID ?? self.buildInstanceID,
                RuntimeReader.sourceCommitSHAInfoDictionaryKey: sourceCommitSHA ?? self.sourceCommitSHA,
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
    }

    private func makeRuntimeBoundRecord(
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        overrides: [String: Any] = [:]
    ) throws -> PassiveBluetoothCaptureExternalBuildRecord {
        var runtimeOverrides: [String: Any] = [
            "executableSHA256": runtimeIdentity.executableSHA256,
            "infoPlistSHA256": runtimeIdentity.infoPlistSHA256,
        ]
        for (key, value) in overrides {
            runtimeOverrides[key] = value
        }
        return try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(
            try makeRecordJSON(overrides: runtimeOverrides)
        )
    }

    private func expectRuntimeBindingFailure(
        _ expected: BindingError,
        record: PassiveBluetoothCaptureExternalBuildRecord,
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(throws: expected, sourceLocation: sourceLocation) {
            try record.validateRuntimeBinding(to: runtimeIdentity)
        }
    }

    private func makeRecordJSON(overrides: [String: Any] = [:]) throws -> Data {
        var object = baseRecordObject()
        for (key, value) in overrides {
            object[key] = value
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
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
