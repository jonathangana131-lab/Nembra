import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Signed field artifact evidence duplicate-key rejection")
struct PassiveBluetoothCaptureSignedFieldArtifactEvidenceDuplicateKeyTests {
    @Test("exact duplicate root field fails closed before decoder precedence")
    func exactDuplicateRootFieldFailsClosed() throws {
        let alternateSource = String(repeating: "2", count: 40)
        let data = try evidenceJSON(
            extraRootMember: "\"sourceCommitSHA\":\"\(alternateSource)\""
        )

        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .duplicateField("sourceCommitSHA")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(data)
        }
    }

    @Test("escaped spelling of duplicate semantic root key fails closed")
    func escapedDuplicateSemanticKeyFailsClosed() throws {
        let alternateSource = String(repeating: "2", count: 40)
        let data = try evidenceJSON(
            extraRootMember: "\"sourceCommit\\u0053HA\":\"\(alternateSource)\""
        )

        #expect(
            throws: PassiveBluetoothCaptureSignedFieldArtifactEvidenceError
                .duplicateField("sourceCommitSHA")
        ) {
            _ = try PassiveBluetoothCaptureSignedFieldArtifactEvidenceJSON.decodeDeclaration(data)
        }
    }

    private func evidenceJSON(extraRootMember: String) throws -> Data {
        let source = String(repeating: "1", count: 40)
        let shaA = String(repeating: "a", count: 64)
        let shaB = String(repeating: "b", count: 64)
        let shaC = String(repeating: "c", count: 64)
        let shaD = String(repeating: "d", count: 64)
        let json = """
        {
          "schemaVersion":2,
          "authority":"signed-field-artifact-evidence-not-field-authorization",
          "buildIdentifier":"Capture Build V14-111111111111",
          "buildInstanceID":"12345678-1234-4234-8234-123456789abc",
          "sourceCommitSHA":"\(source)",
          "bundleIdentifier":"com.jonathangana131.nembra",
          "platformName":"iphoneos",
          "supportedPlatforms":["iPhoneOS"],
          "teamIdentifier":"ABCDEFGHIJ",
          "signingAuthorities":["Apple Development: Nembra"],
          "codeDirectoryHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "provisioningProfileUUID":"12345678-1234-4234-8234-123456789abc",
          "provisioningProfileExpirationUTC":"2030-01-01T00:00:00Z",
          "ipaSHA256":"\(shaA)",
          "ipaByteCount":123,
          "executableSHA256":"\(shaB)",
          "infoPlistSHA256":"\(shaC)",
          "externalBuildRecordSHA256":"\(shaD)",
          "experimentRecipeID":"ES80-FINGERPRINT-v1",
          "procedureVersion":"V14",
          \(extraRootMember)
        }
        """
        guard let data = json.data(using: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return data
    }
}
