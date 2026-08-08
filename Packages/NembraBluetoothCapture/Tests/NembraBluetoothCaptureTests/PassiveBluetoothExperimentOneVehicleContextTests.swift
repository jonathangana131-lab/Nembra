import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("ES80 Experiment One vehicle context")
struct PassiveBluetoothExperimentOneVehicleContextTests {
    @Test("product-specific run accepts only the canonical ES80 software context")
    @MainActor
    func runRejectsContradictoryVehicleContext() throws {
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

        // Exact equality with the canonical profile is intentional. A caller-built identity cannot
        // bypass the product context simply because it is neither one of Nembra's known profiles nor
        // obviously MAXSHOT-shaped.
        let arbitrary = VehicleIdentity(
            manufacturer: "Example",
            model: "Unknown",
            displayName: "Unknown Scooter",
            protocolFamily: "Unverified"
        )
        #expect(throws: PassiveBluetoothExperimentOneRunError.invalidVehicleContext) {
            _ = try PassiveBluetoothExperimentOneRun(vehicleIdentity: arbitrary)
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
