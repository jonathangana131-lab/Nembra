import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Private research field authorization")
struct PassiveBluetoothCapturePrivateResearchAuthorizationTests {
    private let sourceSHA = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "12345678-1234-4abc-8def-1234567890ab"

    @Test("exact recipe source and build instance mint a private research admission")
    func exactBuildMarkerMintsAdmission() throws {
        let identity = try makeRuntimeIdentity()
        let marker = PassiveBluetoothCapturePrivateResearchAuthorizationReader
            .expectedAuthorizationMarker(
                recipeID: .es80FingerprintV1,
                runtimeBuildIdentity: identity
            )
        let authorization = try PassiveBluetoothCapturePrivateResearchAuthorizationReader
            .resolveEmbeddedAuthorization(
                infoDictionary: [
                    PassiveBluetoothCapturePrivateResearchAuthorizationReader.fieldRecipeInfoDictionaryKey:
                        PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
                    PassiveBluetoothCapturePrivateResearchAuthorizationReader.authorizationInfoDictionaryKey:
                        marker,
                ],
                runtimeBuildIdentity: identity
            )

        #expect(authorization.recipeID == .es80FingerprintV1)
        #expect(authorization.runtimeBuildIdentity == identity)
        #expect(authorization.authorizationMarker == marker)

        let admission = try #require(
            PassiveBluetoothExperimentOneFieldExecutionGate.admit(
                privateResearchAuthorization: authorization
            )
        )
        #expect(admission.recipeID == .es80FingerprintV1)
        #expect(admission.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(admission.buildInstanceID == buildInstanceID)
        #expect(admission.sourceCommitSHA == sourceSHA)

        // Private research authority must not silently promote the public/release product gate.
        #expect(
            PassiveBluetoothExperimentOneFieldExecutionGate.status
                == .noGo(.finalComposedBuildNotAuthorized)
        )
        #expect(!PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure)
    }

    @Test("missing build-time research marker fails closed")
    func missingMarkerFailsClosed() throws {
        let identity = try makeRuntimeIdentity()

        #expect(throws: PassiveBluetoothCapturePrivateResearchAuthorizationError.missingAuthorizationMarker) {
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

    @Test("marker for another build instance fails closed")
    func wrongBuildInstanceFailsClosed() throws {
        let identity = try makeRuntimeIdentity()
        let wrongMarker = [
            PassiveBluetoothCapturePrivateResearchAuthorizationReader.authorizationVersion,
            PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
            sourceSHA,
            "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        ].joined(separator: ":")

        #expect(throws: PassiveBluetoothCapturePrivateResearchAuthorizationError.authorizationMarkerMismatch) {
            _ = try PassiveBluetoothCapturePrivateResearchAuthorizationReader
                .resolveEmbeddedAuthorization(
                    infoDictionary: [
                        PassiveBluetoothCapturePrivateResearchAuthorizationReader.fieldRecipeInfoDictionaryKey:
                            PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
                        PassiveBluetoothCapturePrivateResearchAuthorizationReader.authorizationInfoDictionaryKey:
                            wrongMarker,
                    ],
                    runtimeBuildIdentity: identity
                )
        }
    }

    @Test("recipe-shaped marker cannot authorize a differently named build")
    func nonCanonicalBuildIdentifierFailsClosed() throws {
        let identity = try makeRuntimeIdentity(buildIdentifier: "Debug Capture")
        let marker = PassiveBluetoothCapturePrivateResearchAuthorizationReader
            .expectedAuthorizationMarker(
                recipeID: .es80FingerprintV1,
                runtimeBuildIdentity: identity
            )

        #expect(throws: PassiveBluetoothCapturePrivateResearchAuthorizationError.buildIdentifierMismatch) {
            _ = try PassiveBluetoothCapturePrivateResearchAuthorizationReader
                .resolveEmbeddedAuthorization(
                    infoDictionary: [
                        PassiveBluetoothCapturePrivateResearchAuthorizationReader.fieldRecipeInfoDictionaryKey:
                            PassiveBluetoothExperimentRecipeID.es80FingerprintV1.rawValue,
                        PassiveBluetoothCapturePrivateResearchAuthorizationReader.authorizationInfoDictionaryKey:
                            marker,
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
