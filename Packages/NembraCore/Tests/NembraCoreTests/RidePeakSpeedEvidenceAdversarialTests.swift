import Foundation
import Testing

@testable import NembraCore

@Suite("Ride-bound peak-speed adversarial persistence")
struct RidePeakSpeedEvidenceAdversarialTests {
    private let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let epoch = Date(timeIntervalSinceReferenceDate: 10_000)

    private func completedRide() throws -> CompletedRideEvidence {
        try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: epoch,
            confirmedAtDate: epoch,
            endedAtDate: epoch,
            startingOdometerKilometers: nil,
            endingOdometerKilometers: nil,
            qualityScreenedGPSDistanceMeters: 0,
            continuity: .uninterruptedProcess
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

    @Test("finite SI speed that overflows km/h is rejected at durable decode boundary")
    func derivedSpeedOverflowRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "scooterBluetooth",
              "metersPerSecond": 1e308,
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

    @Test("durable peak cannot claim zero accepted selected-source samples")
    func zeroAcceptedSampleCountRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "scooterBluetooth",
              "metersPerSecond": 5,
              "acceptedSampleCount": 0,
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

    @Test("negative evidence-loss counters fail durable validation")
    func negativeLossCounterRejected() {
        let data = Data(
            """
            {
              "sessionID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "rideContinuity": "uninterruptedProcess",
              "source": "scooterBluetooth",
              "metersPerSecond": 5,
              "acceptedSampleCount": 1,
              "qualityRejectedSampleCount": -1,
              "knownInterruptionCount": 0,
              "observationContinuity": "partialSelectedSourceEvidence"
            }
            """.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompletedRidePeakSpeedEvidence.self, from: data)
        }
    }

    @Test("quality-rejected GPS callback remains visible in completed peak provenance")
    func qualityRejectionPersistsAlongsideLaterValidPeak() throws {
        let policy = try PeakSpeedPolicy(
            source: .gps,
            maximumSpeedAccuracyMetersPerSecond: 0.5
        )
        var accumulator = RidePeakSpeedEvidenceAccumulator(
            sessionID: sessionID,
            policy: policy
        )

        #expect(
            accumulator.record(try gpsSample(
                metersPerSecond: 8,
                uptime: 100,
                accuracy: 0.8
            )) == .rejected(.speedAccuracyExceeded(maximum: 0.5, actual: 0.8))
        )
        _ = accumulator.record(try gpsSample(
            metersPerSecond: 6,
            uptime: 200,
            accuracy: 0.4
        ))

        let durable = try CompletedRidePeakSpeedEvidence(
            completedRide: completedRide(),
            ridePeak: #require(accumulator.evidence)
        )

        #expect(durable.metersPerSecond == 6)
        #expect(durable.speedAccuracyMetersPerSecond == 0.4)
        #expect(durable.maximumAllowedSpeedAccuracyMetersPerSecond == 0.5)
        #expect(durable.acceptedSampleCount == 1)
        #expect(durable.qualityRejectedSampleCount == 1)
        #expect(durable.observationContinuity == .partialSelectedSourceEvidence)
    }
}
