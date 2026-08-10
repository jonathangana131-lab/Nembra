import XCTest
@testable import Nembra

final class DashboardEnergyRailContinuityTests: XCTestCase {
    @MainActor
    func testExplicitSimulatorStoreOwnsPowerEvidenceCapability() {
        let store = AppBootstrap.makeVehicleStore(
            arguments: ["Nembra"],
            environment: ["NEMBRA_SIMULATION_SCENARIO": "riding"]
        )

        XCTAssertEqual(store.profile, .simulatorQA)
        XCTAssertTrue(store.profile.capabilities.supportsPowerWatts)
        XCTAssertTrue(store.hasSimulatorPowerEvidenceSource)
    }

    @MainActor
    func testOrdinaryLaunchCannotMountSimulatorPowerEvidenceSource() {
        let store = AppBootstrap.makeVehicleStore(
            arguments: ["Nembra"],
            environment: [:]
        )

        XCTAssertNotEqual(store.profile, .simulatorQA)
        XCTAssertFalse(store.hasSimulatorPowerEvidenceSource)
        XCTAssertEqual(store.simulatorPowerEvidenceAvailability, .unavailable)
    }

    @MainActor
    func testSpeedEvidenceGapFlagAloneCannotOpenSimulatorPowerAuthority() {
        let store = AppBootstrap.makeVehicleStore(
            arguments: ["Nembra"],
            environment: [AppBootstrap.simulationSpeedEvidenceGapEnvironmentKey: "1"]
        )

        XCTAssertNotEqual(store.profile, .simulatorQA)
        XCTAssertFalse(store.hasSimulatorPowerEvidenceSource)
        XCTAssertEqual(store.simulatorPowerEvidenceAvailability, .unavailable)
    }
}
