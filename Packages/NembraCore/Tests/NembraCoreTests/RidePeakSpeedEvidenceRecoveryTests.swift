import Foundation
import Testing

@testable import NembraCore

@Suite("Ride-bound peak-speed recovery truth")
struct RidePeakSpeedEvidenceRecoveryTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func recoveredRide() throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch,
            endedAtDate: epoch,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .recoveredCheckpoint
        )
    }

    private func gpsSample(
        metersPerSecond: Double,
        uptime: UInt64,
        accuracy: Double
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: metersPerSecond,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: epoch,
            speedAccuracyMetersPerSecond: accuracy
        )
    }

    @Test("quality rejection alone cannot stand in for the checkpoint recovery gap")
    func qualityLossDoesNotSatisfyRecoveryInterruption() throws {
        let policy = try PeakSpeedPolicy(
            source: .gps,
            maximumSpeedAccuracyMetersPerSecond: 0.5
        )
        var accumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: policy
        )

        _ = accumulator.record(try gpsSample(
            metersPerSecond: 7,
            uptime: 100,
            accuracy: 0.8
        ))
        _ = accumulator.record(try gpsSample(
            metersPerSecond: 6,
            uptime: 200,
            accuracy: 0.4
        ))

        let peak = try #require(accumulator.evidence)
        #expect(!peak.beganAfterKnownObservationGap)
        #expect(peak.peakEvidence.continuity == .partialSelectedSourceEvidence)
        #expect(peak.peakEvidence.qualityRejectedSampleCount == 1)
        #expect(peak.peakEvidence.knownInterruptionCount == 0)

        #expect(throws: CompletedRidePeakSpeedEvidenceError.continuityMismatch) {
            try CompletedRidePeakSpeedEvidence(
                completedRide: recoveredRide(),
                ridePeak: peak
            )
        }
    }

    @Test("later disconnect cannot masquerade as the initial recovery gap")
    func laterInterruptionDoesNotSatisfyInitialGapProvenance() throws {
        let policy = try PeakSpeedPolicy(source: .gps)
        var accumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: policy
        )

        _ = accumulator.record(try gpsSample(
            metersPerSecond: 6,
            uptime: 100,
            accuracy: 0.4
        ))
        accumulator.recordInterruption(.vehicleConnectionLost)

        let peak = try #require(accumulator.evidence)
        #expect(!peak.beganAfterKnownObservationGap)
        #expect(peak.peakEvidence.knownInterruptionCount == 1)
        #expect(peak.peakEvidence.continuity == .partialSelectedSourceEvidence)

        #expect(throws: CompletedRidePeakSpeedEvidenceError.continuityMismatch) {
            try CompletedRidePeakSpeedEvidence(
                completedRide: recoveredRide(),
                ridePeak: peak
            )
        }
    }

    @Test("decoded recovered evidence requires explicit initial-gap provenance")
    func decodedRecoveredQualityOnlyEvidenceRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "recoveredCheckpoint",
              "beganAfterKnownObservationGap": false,
              "source": "gps",
              "metersPerSecond": 6,
              "speedAccuracyMetersPerSecond": 0.4,
              "maximumAllowedSpeedAccuracyMetersPerSecond": 0.5,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": 1,
              "knownInterruptionCount": 0,
              "observationContinuity": "partialSelectedSourceEvidence"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }
}
