import Foundation

/// Build-time authority for the first private, stationary ES80 research capture.
///
/// This is intentionally narrower than Nembra's production P-256 field authorization. It exists
/// only to unblock the first private read-only artifact without pretending the public-release trust
/// model is complete. The capability is minted from the running app's measured build identity plus
/// the exact field-recipe marker already embedded by the canonical signed field-candidate producer.
/// The running executable and raw Info.plist digests, exact source declaration, and per-produced-build
/// instance ID make the resulting capability specific to the app that is actually running.
///
/// It is software authority only. It does not authenticate an AOVOPRO ES80, prove RF completeness,
/// establish GATT/Tuya/telemetry semantics, or authorize any characteristic write.
public struct PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization: Equatable, Sendable {
    public let recipeID: PassiveBluetoothExperimentRecipeID
    public let runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity
    public let buildTimeRecipeMarker: String

    fileprivate init(
        recipeID: PassiveBluetoothExperimentRecipeID,
        runtimeBuildIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        buildTimeRecipeMarker: String
    ) {
        self.recipeID = recipeID
        self.runtimeBuildIdentity = runtimeBuildIdentity
        self.buildTimeRecipeMarker = buildTimeRecipeMarker
    }
}

public enum PassiveBluetoothCapturePrivateResearchAuthorizationError: Error, Equatable, Sendable {
    case unavailableOnSimulator
    case missingFieldRecipe
    case unsupportedFieldRecipe
    case buildIdentifierMismatch
}

/// Fail-closed reader for TODAY's private research authorization.
///
/// Production app code cannot provide arbitrary bytes, a preference value, launch argument, or
/// imported JSON. The public entry point reads only the running main bundle. A Debug launch argument
/// therefore remains routing only: without the build-time `NembraCaptureFieldRecipe` declaration and
/// canonical exact-source field build identity, no private research capability can be minted.
public enum PassiveBluetoothCapturePrivateResearchAuthorizationReader {
    public static let fieldRecipeInfoDictionaryKey = "NembraCaptureFieldRecipe"

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

        let expectedBuildIdentifier = "Capture Build V14-\(runtimeBuildIdentity.sourceCommitSHA.prefix(12))"
        guard runtimeBuildIdentity.buildIdentifier == expectedBuildIdentifier else {
            throw PassiveBluetoothCapturePrivateResearchAuthorizationError.buildIdentifierMismatch
        }

        return PassiveBluetoothCaptureVerifiedPrivateResearchAuthorization(
            recipeID: recipeID,
            runtimeBuildIdentity: runtimeBuildIdentity,
            buildTimeRecipeMarker: rawRecipe
        )
    }
}
