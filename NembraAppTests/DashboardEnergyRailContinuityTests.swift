import XCTest
@testable import Nembra
import enum NembraCore.PropulsionEnergyRailCurrentness

final class DashboardEnergyRailContinuityTests: XCTestCase {
    func testLiveSourceMapsToLiveWithoutChangingReceiptIdentity() throws {
        let observation = try SimulatorPowerObservation(
            watts: 356,
            receiptSequenceNumber: 41,
            receivedAtUptimeNanoseconds: 9_000_000_000,
            continuityGeneration: 7
        )
        let availability = SimulatorPowerEvidenceAvailability.live(observation)

        XCTAssertEqual(
            dashboardEnergyRailSourceCurrentness(availability),
            .live
        )
        XCTAssertEqual(
            dashboardEnergyRailSourceObservation(availability),
            observation
        )
    }

    func testRetainedSourceMapsToRetainedAndPreservesExactObservation() throws {
        let observation = try SimulatorPowerObservation(
            watts: 356,
            receiptSequenceNumber: 41,
            receivedAtUptimeNanoseconds: 9_000_000_000,
            continuityGeneration: 7
        )
        let availability = SimulatorPowerEvidenceAvailability.retained(observation)

        XCTAssertEqual(
            dashboardEnergyRailSourceCurrentness(availability),
            .retained
        )
        XCTAssertEqual(
            dashboardEnergyRailSourceObservation(availability),
            observation
        )
    }

    func testUnavailableSourceCannotProvideReceiptMaterial() {
        let availability = SimulatorPowerEvidenceAvailability.unavailable

        XCTAssertEqual(
            dashboardEnergyRailSourceCurrentness(availability),
            .unavailable
        )
        XCTAssertNil(dashboardEnergyRailSourceObservation(availability))
    }

    func testPowerMappingHasNoSpeedOrAggregateVehicleInput() throws {
        let observation = try SimulatorPowerObservation(
            watts: 0,
            receiptSequenceNumber: 2,
            receivedAtUptimeNanoseconds: 2_000_000_000,
            continuityGeneration: 1
        )

        // The source-owned bridge is intentionally a function only of the power
        // source availability. There is no speed, connection, aggregate watts, or
        // view-time argument capable of promoting/demoting this receipt.
        let availability = SimulatorPowerEvidenceAvailability.live(observation)
        XCTAssertEqual(dashboardEnergyRailSourceCurrentness(availability), .live)
        XCTAssertEqual(dashboardEnergyRailSourceObservation(availability), observation)
    }
}
