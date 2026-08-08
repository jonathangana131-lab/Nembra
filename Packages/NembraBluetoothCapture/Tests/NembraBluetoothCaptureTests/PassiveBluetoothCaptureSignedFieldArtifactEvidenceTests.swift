import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Signed field artifact evidence")
struct PassiveBluetoothCaptureSignedFieldArtifactEvidenceTests {
    private let recordSHA = String(repeating: "a", count: 64)
    private let ipaSHA = String(repeating: "b", count: 64)
    private let executableSHA = String(repeating: "c", count: 64)
    private let infoPlistSHA = String(repeating: "d", count: 64)

    @Test("canonical evidence preserves exact IPA and signing facts")
    func canonicalEvidenceParses() throws {
        let data = try evidenceData()
        let evidence = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON
            .decodeDeclaration(data)

        #expect(evidence.exactEvidenceSHA256 == sha256Hex(data))
        #expect(evidence.ipaSHA256 == ipaSHA)
        #expect(evidence.ipaByteCount == 1_234_567)
        #expect(evidence.externalBuildRecordSHA256 == recordSHA)
        #expect(evidence.teamIdentifier == "TEAM123456")
        #expect(evidence.signingAuthorities == ["Apple Development: Nembra Test"])
        #expect(evidence.experimentRecipeID == .es80FingerprintV1)
        #expect(evidence.procedureVersion == "V14")
    }

    @Test("authority-looking unknown field fails closed")
    func unknownAuthorityFieldFailsClosed() throws {
        var object = baseEvidenceObject()
        object["physicalGO"] = true
        let data = try json(object)

        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unexpectedField("physicalGO")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(data)
        }
    }

    @Test("simulator, malformed digest, and empty signing authority fail closed")
    func invalidPhysicalEvidenceFailsClosed() throws {
        var object = baseEvidenceObject()
        object["supportedPlatforms"] = ["iPhoneSimulator"]
        #expect(throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSupportedPlatforms) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON
                .decodeDeclaration(try json(object))
        }

        object = baseEvidenceObject()
        object["ipaSHA256"] = String(repeating: "B", count: 64)
        #expect(throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidIPASHA256) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON
                .decodeDeclaration(try json(object))
        }

        object = baseEvidenceObject()
        object["signingAuthorities"] = []
        #expect(throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError.invalidSigningAuthorities) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON
                .decodeDeclaration(try json(object))
        }
    }

    @Test("evidence label, recipe, and procedure cannot drift")
    func fixedVocabularyFailsClosed() throws {
        var object = baseEvidenceObject()
        object["authority"] = "field-authorized"
        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedAuthority("field-authorized")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON
                .decodeDeclaration(try json(object))
        }

        object = baseEvidenceObject()
        object["experimentRecipeID"] = "ES80-ELECTRICAL-CORRELATION-v1"
        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedExperimentRecipe("ES80-ELECTRICAL-CORRELATION-v1")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON
                .decodeDeclaration(try json(object))
        }

        object = baseEvidenceObject()
        object["procedureVersion"] = "V15"
        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .unsupportedProcedureVersion("V15")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON
                .decodeDeclaration(try json(object))
        }
    }

    private func evidenceData() throws -> Data {
        try json(baseEvidenceObject())
    }

    private func baseEvidenceObject() -> [String: Any] {
        [
            "schemaVersion": 1,
            "authority": "signed-field-artifact-evidence-not-field-authorization",
            "buildIdentifier": "Capture Build V14-abcdef012345",
            "buildInstanceID": "a1b2c3d4-e5f6-47a8-90bc-def123456789",
            "sourceCommitSHA": "abcdef0123456789abcdef0123456789abcdef01",
            "bundleIdentifier": "com.jonathangana131.nembra",
            "platformName": "iphoneos",
            "supportedPlatforms": ["iPhoneOS"],
            "teamIdentifier": "TEAM123456",
            "signingAuthorities": ["Apple Development: Nembra Test"],
            "ipaSHA256": ipaSHA,
            "ipaByteCount": 1_234_567,
            "executableSHA256": executableSHA,
            "infoPlistSHA256": infoPlistSHA,
            "externalBuildRecordSHA256": recordSHA,
            "experimentRecipeID": "ES80-FINGERPRINT-v1",
            "procedureVersion": "V14",
        ]
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
