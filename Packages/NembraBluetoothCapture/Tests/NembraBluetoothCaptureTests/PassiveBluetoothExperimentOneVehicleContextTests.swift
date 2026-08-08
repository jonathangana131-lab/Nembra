import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 Experiment One vehicle context")
struct PassiveBluetoothExperimentOneVehicleContextTests {
    @Test("product-specific run rejects a deferred non-ES80 vehicle context")
    @MainActor
    func runRejectsDeferredVehicleContext() throws {
        let es80Run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        #expect(es80Run.vehicleIdentity == VehicleProfile.aovoproES80.identity)

        // Experiment One is the product-specific AOVOPRO ES80 procedure. A declared
        // Nembra vehicle context is only software metadata, not hardware authentication,
        // but the product-specific run must still fail closed rather than issuing its
        // hidden run authority under the deferred MAXSHOT profile.
        #expect(throws: (any Error).self) {
            _ = try PassiveBluetoothExperimentOneRun(
                vehicleIdentity: VehicleProfile.maxshotV1SPro.identity
            )
        }
    }
}
