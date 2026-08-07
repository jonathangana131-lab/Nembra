import Testing

@testable import NembraCore

@Suite("Observed peak feature-quality policy")
struct RideObservedPeakQualityPolicyTests {
    private func telemetryPolicy(
        source: SpeedTelemetrySource? = .scooterBluetooth,
        maximumRejectedFraction: Double? = 0,
        maximumMeanIntervalMilliseconds: Double? = 150,
        maximumObservedIntervalMilliseconds: Double? = 200,
        maximumJitterMilliseconds: Double? = 50,
        minimumLatencyFraction: Double? = nil,
        maximumMeanLatencyMilliseconds: Double? = nil,
        maximumSpeedStepKPH: Double? = 10
    ) throws -> SpeedTelemetryQualityPolicy {
        try SpeedTelemetryQualityPolicy(
            requiredSource: source,
            minimumAcceptedSampleCount: 3,
            maximumRejectedSampleFraction: maximumRejectedFraction,
            maximumMeanIntervalMilliseconds: maximumMeanIntervalMilliseconds,
            maximumObservedIntervalMilliseconds: maximumObservedIntervalMilliseconds,
            maximumJitterStandardDeviationMilliseconds: maximumJitterMilliseconds,
            minimumDeliveryLatencySampleFraction: minimumLatencyFraction,
            maximumMeanDeliveryLatencyMilliseconds: maximumMeanLatencyMilliseconds,
            maximumEmpiricalSpeedStepKilometersPerHour: maximumSpeedStepKPH
        )
    }

    @Test("every peak-quality evidence dimension must be explicit")
    func omittedEvidenceDimensionsFailConstruction() throws {
        #expect(throws: RideObservedPeakQualityPolicyError.sourceRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(source: nil)
            )
        }
        #expect(throws: RideObservedPeakQualityPolicyError.rejectedFractionRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(maximumRejectedFraction: nil)
            )
        }
        #expect(throws: RideObservedPeakQualityPolicyError.meanIntervalRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(maximumMeanIntervalMilliseconds: nil)
            )
        }
        #expect(throws: RideObservedPeakQualityPolicyError.maximumIntervalRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(maximumObservedIntervalMilliseconds: nil)
            )
        }
        #expect(throws: RideObservedPeakQualityPolicyError.jitterRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(maximumJitterMilliseconds: nil)
            )
        }
        #expect(throws: RideObservedPeakQualityPolicyError.speedResolutionRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(maximumSpeedStepKPH: nil)
            )
        }
    }

    @Test("motion-assist can never become the required peak source")
    func motionAssistPolicyRejected() throws {
        #expect(throws: RideObservedPeakQualityPolicyError.nonAuthoritativeSource) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(source: .motionAssist)
            )
        }
    }

    @Test("GPS requires both delivery-latency coverage and a latency ceiling")
    func gpsLatencyRequirementsAreExplicit() throws {
        #expect(throws: RideObservedPeakQualityPolicyError.gpsLatencyCoverageRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(
                    source: .gps,
                    maximumMeanLatencyMilliseconds: 100
                )
            )
        }

        #expect(throws: RideObservedPeakQualityPolicyError.gpsLatencyRequirementRequired) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(
                    source: .gps,
                    minimumLatencyFraction: 1
                )
            )
        }

        let valid = try RideObservedPeakQualityPolicy(
            telemetry: telemetryPolicy(
                source: .gps,
                minimumLatencyFraction: 1,
                maximumMeanLatencyMilliseconds: 100
            )
        )
        #expect(valid.telemetry.requiredSource == .gps)
    }

    @Test("policy source mismatch cannot qualify an otherwise clean ride session")
    func explicitButWrongSourceStillFailsAssessment() throws {
        let sessionID = try #require(
            UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        )
        var session = RideSpeedEvidenceSessionAccumulator(
            sessionID: sessionID,
            peakPolicy: try PeakSpeedPolicy(source: .scooterBluetooth)
        )

        for index in 1...3 {
            _ = session.record(try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: Double(index),
                receivedAtUptimeNanoseconds: UInt64(index) * 100_000_000,
                receivedAtDate: .distantPast
            ))
        }

        let wrongSourcePolicy = try RideObservedPeakQualityPolicy(
            telemetry: telemetryPolicy(
                source: .gps,
                minimumLatencyFraction: 1,
                maximumMeanLatencyMilliseconds: 100
            )
        )
        let readiness = session.snapshot.observedPeakReadiness(using: wrongSourcePolicy)

        #expect(!readiness.isReady)
        #expect(readiness.telemetryQuality.failures.contains(
            .sourceMismatch(expected: .gps, actual: .scooterBluetooth)
        ))
    }
}
