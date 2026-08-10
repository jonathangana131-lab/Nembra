import XCTest
@testable import Nembra

final class DashboardEnergyRailContinuityTests: XCTestCase {
    func testRetainedSimulatorSpeedPreservesAcceptedPowerWithoutAdmittingNewPower() throws {
        let sample = try simulatorSpeedSample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 1_000_000_000
        )

        let disposition = dashboardEnergyRailSimulatorSourceDisposition(
            allowsSimulatorQA: true,
            supportsPowerWatts: true,
            isConnected: true,
            speedAvailability: .retained(sample),
            aggregateSpeedKilometersPerHour: 0,
            aggregatePowerWatts: 0
        )

        XCTAssertEqual(disposition.admission, .hardUnavailable)
        XCTAssertTrue(disposition.preservesAcceptedPowerDuringSpeedOnlyRetention)
        XCTAssertTrue(disposition.isPresentationEligible)
    }

    func testRetainedSpeedCannotPreservePowerAfterTransportLoss() throws {
        let sample = try simulatorSpeedSample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 1_000_000_000
        )

        let disposition = dashboardEnergyRailSimulatorSourceDisposition(
            allowsSimulatorQA: true,
            supportsPowerWatts: true,
            isConnected: false,
            speedAvailability: .retained(sample),
            aggregateSpeedKilometersPerHour: 0,
            aggregatePowerWatts: 0
        )

        XCTAssertEqual(disposition.admission, .hardUnavailable)
        XCTAssertFalse(disposition.preservesAcceptedPowerDuringSpeedOnlyRetention)
        XCTAssertFalse(disposition.isPresentationEligible)
    }

    func testRetainedSimulatorSpeedCannotPreservePowerOutsideSimulatorProfile() throws {
        let sample = try simulatorSpeedSample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 1_000_000_000
        )

        let disposition = dashboardEnergyRailSimulatorSourceDisposition(
            allowsSimulatorQA: false,
            supportsPowerWatts: true,
            isConnected: true,
            speedAvailability: .retained(sample),
            aggregateSpeedKilometersPerHour: 0,
            aggregatePowerWatts: 0
        )

        XCTAssertEqual(disposition.admission, .hardUnavailable)
        XCTAssertFalse(disposition.preservesAcceptedPowerDuringSpeedOnlyRetention)
        XCTAssertFalse(disposition.isPresentationEligible)
    }

    func testUnavailableSpeedCannotPreserveAcceptedPower() {
        let disposition = dashboardEnergyRailSimulatorSourceDisposition(
            allowsSimulatorQA: true,
            supportsPowerWatts: true,
            isConnected: true,
            speedAvailability: .unavailable,
            aggregateSpeedKilometersPerHour: 0,
            aggregatePowerWatts: 0
        )

        XCTAssertEqual(disposition.admission, .hardUnavailable)
        XCTAssertFalse(disposition.preservesAcceptedPowerDuringSpeedOnlyRetention)
        XCTAssertFalse(disposition.isPresentationEligible)
    }

    func testCoherentMissingPowerStillFailsClosed() throws {
        let sample = try simulatorSpeedSample(
            kilometersPerHour: 18,
            uptimeNanoseconds: 1_000_000_000
        )

        let disposition = dashboardEnergyRailSimulatorSourceDisposition(
            allowsSimulatorQA: true,
            supportsPowerWatts: true,
            isConnected: true,
            speedAvailability: .live(sample),
            aggregateSpeedKilometersPerHour: 18,
            aggregatePowerWatts: nil
        )

        XCTAssertEqual(disposition.admission, .hardUnavailable)
        XCTAssertFalse(disposition.preservesAcceptedPowerDuringSpeedOnlyRetention)
        XCTAssertFalse(disposition.isPresentationEligible)
    }

    private func simulatorSpeedSample(
        kilometersPerHour: Double,
        uptimeNanoseconds: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .simulatorQA,
            provenance: .absoluteMeasurement,
            metersPerSecond: kilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: Date(timeIntervalSince1970: 0)
        )
    }
}
