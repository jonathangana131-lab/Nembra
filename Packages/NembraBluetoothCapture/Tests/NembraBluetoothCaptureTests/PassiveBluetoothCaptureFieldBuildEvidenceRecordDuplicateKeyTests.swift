import Foundation
import Testing
@testable import NembraBluetoothCapture

struct PassiveBluetoothCaptureFieldBuildEvidenceRecordDuplicateKeyTests {
    private let externalHash = String(repeating: "a", count: 64)
    private let installableHash = String(repeating: "b", count: 64)
    private let executableHash = String(repeating: "c", count: 64)
    private let infoPlistHash = String(repeating: "d", count: 64)

    @Test
    func exactDuplicateSignedInstallableDigestFailsBeforeTypedDecode() {
        let data = Data(
            """
            {"schemaVersion":1,"externalBuildRecordSHA256":"\(externalHash)","signedInstallableSHA256":"\(installableHash)","signedInstallableSHA256":"\(String(repeating: "e", count: 64))","signedInstallableKind":"ipa","buildIdentifier":"Capture Build V14-abcdef012345","buildInstanceID":"a1b2c3d4-e5f6-47a8-90bc-def123456789","sourceCommitSHA":"abcdef0123456789abcdef0123456789abcdef01","executableSHA256":"\(executableHash)","infoPlistSHA256":"\(infoPlistHash)","experimentRecipeID":"ES80-FINGERPRINT-v1","procedureVersion":"V14"}
            """.utf8
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(data)
        }
    }

    @Test
    func escapedEquivalentSignedInstallableDigestFailsBeforeTypedDecode() {
        let data = Data(
            """
            {"schemaVersion":1,"externalBuildRecordSHA256":"\(externalHash)","signedInstallableSHA256":"\(installableHash)","signedInstallable\\u0053HA256":"\(String(repeating: "e", count: 64))","signedInstallableKind":"ipa","buildIdentifier":"Capture Build V14-abcdef012345","buildInstanceID":"a1b2c3d4-e5f6-47a8-90bc-def123456789","sourceCommitSHA":"abcdef0123456789abcdef0123456789abcdef01","executableSHA256":"\(executableHash)","infoPlistSHA256":"\(infoPlistHash)","experimentRecipeID":"ES80-FINGERPRINT-v1","procedureVersion":"V14"}
            """.utf8
        )

        #expect(
            throws: PassiveBluetoothCaptureFieldBuildEvidenceRecordError
                .duplicateField("signedInstallableSHA256")
        ) {
            _ = try PassiveBluetoothCaptureFieldBuildEvidenceRecordJSON.decodeDeclaration(data)
        }
    }
}
