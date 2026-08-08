import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture exact evidence JSON ambiguity")
struct PassiveBluetoothCaptureStrictEvidenceJSONTests {
    private let buildIdentifier = "Capture Build V14-abcdef012345"
    private let buildInstanceID = "a1b2c3d4-e5f6-47a8-90bc-def123456789"
    private let sourceCommitSHA = "abcdef0123456789abcdef0123456789abcdef01"
    private let executableSHA256 = String(repeating: "a", count: 64)
    private let infoPlistSHA256 = String(repeating: "b", count: 64)
    private let signedInstallableSHA256 = String(repeating: "c", count: 64)
    private let externalBuildRecordSHA256 = String(repeating: "d", count: 64)

    @Test("external build record rejects exact duplicate semantic key")
    func externalRecordRejectsExactDuplicateKey() throws {
        let canonical = externalRecordJSON()
        let ambiguous = duplicate(
            encodedKey: "infoPlistSHA256",
            encodedValue: "\"\(infoPlistSHA256)\"",
            in: canonical
        )

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError
                .duplicateField("infoPlistSHA256")
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(ambiguous)
        }
    }

    @Test("external build record rejects escape-equivalent duplicate semantic key")
    func externalRecordRejectsEscapeEquivalentDuplicateKey() throws {
        let canonical = externalRecordJSON()
        let ambiguous = duplicate(
            encodedKey: "infoPlistSHA\\u0032\\u0035\\u0036",
            encodedValue: "\"\(infoPlistSHA256)\"",
            in: canonical
        )

        #expect(
            throws: PassiveBluetoothCaptureExternalBuildRecordError
                .duplicateField("infoPlistSHA256")
        ) {
            _ = try PassiveBluetoothCaptureExternalBuildRecordJSON.decodeDeclaration(ambiguous)
        }
    }

    @Test("field evidence rejects exact duplicate semantic key")
    func fieldEvidenceRejectsExactDuplicateKey() throws {
        let canonical = fieldEvidenceJSON()
        let ambiguous = duplicate(
            encodedKey: "signedInstallableSHA256",
            encodedValue: "\"\(signedInstallableSHA256)\"",
            in: canonical
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(ambiguous)
        }
    }

    @Test("field evidence rejects escape-equivalent duplicate semantic key")
    func fieldEvidenceRejectsEscapeEquivalentDuplicateKey() throws {
        let canonical = fieldEvidenceJSON()
        let ambiguous = duplicate(
            encodedKey: "signedInstallableSHA\\u0032\\u0035\\u0036",
            encodedValue: "\"\(signedInstallableSHA256)\"",
            in: canonical
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(ambiguous)
        }
    }

    private func externalRecordJSON() -> Data {
        Data(
            """
            {"schemaVersion":3,"buildIdentifier":"\(buildIdentifier)","buildInstanceID":"\(buildInstanceID)","sourceCommitSHA":"\(sourceCommitSHA)","executableSHA256":"\(executableSHA256)","infoPlistSHA256":"\(infoPlistSHA256)","experimentRecipeID":"ES80-FINGERPRINT-v1","procedureVersion":"V14"}
            """.utf8
        )
    }

    private func fieldEvidenceJSON() -> Data {
        Data(
            """
            {"schemaVersion":1,"externalBuildRecordSHA256":"\(externalBuildRecordSHA256)","signedInstallableSHA256":"\(signedInstallableSHA256)","signedInstallableKind":"ipa","buildIdentifier":"\(buildIdentifier)","buildInstanceID":"\(buildInstanceID)","sourceCommitSHA":"\(sourceCommitSHA)","executableSHA256":"\(executableSHA256)","infoPlistSHA256":"\(infoPlistSHA256)","experimentRecipeID":"ES80-FINGERPRINT-v1","procedureVersion":"V14"}
            """.utf8
        )
    }

    private func duplicate(encodedKey: String, encodedValue: String, in canonical: Data) -> Data {
        let object = String(decoding: canonical, as: UTF8.self)
        precondition(object.first == "{")
        return Data(("{\"\(encodedKey)\":\(encodedValue)," + object.dropFirst()).utf8)
    }
}
