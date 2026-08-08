import Foundation

/// Build-time authority for the first private, stationary ES80 research capture.
///
/// This is intentionally narrower than Nembra's production P-256 field authorization. It exists
/// only to unblock the first private read-only artifact without pretending the public-release trust
/// model is complete. The capability is minted from the running app's measured build identity plus
/// an exact recipe/source/build-instance marker embedded into the signed app at build time.
///
/// It is software authority only. It does not authenticate an AOVOPRO ES80, prove RF completeness,
/// establish GATT/Tuya/telemetry semantics, or authorize any characteristic write.
public struct PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization: Equatable, Sendable {
    public let recipeID: PassiveBluetoothExperimentRecipeID
    public let runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    public let authorizationMarker: String

    fileprivate init(
        recipeID: PassiveBluetoothExperimentRecipeID,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        authorizationMarker: String
    ) {
        self.recipeID = recipeID
        self.runtimeBuildIdentity = runtimeBuildIdentity
        self.authorizationMarker = authorizationMarker
    }
}

public enum PassiveBluetoothCapturePrivateResearchAuthorizationError: Error, Equatable, Sendable {
    case unavailableOnSimulator
    case missingFieldRecipe
    case unsupportedFieldRecipe
    case missingAuthorizationMarker
    case authorizationMarkerMismatch
    case buildIdentifierMismatch
}

/// Fail-closed reader for TODAY's private research authorization.
///
/// Production app code cannot provide arbitrary bytes, a preference value, or imported JSON. The
/// public entry point reads only the running main bundle. The marker includes the exact recipe,
/// source commit, and per-produced-build instance ID and is covered by the raw Info.plist digest in
/// `PassiveBluetoothCaptureRuntimeBuildIdentity`.
public enum PassiveBluetoothCapturePrivateResearchAuthorizationReader {
    public static let fieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"
    public static let authorizationInfoDictionaryKey = "NembraCapturePrivateResearchAuthorization"
    public static let authorizationVersion = "private-research-v1"

    public static func currentApplication() throws -> PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization {
#if targetEnvironment(simulator)
        throw PassiveBluetoothCapturePrivateResearchAuthorizationError.unavailableOnSimulator
#else
        let runtimeIdentity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()
        return try resolveEmbeddedAuthorization(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            runtimeBuildIdentity: runtimeIdentity
        )
#endif
    }

    package static func resolveEmbeddedAuthorization(
        infoDictionary: [String: Any],
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) throws -> PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization {
        guard let rawRecipe = infoDictionary[fieldRecipeInfoDictionaryKey] as? String else {
            throw PassiveBluetoothCapturePrivateResearchAuthorizationError.missingFieldRecipe
        }
        guard let recipeID = PassiveBluetoothExperimentRecipeID(rawValue: rawRecipe),
              recipeID == .es80FingerprintV1 else {
            throw PassiveBluetoothCapturePrivateResearchAuthorizationError.unsupportedFieldRecipe
        }

        guard let marker = infoDictionary[authorizationInfoDictionaryKey] as? String else {
            throw PassiveBluetoothCapturePrivateResearchAuthorizationError.missingAuthorizationMarker
        }
        guard marker == expectedAuthorizationMarker(
            recipeID: recipeID,
            runtimeBuildIdentity: runtimeBuildIdentity
        ) else {
            throw PassiveBluetoothCapturePrivateResearchAuthorizationError.authorizationMarkerMismatch
        }

        let expectedBuildIdentifier = "Capture Build V14-\(runtimeBuildIdentity.sourceCommitSHA.prefix(12))"
        guard runtimeBuildIdentity.buildIdentifier == expectedBuildIdentifier else {
            throw PassiveBluetoothCapturePrivateResearchAuthorizationError.buildIdentifierMismatch
        }

        return PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization(
            recipeID: recipeID,
            runtimeBuildIdentity: runtimeBuildIdentity,
            authorizationMarker: marker
        )
    }

    package static func expectedAuthorizationMarker(
        recipeID: PassiveBluetoothExperimentRecipeID,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    ) -> String {
        [
            authorizationVersion,
            recipeID.rawValue,
            runtimeBuildIdentity.sourceCommitSHA,
            runtimeBuildIdentity.buildInstanceID,
        ].joined(separator: ":")
    }
}
