import Foundation
import Testing

@testable import NembraCore

@Suite("Ride observed peak-power statistics")
struct RidePowerStatisticsTests {
    private let sessionA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let sessionB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let sessionC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func completedRide(
        sessionID: UUID,
        startOffset: TimeInterval = 0,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        let start = epoch.addingTimeInterval(startOffset)
        return try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: start,
            confirmedAtDate: start.addingTimeInterval(2),
            endedAtDate: start.addingTimeInterval(120),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func simulatorScope(
        vehicle: String = "sim-es80",
        mode: String? = "drive"
    ) throws -> ObservedPowerEnvelopeScope {
        try .simulatorQA(vehicleIdentityKey: vehicle, confirmedModeKey: mode)
    }

    private func verifiedScope(
        vehicle: String = "verified-es80",
        mode: String? = "drive"
    ) throws -> ObservedPowerEnvelopeScope {
        try .verifiedVehicleIdentity(
            vehicleIdentityKey: vehicle,
            confirmedModeKey: mode
        )
    }

    private func completedPeak(
        ride: CompletedRideEvidence,
        scope: ObservedPowerEnvelopeScope,
        watts: Double,
        beginsAfterKnownObservationGap: Bool = false
    ) throws -> CompletedRidePeakPowerEvidence {
        var accumulator = try RidePeakPowerEvidenceAccumulator(
            sessionID: ride.sessionID,
            scope: scope,
            beginsAfterKnownObservationGap: beginsAfterKnownObservationGap
        )

        let result: PeakPowerRecordResult
        switch scope.identityAuthority {
        case .simulatorQA:
            result = accumulator.record(.simulatorQA(
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: 1,
                observedAtUptimeNanoseconds: 100,
                learningEligibility: .measurementOnly
            ))
        case .verifiedVehicleIdentity:
            result = accumulator.record(.verifiedVehicleMeasurement(
                scope: scope,
                powerWatts: watts,
                receiptSequenceNumber: 1,
                observedAtUptimeNanoseconds: 100,
                learningEligibility: .measurementOnly
            ))
        }

        guard case .peakUpdated = result else {
            Issue.record("Expected accepted nonnegative observation to establish a peak")
            throw RidePowerStatisticsError.invalidRide
        }

        return try CompletedRidePeakPowerEvidence(
            completedRide: ride,
            ridePeak: #require(accumulator.evidence)
        )
    }

    private func statisticsRide(
        ride: CompletedRideEvidence,
        peak: CompletedRidePeakPowerEvidence?,
        attribution: RideStatisticsCalendarAttribution = .rideBegan
    ) throws -> RidePowerStatisticsRide {
        try RidePowerStatisticsRide(
            completedRide: ride,
            peakPowerEvidence: peak,
            calendarAttribution: attribution
        )
    }

    @Test("empty selected period stays no-rides with no invented numeric or provenance")
    func emptyPeriodHasNoEvidence() throws {
        let summary = try RidePowerStatisticsAggregator.summarize(
            period: .today,
            rides: [],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(summary.rideCount == 0)
        #expect(summary.acceptedPeakPowerRideCount == 0)
        #expect(summary.peakPowerAvailability == .noRides)
        #expect(summary.highestAcceptedObservedPowerWatts == nil)
        #expect(summary.vehicleIdentityKey == nil)
        #expect(summary.identityAuthority == nil)
        #expect(summary.evidenceAuthority == nil)
    }

    @Test("rides without accepted peak evidence remain unavailable rather than zero watts")
    func missingPeakEvidenceIsUnavailable() throws {
        let ride = try completedRide(sessionID: sessionA)
        let summary = try RidePowerStatisticsAggregator.summarize(
            period: .allTime,
            rides: [try statisticsRide(ride: ride, peak: nil)],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(summary.rideCount == 1)
        #expect(summary.unavailablePeakPowerRideCount == 1)
        #expect(summary.peakPowerAvailability == .unavailable)
        #expect(summary.highestAcceptedObservedPowerWatts == nil)
        #expect(summary.highestAcceptedObservedPowerSessionID == nil)
    }

    @Test("accepted zero watts remains real evidence instead of collapsing to unavailable")
    func acceptedZeroWattsRemainsEvidence() throws {
        let ride = try completedRide(sessionID: sessionA)
        let peak = try completedPeak(
            ride: ride,
            scope: simulatorScope(),
            watts: 0
        )
        let summary = try RidePowerStatisticsAggregator.summarize(
            period: .allTime,
            rides: [try statisticsRide(ride: ride, peak: peak)],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(summary.acceptedPeakPowerRideCount == 1)
        #expect(summary.unavailablePeakPowerRideCount == 0)
        #expect(summary.peakPowerAvailability == .complete)
        #expect(summary.highestAcceptedObservedPowerWatts == 0)
        #expect(summary.highestAcceptedObservedPowerSessionID == sessionA)
    }

    @Test("gap-free same-vehicle peaks across modes produce a complete observed maximum")
    func gapFreePeaksAcrossModesRemainComparable() throws {
        let rideA = try completedRide(sessionID: sessionA)
        let rideB = try completedRide(sessionID: sessionB, startOffset: 300)
        let peakA = try completedPeak(
            ride: rideA,
            scope: simulatorScope(mode: "drive"),
            watts: 480
        )
        let peakB = try completedPeak(
            ride: rideB,
            scope: simulatorScope(mode: "sport"),
            watts: 610
        )

        let summary = try RidePowerStatisticsAggregator.summarize(
            period: .allTime,
            rides: [
                try statisticsRide(ride: rideA, peak: peakA),
                try statisticsRide(ride: rideB, peak: peakB)
            ],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(summary.rideCount == 2)
        #expect(summary.acceptedPeakPowerRideCount == 2)
        #expect(summary.gapFreePeakPowerRideCount == 2)
        #expect(summary.partialPeakPowerRideCount == 0)
        #expect(summary.unavailablePeakPowerRideCount == 0)
        #expect(summary.peakPowerAvailability == .complete)
        #expect(summary.highestAcceptedObservedPowerWatts == 610)
        #expect(summary.highestAcceptedObservedPowerSessionID == sessionB)
        #expect(summary.highestAcceptedObservedPowerConfirmedModeKey == "sport")
        #expect(summary.highestAcceptedObservedPowerContinuity == .noRecordedSelectedSourceEvidenceLoss)
        #expect(summary.vehicleIdentityKey == "sim-es80")
        #expect(summary.identityAuthority == .simulatorQA)
        #expect(summary.evidenceAuthority == .simulatorQA)
    }

    @Test("equal observed peaks use durable session identity tie-break independent of input order")
    func equalPeakTieIsDeterministic() throws {
        let rideA = try completedRide(sessionID: sessionA)
        let rideB = try completedRide(sessionID: sessionB, startOffset: 300)
        let scope = try simulatorScope(mode: "sport")
        let preparedA = try statisticsRide(
            ride: rideA,
            peak: completedPeak(ride: rideA, scope: scope, watts: 600)
        )
        let preparedB = try statisticsRide(
            ride: rideB,
            peak: completedPeak(ride: rideB, scope: scope, watts: 600)
        )

        let first = try RidePowerStatisticsAggregator.summarize(
            period: .allTime,
            rides: [preparedB, preparedA],
            referenceDate: epoch,
            calendar: calendar
        )
        let second = try RidePowerStatisticsAggregator.summarize(
            period: .allTime,
            rides: [preparedA, preparedB],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(first == second)
        #expect(first.highestAcceptedObservedPowerSessionID == sessionA)
        #expect(first.highestAcceptedObservedPowerWatts == 600)
    }

    @Test("known selected-source evidence loss preserves observed high but keeps summary partial")
    func gappedPeakRemainsPartial() throws {
        let ride = try completedRide(sessionID: sessionA)
        let peak = try completedPeak(
            ride: ride,
            scope: simulatorScope(mode: "sport"),
            watts: 625,
            beginsAfterKnownObservationGap: true
        )

        let summary = try RidePowerStatisticsAggregator.summarize(
            period: .allTime,
            rides: [try statisticsRide(ride: ride, peak: peak)],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(summary.acceptedPeakPowerRideCount == 1)
        #expect(summary.gapFreePeakPowerRideCount == 0)
        #expect(summary.partialPeakPowerRideCount == 1)
        #expect(summary.peakPowerAvailability == .partial)
        #expect(summary.highestAcceptedObservedPowerWatts == 625)
        #expect(summary.highestAcceptedObservedPowerContinuity == .partialSelectedSourceEvidence)
    }

    @Test("missing ride evidence makes a known observed high only a partial period result")
    func mixedKnownAndMissingEvidenceIsPartial() throws {
        let rideA = try completedRide(sessionID: sessionA)
        let rideB = try completedRide(sessionID: sessionB, startOffset: 300)
        let known = try completedPeak(
            ride: rideA,
            scope: simulatorScope(),
            watts: 540
        )

        let summary = try RidePowerStatisticsAggregator.summarize(
            period: .allTime,
            rides: [
                try statisticsRide(ride: rideA, peak: known),
                try statisticsRide(ride: rideB, peak: nil)
            ],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(summary.acceptedPeakPowerRideCount == 1)
        #expect(summary.unavailablePeakPowerRideCount == 1)
        #expect(summary.peakPowerAvailability == .partial)
        #expect(summary.highestAcceptedObservedPowerWatts == 540)
    }

    @Test("different vehicle identities cannot collapse into one period peak")
    func vehicleIdentityConflictFailsClosed() throws {
        let rideA = try completedRide(sessionID: sessionA)
        let rideB = try completedRide(sessionID: sessionB, startOffset: 300)
        let peakA = try completedPeak(
            ride: rideA,
            scope: simulatorScope(vehicle: "sim-es80-a"),
            watts: 500
        )
        let peakB = try completedPeak(
            ride: rideB,
            scope: simulatorScope(vehicle: "sim-es80-b"),
            watts: 700
        )

        #expect(throws: RidePowerStatisticsError.sourceScopeConflict(sessionB)) {
            try RidePowerStatisticsAggregator.summarize(
                period: .allTime,
                rides: [
                    try statisticsRide(ride: rideA, peak: peakA),
                    try statisticsRide(ride: rideB, peak: peakB)
                ],
                referenceDate: epoch,
                calendar: calendar
            )
        }
    }

    @Test("simulator and verified authorities cannot collapse into one period peak")
    func authorityConflictFailsClosed() throws {
        let rideA = try completedRide(sessionID: sessionA)
        let rideB = try completedRide(sessionID: sessionB, startOffset: 300)
        let simulator = try completedPeak(
            ride: rideA,
            scope: simulatorScope(vehicle: "same-key"),
            watts: 500
        )
        let verified = try completedPeak(
            ride: rideB,
            scope: verifiedScope(vehicle: "same-key"),
            watts: 700
        )

        #expect(throws: RidePowerStatisticsError.sourceScopeConflict(sessionB)) {
            try RidePowerStatisticsAggregator.summarize(
                period: .allTime,
                rides: [
                    try statisticsRide(ride: rideA, peak: simulator),
                    try statisticsRide(ride: rideB, peak: verified)
                ],
                referenceDate: epoch,
                calendar: calendar
            )
        }
    }

    @Test("statistics adapter rejects peak evidence from another ride session")
    func adapterRejectsSessionMismatch() throws {
        let rideA = try completedRide(sessionID: sessionA)
        let rideB = try completedRide(sessionID: sessionB)
        let peakA = try completedPeak(
            ride: rideA,
            scope: simulatorScope(),
            watts: 500
        )

        #expect(throws: RidePowerStatisticsError.sessionMismatch) {
            try statisticsRide(ride: rideB, peak: peakA)
        }
    }

    @Test("statistics adapter rejects peak evidence from another ride continuity")
    func adapterRejectsContinuityMismatch() throws {
        let uninterrupted = try completedRide(
            sessionID: sessionA,
            continuity: .uninterruptedProcess
        )
        let recovered = try completedRide(
            sessionID: sessionA,
            continuity: .recoveredCheckpoint
        )
        let peak = try completedPeak(
            ride: uninterrupted,
            scope: simulatorScope(),
            watts: 500
        )

        #expect(throws: RidePowerStatisticsError.continuityMismatch) {
            try statisticsRide(ride: recovered, peak: peak)
        }
    }

    @Test("unrelated historical duplicate conflict does not poison Today")
    func unrelatedHistoricalConflictIsPeriodIsolated() throws {
        let todayRide = try completedRide(sessionID: sessionA)
        let todayPeak = try completedPeak(
            ride: todayRide,
            scope: simulatorScope(),
            watts: 510
        )

        let oldDateOffset: TimeInterval = -10 * 24 * 60 * 60
        let historicalA = try completedRide(sessionID: sessionC, startOffset: oldDateOffset)
        let historicalB = try completedRide(sessionID: sessionC, startOffset: oldDateOffset + 60)

        let summary = try RidePowerStatisticsAggregator.summarize(
            period: .today,
            rides: [
                try statisticsRide(ride: todayRide, peak: todayPeak),
                try statisticsRide(ride: historicalA, peak: nil),
                try statisticsRide(ride: historicalB, peak: nil)
            ],
            referenceDate: epoch,
            calendar: calendar
        )

        #expect(summary.rideCount == 1)
        #expect(summary.highestAcceptedObservedPowerWatts == 510)
        #expect(summary.peakPowerAvailability == .complete)
    }

    @Test("selected-session duplicate conflict fails closed")
    func selectedSessionConflictFailsClosed() throws {
        let rideA = try completedRide(sessionID: sessionA)
        let conflictingCopy = try completedRide(sessionID: sessionA, startOffset: 60)
        let peak = try completedPeak(
            ride: rideA,
            scope: simulatorScope(),
            watts: 500
        )

        #expect(throws: RidePowerStatisticsError.sessionConflict(sessionA)) {
            try RidePowerStatisticsAggregator.summarize(
                period: .today,
                rides: [
                    try statisticsRide(ride: rideA, peak: peak),
                    try statisticsRide(ride: conflictingCopy, peak: nil)
                ],
                referenceDate: epoch,
                calendar: calendar
            )
        }
    }
}
