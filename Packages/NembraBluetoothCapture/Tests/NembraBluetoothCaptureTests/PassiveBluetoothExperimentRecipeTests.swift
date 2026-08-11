import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Experiment recipe ordering")
struct PassiveBluetoothExperimentRecipeTests {
    @Test("ES80 fingerprint v1 has the canonical procedure identity and order")
    func canonicalRecipe() {
        let recipe = PassiveBluetoothExperimentRecipe.es80FingerprintV1

        #expect(recipe.id.rawValue == "ES80-FINGERPRINT-v1")
        #expect(recipe.requiredSteps == [
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
        ])
    }

    @Test("recipe ID round-trips as the stable artifact spelling")
    func recipeIDCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(PassiveBluetoothExperimentRecipeID.es80FingerprintV1)
        #expect(String(decoding: encoded, as: UTF8.self) == "\"ES80-FINGERPRINT-v1\"")

        let decoded = try JSONDecoder().decode(PassiveBluetoothExperimentRecipeID.self, from: encoded)
        #expect(decoded == .es80FingerprintV1)
    }

    @Test("progress accepts only the exact next required step")
    func exactNextStepOnly() throws {
        var progress = PassiveBluetoothExperimentRecipe.es80FingerprintV1.makeProgress()

        do {
            try progress.complete(.powerOnFirst)
            Issue.record("out-of-order step unexpectedly accepted")
        } catch let error as PassiveBluetoothExperimentRecipeProgressError {
            #expect(error == .unexpectedStep(expected: .preflight, received: .powerOnFirst))
        }

        #expect(progress.completedStepCount == 0)
        #expect(progress.nextRequiredStep == .preflight)

        try progress.complete(.preflight)
        #expect(Array(progress.completedSteps) == [.preflight])
        #expect(progress.nextRequiredStep == .findScooter)
    }

    @Test("complete recipe reaches share only after every prior stage")
    func completesInOrder() throws {
        let recipe = PassiveBluetoothExperimentRecipe.es80FingerprintV1
        var progress = recipe.makeProgress()

        for step in recipe.requiredSteps {
            #expect(progress.nextRequiredStep == step)
            try progress.complete(step)
        }

        #expect(progress.isComplete)
        #expect(progress.nextRequiredStep == nil)
        #expect(Array(progress.completedSteps) == recipe.requiredSteps)

        do {
            try progress.complete(.share)
            Issue.record("completed recipe unexpectedly accepted another step")
        } catch let error as PassiveBluetoothExperimentRecipeProgressError {
            #expect(error == .alreadyComplete)
        }
    }
}
