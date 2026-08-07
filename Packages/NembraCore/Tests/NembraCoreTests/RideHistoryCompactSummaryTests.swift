import Foundation
import Testing
@testable import NembraCore

@Suite("Ride history compact summary")
struct RideHistoryCompactSummaryTests {
    private let sessionID = UUID(uuidString: "87F88523-A98F-4C64-8EEB-C9A3F0DAE441")!

    private func record(
        startOdometerKilometers: Double? = nil,
        endOdometerKilometers: Double? = nil,
        gpsDistanceMeters: Double = 0,
        continuity: RideSessionContinuity = .uninterruptedProcess,
        endedAtDate: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) throws -> RideHistoryRecord {
        RideHistoryRecord(
            evidence: try CompletedRideEvidence(
                sessionID: sessionID,
                beganAtDate: Date(timeIntervalSince1970: 1_799_999_000),
                confirmedAtDate: Date(timeIntervalSince1970: 1_799_999_010),
                endedAtDate: endedAtDate,
                startingOdometerKilometers: startOdometerKilometers,
                endingOdometerKilometers: endOdometerKilometers,
                qualityScreenedGPSDistanceMeters: gpsDistanceMeters,
                continuity: continuity
            )
        )
    }

    @Test("identity, wall-clock presentation date, and continuity stay bound to one record")
    func preservesRecordIdentityAndContinuity() throws {
        let endedAtDate = Date(timeIntervalSince1970: 1_811_111_111)
        let summary = RideHistoryCompactSummary(
            record: try record(
                continuity: .recoveredCheckpoint,
                endedAtDate: endedAtDate
            )
        )

        #expect(summary.sessionID == sessionID)
        #expect(summary.presentationEndedAtDate == endedAtDate)
        #expect(summary.continuity == .recoveredCheckpoint)
        #expect(summary.wasRecoveredFromCheckpoint)
    }

    @Test("an observed zero odometer delta remains legitimate evidence")
    func zeroOdometerDeltaIsPreserved() throws {
        let summary = RideHistoryCompactSummary(
            record: try record(
                startOdometerKilometers: 321.5,
                endOdometerKilometers: 321.5
            )
        )

        #expect(summary.odometerState == .observedDelta)
        #expect(summary.observedOdometerDeltaKilometers == 0)
        #expect(summary.displayableDistanceEvidenceCount == 1)
        #expect(summary.hasDisplayableDistanceEvidence)
    }

    @Test("missing odometer endpoints stay unavailable")
    func missingOdometerEvidenceStaysUnavailable() throws {
        let summary = RideHistoryCompactSummary(record: try record())

        #expect(summary.odometerState == .unavailable)
        #expect(summary.observedOdometerDeltaKilometers == nil)
        #expect(summary.displayableDistanceEvidenceCount == 0)
        #expect(!summary.hasDisplayableDistanceEvidence)
    }

    @Test("stored GPS zero preserves current schema ambiguity instead of claiming measured zero")
    func gpsZeroStaysUnresolved() throws {
        let summary = RideHistoryCompactSummary(
            record: try record(gpsDistanceMeters: 0)
        )

        #expect(summary.gpsState == .unresolvedZeroOrNoObservation)
        #expect(summary.observedPositiveGPSDistanceMeters == nil)
        #expect(summary.displayableDistanceEvidenceCount == 0)
    }

    @Test("positive quality-screened GPS accumulation remains source-specific evidence")
    func positiveGPSDistanceIsPreserved() throws {
        let summary = RideHistoryCompactSummary(
            record: try record(gpsDistanceMeters: 1_234.5)
        )

        #expect(summary.gpsState == .observedPositiveDistance)
        #expect(summary.observedPositiveGPSDistanceMeters == 1_234.5)
        #expect(summary.displayableDistanceEvidenceCount == 1)
        #expect(summary.hasDisplayableDistanceEvidence)
    }

    @Test("ODO and GPS remain two independent values rather than a reconciled total")
    func multipleEvidenceSourcesStaySeparate() throws {
        let summary = RideHistoryCompactSummary(
            record: try record(
                startOdometerKilometers: 100,
                endOdometerKilometers: 102.25,
                gpsDistanceMeters: 2_190
            )
        )

        #expect(summary.odometerState == .observedDelta)
        #expect(summary.observedOdometerDeltaKilometers == 2.25)
        #expect(summary.gpsState == .observedPositiveDistance)
        #expect(summary.observedPositiveGPSDistanceMeters == 2_190)
        #expect(summary.displayableDistanceEvidenceCount == 2)
    }

    @Test("uninterrupted rides do not acquire recovered presentation state")
    func uninterruptedRideIsNotRecovered() throws {
        let summary = RideHistoryCompactSummary(
            record: try record(continuity: .uninterruptedProcess)
        )

        #expect(!summary.wasRecoveredFromCheckpoint)
    }

    @Test("wall-clock rollback stays presentation metadata instead of becoming duration/order truth")
    func wallClockRollbackIsPreservedWithoutInference() throws {
        let rolledBackEnd = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = RideHistoryCompactSummary(
            record: try record(endedAtDate: rolledBackEnd)
        )

        #expect(summary.presentationEndedAtDate == rolledBackEnd)
        #expect(summary.sessionID == sessionID)
    }
}
