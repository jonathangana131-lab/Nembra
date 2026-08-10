import XCTest
@testable import NembraCore

final class PropulsionEnergyRailSourceOwnedRuntimeTests: XCTestCase {
    func testSourceOwnedLiveProjectionCarriesExactReceiptIdentity() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()

        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))

        let projection = runtime.projection(
            atUptimeNanoseconds: 1_000_000_000,
            sourceCurrentness: .live
        )

        XCTAssertEqual(projection.currentness, .live)
        XCTAssertEqual(projection.acceptedWatts, 356)
        XCTAssertEqual(projection.acceptedMeasurement?.authority, .simulator)
        XCTAssertEqual(projection.acceptedMeasurement?.receiptSequenceNumber, 7)
        XCTAssertEqual(projection.acceptedMeasurement?.receivedAtUptimeNanoseconds, 1_000_000_000)
        XCTAssertEqual(projection.acceptedMeasurement?.continuityGeneration, 3)
        XCTAssertEqual(projection.accessibilityPresentation.acceptedRevision?.receiptSequenceNumber, 7)
        XCTAssertEqual(projection.accessibilityPresentation.currentness, .live)
    }

    func testEqualWattNewerSourceReceiptAdvancesAcceptedRevision() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()

        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 1_100_000_000,
            continuityGeneration: 3
        ))

        let projection = runtime.projection(
            atUptimeNanoseconds: 1_100_000_000,
            sourceCurrentness: .live
        )

        XCTAssertEqual(projection.acceptedWatts, 356)
        XCTAssertEqual(projection.acceptedMeasurement?.receiptSequenceNumber, 8)
        XCTAssertEqual(projection.accessibilityPresentation.acceptedRevision?.receiptSequenceNumber, 8)
    }

    func testDuplicateOrStaleReceiptCannotReplaceNewestAcceptedSourceTruth() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()

        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 410,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 1_100_000_000,
            continuityGeneration: 3
        ))

        XCTAssertFalse(runtime.observeSourceOwned(
            watts: 50,
            receiptSequenceNumber: 8,
            receivedAtUptimeNanoseconds: 1_200_000_000,
            continuityGeneration: 3
        ))
        XCTAssertFalse(runtime.observeSourceOwned(
            watts: 20,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_300_000_000,
            continuityGeneration: 3
        ))

        let projection = runtime.projection(
            atUptimeNanoseconds: 1_300_000_000,
            sourceCurrentness: .live
        )
        XCTAssertEqual(projection.acceptedWatts, 410)
        XCTAssertEqual(projection.acceptedMeasurement?.receiptSequenceNumber, 8)
    }

    func testNewContinuityGenerationMayResetReceiptSequence() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()

        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 9,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 120,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 2_000_000_000,
            continuityGeneration: 4
        ))

        let projection = runtime.projection(
            atUptimeNanoseconds: 2_000_000_000,
            sourceCurrentness: .live
        )
        XCTAssertEqual(projection.acceptedWatts, 120)
        XCTAssertEqual(projection.acceptedMeasurement?.receiptSequenceNumber, 1)
        XCTAssertEqual(projection.acceptedMeasurement?.continuityGeneration, 4)
    }

    func testRetainedSourceDemotesExactMeasurementAndStripsLiveGeometry() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))

        let projection = runtime.projection(
            atUptimeNanoseconds: 1_100_000_000,
            sourceCurrentness: .retained
        )

        XCTAssertEqual(projection.currentness, .retained)
        XCTAssertEqual(projection.acceptedWatts, 356)
        XCTAssertEqual(projection.acceptedMeasurement?.receiptSequenceNumber, 7)
        XCTAssertEqual(projection.accessibilityPresentation.currentness, .retained)
        XCTAssertEqual(projection.displayWatts, 356)
        XCTAssertNil(projection.railFraction)
        XCTAssertNil(projection.acceptedTargetFraction)
        XCTAssertNil(projection.acceptedPeakMarkerFraction)
        XCTAssertNil(projection.scaleOrigin)
        XCTAssertFalse(projection.allowsLiveMotion)
    }

    func testUnavailableSourceStripsNumericAndAcceptedRevision() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))

        let projection = runtime.projection(
            atUptimeNanoseconds: 1_100_000_000,
            sourceCurrentness: .unavailable
        )

        XCTAssertEqual(projection.currentness, .unavailable)
        XCTAssertNil(projection.acceptedMeasurement)
        XCTAssertNil(projection.acceptedWatts)
        XCTAssertNil(projection.accessibilityPresentation.acceptedRevision)
        XCTAssertNil(projection.displayWatts)
        XCTAssertNil(projection.railFraction)
        XCTAssertFalse(projection.allowsLiveMotion)
    }

    func testSourceLiveCannotUpgradeUnderlyingUnavailableProjection() throws {
        let runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()

        let projection = runtime.projection(
            atUptimeNanoseconds: 1_000_000_000,
            sourceCurrentness: .live
        )

        XCTAssertEqual(projection.currentness, .unavailable)
        XCTAssertNil(projection.acceptedWatts)
        XCTAssertNil(projection.acceptedMeasurement)
    }

    func testRetainedAndUnavailableCurrentnessDisableDisplaySchedule() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))

        let retained = runtime.displaySchedule(
            atUptimeNanoseconds: 1_050_000_000,
            sourceCurrentness: .retained
        )
        let unavailable = runtime.displaySchedule(
            atUptimeNanoseconds: 1_050_000_000,
            sourceCurrentness: .unavailable
        )

        XCTAssertFalse(retained.requiresContinuousFrames)
        XCTAssertNil(retained.nextTransitionUptimeNanoseconds)
        XCTAssertFalse(unavailable.requiresContinuousFrames)
        XCTAssertNil(unavailable.nextTransitionUptimeNanoseconds)
    }

    func testSourceOwnedRuntimeDoesNotScheduleGuessedFreshnessDemotion() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))

        let afterInterpolation = runtime.displaySchedule(
            atUptimeNanoseconds: 1_300_000_000,
            sourceCurrentness: .live
        )

        XCTAssertFalse(afterInterpolation.requiresContinuousFrames)
        // Peak expiry may remain as a display-only deadline, but no source-owned
        // freshness timeout can produce a later live -> retained wake-up.
        if let deadline = afterInterpolation.nextTransitionUptimeNanoseconds {
            XCTAssertLessThanOrEqual(deadline, 3_000_000_001)
        }
    }

    func testLegacyAdapterCannotMintSecondChronologyAfterSourceOwnedReceipt() throws {
        var runtime = try PropulsionEnergyRailSimulatorRuntime.sourceOwned()
        XCTAssertTrue(runtime.observeSourceOwned(
            watts: 356,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            continuityGeneration: 3
        ))

        XCTAssertFalse(runtime.observe(
            connected: true,
            watts: 600,
            modeKey: nil,
            receivedAtUptimeNanoseconds: 2_000_000_000
        ))

        let projection = runtime.projection(
            atUptimeNanoseconds: 2_000_000_000,
            sourceCurrentness: .live
        )
        XCTAssertEqual(projection.acceptedWatts, 356)
        XCTAssertEqual(projection.acceptedMeasurement?.receiptSequenceNumber, 7)
        XCTAssertEqual(projection.acceptedMeasurement?.continuityGeneration, 3)
    }
}
