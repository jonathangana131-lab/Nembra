import Foundation
import Testing

@testable import NembraCore

@Suite("Ride-bound observed peak-speed evidence")
struct RidePeakSpeedEvidenceTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let otherSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func completedRide(
        sessionID: UUID? = nil,
        continuity: RideSessionContinuity = .uninterruptedProcess
    ) throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID ?? self.sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch.addingTimeInterval(5),
            endedAtDate: epoch.addingTimeInterval(120),
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: continuity
        )
    }

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        metersPerSecond: Double = 5,
        uptime: UInt64 = 100,
        accuracy: Double? = nil
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch,
            speedAccuracyMetersPerSecond: accuracy
        )
    }

    private func ridePeak(
        sessionID: UUID? = nil,
        source: SpeedTelemetrySource = .scooterBluetooth,
        maximumAccuracy: Double? = nil,
        sampleAccuracy: Double? = nil,
        beginsAfterKnownObservationGap: Bool = false
    ) throws -> RidePeakSpeedEvidence {
        let policy = try PeakSpeedPolicy(
            source: source,
            maximumSpeedAccuracyMetersPerSecond: maximumAccuracy
        )
        var accumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID ?? self.sessionID,
            policy: policy,
            beginsAfterKnownObservationGap: beginsAfterKnownObservationGap
        )
        _ = accumulator.record(try sample(
            source: source,
            accuracy: sampleAccuracy
        ))
        return try #require(accumulator.evidence)
    }

    @Test("ride accumulator binds accepted peak to immutable session and policy")
    func accumulatorBindsSessionAndPolicy() throws {
        let policy = try PeakSpeedPolicy(
            source: .gps,
            maximumSpeedAccuracyMetersPerSecond: 0.8
        )
        var accumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: policy
        )

        #expect(accumulator.evidence == nil)
        _ = accumulator.record(try sample(
            source: .gps,
            metersPerSecond: 6,
            accuracy: 0.5
        ))

        let bound = try #require(accumulator.evidence)
        #expect(bound.sessionID == sessionID)
        #expect(bound.policy == policy)
        #expect(bound.peakEvidence.peak.metersPerSecond == 6)
        #expect(bound.peakEvidence.continuity == .noRecordedSelectedSourceEvidenceLoss)
    }

    @Test("foreign source cannot establish evidence or poison selected source ordering")
    func foreignSourceIsolationSurvivesRideBinding() throws {
        let policy = try PeakSpeedPolicy(source: .scooterBluetooth)
        var accumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: policy
        )

        #expect(
            accumulator.record(try sample(
                source: .gps,
                metersPerSecond: 20,
                uptime: 500,
                accuracy: 0.2
            )) == .rejected(.sourceMismatch)
        )
        #expect(accumulator.evidence == nil)

        #expect(
            accumulator.record(try sample(
                source: .scooterBluetooth,
                metersPerSecond: 4,
                uptime: 100
            )) != .rejected(.nonIncreasingTimestamp)
        )
        #expect(accumulator.evidence?.peakEvidence.peak.metersPerSecond == 4)
    }

    @Test("known gap before first peak remains bound to later ride evidence")
    func initialKnownGapRemainsPartial() throws {
        let bound = try ridePeak(beginsAfterKnownObservationGap: true)

        #expect(bound.peakEvidence.knownInterruptionCount == 1)
        #expect(bound.peakEvidence.continuity == .partialSelectedSourceEvidence)
    }

    @Test("completed projection rejects unrelated ride identity")
    func completedProjectionRejectsSessionMismatch() throws {
        let peak = try ridePeak()
        let otherRide = try completedRide(sessionID: otherSessionID)

        #expect(throws: CompletedRidePeakSpeedEvidenceError.sessionMismatch) {
            try CompletedRidePeakSpeedEvidence(
                completedRide: otherRide,
                ridePeak: peak
            )
        }
    }

    @Test("recovered ride cannot claim gap-free process-local peak observation")
    func recoveredRideRequiresRecordedPeakGap() throws {
        let recoveredRide = try completedRide(continuity: .recoveredCheckpoint)
        let gapFreePeak = try ridePeak()

        #expect(throws: CompletedRidePeakSpeedEvidenceError.continuityMismatch) {
            try CompletedRidePeakSpeedEvidence(
                completedRide: recoveredRide,
                ridePeak: gapFreePeak
            )
        }
    }

    @Test("recovered ride retains a truthful observed peak after explicit known gap")
    func recoveredRideWithRecordedGapAccepted() throws {
        let recoveredRide = try completedRide(continuity: .recoveredCheckpoint)
        let peak = try ridePeak(beginsAfterKnownObservationGap: true)

        let durable = try CompletedRidePeakSpeedEvidence(
            completedRide: recoveredRide,
            ridePeak: peak
        )

        #expect(durable.sessionID == sessionID)
        #expect(durable.rideContinuity == .recoveredCheckpoint)
        #expect(durable.metersPerSecond == 5)
        #expect(durable.kilometersPerHour == 18)
        #expect(durable.knownInterruptionCount == 1)
        #expect(durable.observationContinuity == .partialSelectedSourceEvidence)
    }

    @Test("GPS accuracy policy and peak accuracy survive durable projection")
    func accuracyPolicyProvenancePersists() throws {
        let peak = try ridePeak(
            source: .gps,
            maximumAccuracy: 0.8,
            sampleAccuracy: 0.5
        )
        let durable = try CompletedRidePeakSpeedEvidence(
            completedRide: completedRide(),
            ridePeak: peak
        )

        #expect(durable.source == .gps)
        #expect(durable.speedAccuracyMetersPerSecond == 0.5)
        #expect(durable.maximumAllowedSpeedAccuracyMetersPerSecond == 0.8)
    }

    @Test("durable projection strips process-local receive clocks")
    func durableProjectionOmitsProcessLocalClocks() throws {
        let durable = try CompletedRidePeakSpeedEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak()
        )
        let data = try JSONEncoder().encode(durable)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["receivedAtUptimeNanoseconds"] == nil)
        #expect(object["receivedAtDate"] == nil)
        #expect(object["measurementDate"] == nil)
        #expect(object["metersPerSecond"] != nil)
    }

    @Test("durable round trip preserves ride-bound peak evidence")
    func durableRoundTrip() throws {
        let original = try CompletedRidePeakSpeedEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak(
                source: .gps,
                maximumAccuracy: 0.8,
                sampleAccuracy: 0.5,
                beginsAfterKnownObservationGap: true
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            CompletedRidePeakSpeedEvidence.self,
            from: data
        )

        #expect(decoded == original)
    }

    @Test("decoded motion-assist source cannot masquerade as durable observed peak")
    func decodedMotionAssistRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "motionAssist",
              "metersPerSecond": 5,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": 0,
              "knownInterruptionCount": 0,
              "observationContinuity": "noRecordedSelectedSourceEvidenceLoss"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }

    @Test("decoded accuracy ceiling requires matching measured accuracy")
    func decodedAccuracyPolicyWithoutMeasurementRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "gps",
              "metersPerSecond": 5,
              "maximumAllowedSpeedAccuracyMetersPerSecond": 0.8,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": 0,
              "knownInterruptionCount": 0,
              "observationContinuity": "noRecordedSelectedSourceEvidenceLoss"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }

    @Test("decoded peak accuracy cannot exceed the persisted acceptance ceiling")
    func decodedAccuracyAbovePolicyRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "gps",
              "metersPerSecond": 5,
              "speedAccuracyMetersPerSecond": 1.2,
              "maximumAllowedSpeedAccuracyMetersPerSecond": 0.8,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": 0,
              "knownInterruptionCount": 0,
              "observationContinuity": "noRecordedSelectedSourceEvidenceLoss"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }

    @Test("decoded no-loss continuity cannot hide recorded rejection or interruption")
    func decodedNoLossWithLossCountersRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "scooterBluetooth",
              "metersPerSecond": 5,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": 1,
              "knownInterruptionCount": 0,
              "observationContinuity": "noRecordedSelectedSourceEvidenceLoss"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }

    @Test("decoded partial continuity requires a recorded evidence-loss cause")
    func decodedPartialWithoutLossCountersRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "scooterBluetooth",
              "metersPerSecond": 5,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": 0,
              "knownInterruptionCount": 0,
              "observationContinuity": "partialSelectedSourceEvidence"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }

    @Test("decoded recovered ride cannot claim no recorded selected-source loss")
    func decodedRecoveredNoLossRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "recoveredCheckpoint",
              "source": "scooterBluetooth",
              "metersPerSecond": 5,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": 0,
              "knownInterruptionCount": 0,
              "observationContinuity": "noRecordedSelectedSourceEvidenceLoss"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }

    @Test("joining durable peak against another ride fails closed")
    func validationSessionMismatchRejected() throws {
        let durable = try CompletedRidePeakSpeedEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak()
        )
        let other = try completedRide(sessionID: otherSessionID)

        #expect(throws: CompletedRidePeakSpeedEvidenceError.sessionMismatch) {
            try durable.validate(against: other)
        }
    }

    @Test("joining durable peak against changed ride continuity fails closed")
    func validationContinuityMismatchRejected() throws {
        let durable = try CompletedRidePeakSpeedEvidence(
            completedRide: completedRide(),
            ridePeak: ridePeak()
        )
        let conflicting = try completedRide(continuity: .recoveredCheckpoint)

        #expect(throws: CompletedRidePeakSpeedEvidenceError.continuityMismatch) {
            try durable.validate(against: conflicting)
        }
    }
}
