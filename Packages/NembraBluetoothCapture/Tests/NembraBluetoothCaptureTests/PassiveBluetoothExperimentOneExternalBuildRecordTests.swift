import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment One external build record")
struct PassiveBluetoothExperimentOneExternalBuildRecordTests {
    private typealias Codec = PassiveBluetoothExperimentOneExternalBuildRecordCodec
    private typealias RecordError = PassiveBluetoothExperimentOneExternalBuildRecordError

    private let buildInstance = "12345678-90ab-cdef-1234-567890abcdef"
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let digest = String(repeating: "a", count: 64)

    @Test("runner schema decodes closed-world while preserving exact bytes")
    func runnerSchemaPreservesExactBytes() throws {
        let data = try makeRecordData()

        let decoded = try Codec.decodeUntrusted(data)

        #expect(decoded.recordJSON == data)
        #expect(decoded.experimentRecipeID == .es80FingerprintV1)
        #expect(decoded.procedureVersion == "V14")
        #expect(decoded.buildReference.buildIdentifier == "Capture Build V14-fixture")
        #expect(decoded.buildReference.buildInstanceID == buildInstance)
        #expect(decoded.buildReference.sourceCommitSHA == commit)
        #expect(decoded.buildReference.executableSHA256 == digest)
    }

    @Test("authority-looking unknown field fails closed")
    func authorityLookingUnknownFieldFailsClosed() throws {
        var root = try makeRecordObject()
        root["fieldExecutionAuthorized"] = true
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: RecordError.unexpectedField("fieldExecutionAuthorized")) {
            _ = try Codec.decodeUntrusted(data)
        }
    }

    @Test("record cannot silently change recipe or procedure authority")
    func recipeAndProcedureAreFixed() throws {
        var root = try makeRecordObject()
        root["experimentRecipeID"] = "ES80-ELECTRICAL-CORRELATION-v1"
        var data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(
            throws: RecordError.unsupportedExperimentRecipe("ES80-ELECTRICAL-CORRELATION-v1")
        ) {
            _ = try Codec.decodeUntrusted(data)
        }

        root = try makeRecordObject()
        root["procedureVersion"] = "V15"
        data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        #expect(throws: RecordError.unsupportedProcedureVersion("V15")) {
            _ = try Codec.decodeUntrusted(data)
        }
    }

    @Test("record reuses canonical exact-build validation")
    func recordReusesCanonicalBuildValidation() throws {
        var root = try makeRecordObject()
        root["buildInstanceID"] = buildInstance.uppercased()
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])

        #expect(throws: RecordError.malformedRecord) {
            _ = try Codec.decodeUntrusted(data)
        }
    }

    private func makeRecordData() throws -> Data {
        try JSONSerialization.data(withJSONObject: makeRecordObject(), options: [.sortedKeys])
    }

    private func makeRecordObject() throws -> [String: Any] {
        [
            "schemaVersion": 2,
            "buildIdentifier": "Capture Build V14-fixture",
            "buildInstanceID": buildInstance,
            "sourceCommitSHA": commit,
            "executableSHA256": digest,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14"
        ]
    }
}
