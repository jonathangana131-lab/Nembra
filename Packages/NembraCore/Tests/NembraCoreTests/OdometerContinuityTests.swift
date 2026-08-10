import XCTest
@testable import NembraCore

final class OdometerContinuityTests: XCTestCase {
    private let kmPerMile = 1.609344

    func testUserRecordedResetHistoryPreservesLifetimeMileage() throws {
        let first = try OdometerContinuitySegment(
            distanceKilometers: 665.3 * kmPerMile,
            source: .userRecorded,
            note: "owner-recorded counter before reset"
        )
        let second = try OdometerContinuitySegment(
            distanceKilometers: 429.5 * kmPerMile,
            source: .userRecorded,
            note: "owner-recorded counter before second reset"
        )
        let current = try OdometerContinuityReading(
            kilometers: 1070.0 * kmPerMile,
            source: .userRecorded
        )

        let ledger = OdometerContinuityLedger(
            completedSegments: [first, second],
            currentReading: current
        )

        XCTAssertEqual(ledger.snapshot.lifetimeKilometers / kmPerMile, 2164.8, accuracy: 0.000_001)
        XCTAssertEqual(ledger.snapshot.confidence, .referenceOnly)
    }

    func testCounterRegressionRequiresExplicitResetConfirmation() throws {
        let current = try OdometerContinuityReading(kilometers: 100, source: .deviceVerified)
        var ledger = OdometerContinuityLedger(currentReading: current)
        let regressed = try OdometerContinuityReading(kilometers: 3, source: .deviceVerified)

        XCTAssertThrowsError(try ledger.acceptCurrentReading(regressed)) { error in
            XCTAssertEqual(
                error as? OdometerContinuityError,
                .currentReadingRegressed(previousKilometers: 100, observedKilometers: 3)
            )
        }
        XCTAssertEqual(ledger.snapshot.lifetimeKilometers, 100, accuracy: 0.000_001)
    }

    func testConfirmedResetClosesOldCounterAndKeepsLifetimeMonotonic() throws {
        let current = try OdometerContinuityReading(kilometers: 100, source: .deviceVerified)
        var ledger = OdometerContinuityLedger(currentReading: current)
        let newGeneration = try OdometerContinuityReading(kilometers: 3, source: .deviceVerified)

        try ledger.confirmReset(newReading: newGeneration, closedSegmentNote: "confirmed controller reset")

        XCTAssertEqual(ledger.completedSegments.count, 1)
        XCTAssertEqual(ledger.snapshot.lifetimeKilometers, 103, accuracy: 0.000_001)
        XCTAssertEqual(ledger.snapshot.confidence, .verified)
    }

    func testMixedReferenceAndVerifiedHistoryStaysExplicitlyMixed() throws {
        let history = try OdometerContinuitySegment(
            distanceKilometers: 20,
            source: .userRecorded
        )
        let live = try OdometerContinuityReading(
            kilometers: 5,
            source: .deviceVerified
        )
        let ledger = OdometerContinuityLedger(
            completedSegments: [history],
            currentReading: live
        )

        XCTAssertEqual(ledger.snapshot.lifetimeKilometers, 25, accuracy: 0.000_001)
        XCTAssertEqual(ledger.snapshot.confidence, .mixedReferenceAndVerified)
    }

    func testInvalidDistancesAreRejected() {
        XCTAssertThrowsError(
            try OdometerContinuitySegment(distanceKilometers: -Double.infinity, source: .userRecorded)
        )
        XCTAssertThrowsError(
            try OdometerContinuityReading(kilometers: -1, source: .deviceVerified)
        )
    }
}
