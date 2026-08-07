import Testing

@testable import NembraCore

@Suite("Observed peak quality minimum sample evidence")
struct RideObservedPeakQualityMinimumSampleTests {
    private func telemetryPolicy(minimumAcceptedSampleCount: Int) throws -> SpeedTelemetryQualityPolicy {
        try SpeedTelemetryQualityPolicy(
            requiredSource: .scooterBluetooth,
            minimumAcceptedSampleCount: minimumAcceptedSampleCount,
            maximumRejectedSampleFraction: 0,
            maximumMeanIntervalMilliseconds: 150,
            maximumObservedIntervalMilliseconds: 200,
            maximumJitterStandardDeviationMilliseconds: 50,
            maximumEmpiricalSpeedStepKilometersPerHour: 10
        )
    }

    @Test("one accepted sample cannot establish jitter evidence")
    func oneAcceptedSampleRejected() throws {
        #expect(
            throws: RideObservedPeakQualityPolicyError
                .minimumAcceptedSampleCountInsufficientForJitter(required: 3, actual: 1)
        ) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(minimumAcceptedSampleCount: 1)
            )
        }
    }

    @Test("one timing interval cannot establish jitter evidence")
    func twoAcceptedSamplesRejected() throws {
        #expect(
            throws: RideObservedPeakQualityPolicyError
                .minimumAcceptedSampleCountInsufficientForJitter(required: 3, actual: 2)
        ) {
            try RideObservedPeakQualityPolicy(
                telemetry: telemetryPolicy(minimumAcceptedSampleCount: 2)
            )
        }
    }

    @Test("three accepted samples are the structural minimum for two intervals")
    func threeAcceptedSamplesAccepted() throws {
        let policy = try RideObservedPeakQualityPolicy(
            telemetry: telemetryPolicy(minimumAcceptedSampleCount: 3)
        )
        #expect(policy.telemetry.minimumAcceptedSampleCount == 3)
    }
}
