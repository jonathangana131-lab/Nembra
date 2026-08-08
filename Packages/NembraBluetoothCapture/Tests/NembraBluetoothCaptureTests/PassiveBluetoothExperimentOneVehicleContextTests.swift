import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 Experiment One vehicle context")
struct PassiveBluetoothExperimentOneVehicleContextTests {
    @Test("product-specific run accepts only the canonical ES80 software context")
    @MainActor
    func runRejectsDeferredVehicleContext() throws {
        let es80Run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        #expect(es80Run.vehicleIdentity == VehicleProfile.aovoproES80.identity)

        // Experiment One is the product-specific AOVOPRO ES80 procedure. A declared Nembra vehicle
        // context is only software metadata, not hardware authentication, but this authority must
        // fail closed rather than originate under the explicitly deferred MAXSHOT profile.
        #expect(throws: PassiveBluetoothExperimentOneRunError.invalidVehicleContext) {
            _ = try PassiveBluetoothExperimentOneRun(
                vehicleIdentity: VehicleProfile.maxshotV1SPro.identity
            )
        }
    }

    @Test("fixed product procedure thresholds remain exact")
    func fixedProcedureThresholds() {
        #expect(
            PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
                == 10_000_000_000
        )
        #expect(
            PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
                == 60_000_000_000
        )
    }
}
