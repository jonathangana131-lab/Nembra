import Foundation

/// Stable identifier for a versioned Nembra physical research procedure.
///
/// A recipe identifier records which software procedure was intended. It is not proof that the
/// operator completed the steps, that the physical scooter matched the declared model, or that any
/// Bluetooth observation has protocol meaning.
public enum PassiveBluetoothExperimentRecipeID: String, Codable, CaseIterable, Sendable {
    case es80FingerprintV1 = "ES80-FINGERPRINT-v1"
}

/// Ordered operator/product stages for Nembra's first stationary ES80 fingerprint procedure.
///
/// Power-state names are procedure instructions only. Advancing a recipe never attests that the
/// scooter was physically off/on or that RF non-observation proves absence. Step cases are
/// deliberately not Codable, raw-string backed, or CaseIterable: only the versioned recipe ID is a
/// stable wire identity, and the recipe's explicit `requiredSteps` is the sole sequence authority.
public enum PassiveBluetoothExperimentRecipeStep: Sendable {
    case preflight
    case findScooter
    case powerOffFirst
    case powerOnFirst
    case powerOffSecond
    case powerOnSecond
    case explicitTargetConfirmation
    case passiveDiscovery
    case observationReady
    case capture
    case observationHorizonAndSeal
    case integrityCheck
    case analyze
    case share
}

/// Immutable, versioned ordering contract for a research procedure.
///
/// Construction is sealed so callers cannot reuse an official recipe identifier with a shortened
/// or reordered step list. This is workflow policy only; evidence authority remains with the
/// capture/controller/artifact layers that actually produce and validate immutable observations.
public struct PassiveBluetoothExperimentRecipe: Equatable, Sendable {
    public let id: PassiveBluetoothExperimentRecipeID
    public let requiredSteps: [PassiveBluetoothExperimentRecipeStep]

    public static let es80FingerprintV1 = Self(
        id: .es80FingerprintV1,
        requiredSteps: [
            .preflight,
            .findScooter,
            .powerOffFirst,
            .powerOnFirst,
            .powerOffSecond,
            .powerOnSecond,
            .explicitTargetConfirmation,
            .passiveDiscovery,
            .observationReady,
            .capture,
            .observationHorizonAndSeal,
            .integrityCheck,
            .analyze,
            .share,
        ]
    )

    private init(
        id: PassiveBluetoothExperimentRecipeID,
        requiredSteps: [PassiveBluetoothExperimentRecipeStep]
    ) {
        self.id = id
        self.requiredSteps = requiredSteps
    }

    func makeProgress() -> PassiveBluetoothExperimentRecipeProgress {
        PassiveBluetoothExperimentRecipeProgress(recipe: self)
    }
}

enum PassiveBluetoothExperimentRecipeProgressError: Error, Equatable, Sendable {
    case alreadyComplete
    case unexpectedStep(
        expected: PassiveBluetoothExperimentRecipeStep,
        received: PassiveBluetoothExperimentRecipeStep
    )
}

/// Deterministic workflow progression for a sealed experiment recipe.
///
/// Progress can mechanically prevent the product from skipping required procedure stages, but it is
/// deliberately not evidence. Completed steps must never be promoted into target identity, capture
/// health, physical state, telemetry, or artifact integrity without the accepted evidence producer.
/// Construction and advancement stay package-internal so app/UI clients cannot mint or self-promote
/// readiness, sealing, integrity, or completion state.
public struct PassiveBluetoothExperimentRecipeProgress: Equatable, Sendable {
    public let recipeID: PassiveBluetoothExperimentRecipeID
    public let requiredSteps: [PassiveBluetoothExperimentRecipeStep]
    public private(set) var completedStepCount: Int

    fileprivate init(recipe: PassiveBluetoothExperimentRecipe) {
        recipeID = recipe.id
        requiredSteps = recipe.requiredSteps
        completedStepCount = 0
    }

    public var completedSteps: ArraySlice<PassiveBluetoothExperimentRecipeStep> {
        requiredSteps.prefix(completedStepCount)
    }

    public var nextRequiredStep: PassiveBluetoothExperimentRecipeStep? {
        guard completedStepCount < requiredSteps.count else { return nil }
        return requiredSteps[completedStepCount]
    }

    public var isComplete: Bool {
        completedStepCount == requiredSteps.count
    }

    mutating func complete(
        _ step: PassiveBluetoothExperimentRecipeStep
    ) throws {
        guard let expected = nextRequiredStep else {
            throw PassiveBluetoothExperimentRecipeProgressError.alreadyComplete
        }
        guard step == expected else {
            throw PassiveBluetoothExperimentRecipeProgressError.unexpectedStep(
                expected: expected,
                received: step
            )
        }
        completedStepCount += 1
    }
}
