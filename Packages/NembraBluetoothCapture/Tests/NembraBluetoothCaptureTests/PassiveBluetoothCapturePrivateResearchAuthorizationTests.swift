import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Private research field authorization")
struct PassiveBluetoothCapturePrivateResearchAuthorizationTests {
    private let sourceSHA = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "12345678-1234-4abc-8def-1234567890ab"

    @Test("exact field recipe and canonical running build mint a private research admission")
    func exactFieldBuildMintsAdmission() throws {
        let identity = try makeRuntimeIdentity()
        let authorization = try PassiveBluetoothCapturePrivateResearchAuthorizationReader
            .resolveEmbeddedAuthorization(
                infoDictionary: [
                    PassiveBluetoothCapturePrivateResearchAuthorizationReader.fieldRecipeInfoDictionaryKey:
                        PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
                ],
                runtimeBuildIdentity: identity
            )

        #expect(authorization.recipeID == .es80FingerprintV1)
        #expect(authorization.runtimeBuildIdentity == identity)
        #expect(authorization.buildTimeRecipeMarker == "ES80-FINGERPRINT-v1")

        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.admit(
                privateResearchAuthorization: authorization
            )
        )
        #expect(admission.recipeID == .es80FingerprintV1)
        #expect(admission.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(admission.buildInstanceID == buildInstanceID)
        #expect(admission.sourceCommitSHA == sourceSHA)
        #expect(admission.executableSHA256 == identity.executableSHA256)
        #expect(admission.infoPlistSHA256 == identity.infoPlistSHA256)

        // Private research authority must not silently promote the public/release product gate.
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("Debug-style build without field recipe fails closed")
    func missingFieldRecipeFailsClosed() throws {
        let identity = try makeRuntimeIdentity()

        #expect(throws: PassiveBluetoothCapturePrivateResearchAuthorizationError.missingFieldRecipe) {
            _ = try PassiveBluetoothCapturePrivateResearchAuthorizationReader
                .resolveEmbeddedAuthorization(
                    infoDictionary: [:],
                    runtimeBuildIdentity: identity
                )
        }
    }

    @Test("unknown recipe marker fails closed")
    func unsupportedRecipeFailsClosed() throws {
        let identity = try makeRuntimeIdentity()

        #expect(throws: PassiveBluetoothCapturePrivateResearchAuthorizationError.unsupportedFieldRecipe) {
            _ = try PassiveBluetoothCapturePrivateResearchAuthorizationReader
                .resolveEmbeddedAuthorization(
                    infoDictionary: [
                        PassiveBluetoothCapturePrivateResearchAuthorizationReader.fieldRecipeInfoDictionaryKey:
                            "ES80-FINGERPRINT-v2",
                    ],
                    runtimeBuildIdentity: identity
                )
        }
    }

    @Test("recipe marker cannot authorize a differently named build")
    func nonCanonicalBuildIdentifierFailsClosed() throws {
        let identity = try makeRuntimeIdentity(buildIdentifier: "Debug Capture")

        #expect(throws: PassiveBluetoothCapturePrivateResearchAuthorizationError.buildIdentifierMismatch) {
            _ = try PassiveBluetoothCapturePrivateResearchAuthorizationReader
                .resolveEmbeddedAuthorization(
                    infoDictionary: [
                        PassiveBluetoothCapturePrivateResearchAuthorizationReader.fieldRecipeInfoDictionaryKey:
                            PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
                    ],
                    runtimeBuildIdentity: identity
                )
        }
    }

    private func makeRuntimeIdentity(
        buildIdentifier: String? = nil
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier ?? "Capture Build V14-0123456789ab",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceSHA,
            ],
            executableData: Data("exact executable bytes".utf8),
            infoPlistData: Data("exact Info.plist bytes".utf8)
        )
    }
}
