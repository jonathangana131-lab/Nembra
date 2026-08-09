import Foundation
import Testing
@testable import NembraCore

@Suite("Speed telemetry evidence and benchmarking")
struct TelemetryBenchmarkTests {
    @Test("fixed 10 Hz BLE samples report frequency without invented jitter")
    func fixedTenHertz() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        for index in 0..<11 {
            let sample = try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: Double(index) / 10,
                receivedAtUptimeNanoseconds: UInt64(index) * 100_000_000,
                receivedAtDate: epoch.addingTimeInterval(Double(index) * 0.1)
            )
            #expect(collector.record(sample) == .accepted)
        }

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 11)
        #expect(summary.intervalCount == 10)
        #expect(abs((summary.effectiveSampleRateHertz ?? 0) - 10) < 0.000_001)
        #expect(abs((summary.meanIntervalMilliseconds ?? 0) - 100) < 0.000_001)
        #expect((summary.intervalJitterStandardDeviationMilliseconds ?? -1) < 0.000_001)
    }

    @Test("jitter is measured from arrival intervals")
    func jitterMeasurement() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let arrivalMilliseconds: [UInt64] = [0, 90, 205, 300, 420]

        for (index, milliseconds) in arrivalMilliseconds.enumerated() {
            let sample = try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: Double(index),
                receivedAtUptimeNanoseconds: milliseconds * 1_000_000,
                receivedAtDate: epoch.addingTimeInterval(Double(milliseconds) / 1_000)
            )
            collector.record(sample)
        }

        let summary = collector.summary
        #expect(summary.minimumIntervalMilliseconds == 90)
        #expect(summary.maximumIntervalMilliseconds == 120)
        #expect((summary.intervalJitterStandardDeviationMilliseconds ?? 0) > 10)
    }

    @Test("out of order packets are rejected without poisoning interval statistics")
    func outOfOrderRejection() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)

        for milliseconds in [100, 200, 150, 300] as [UInt64] {
            let sample = try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: 2,
                receivedAtUptimeNanoseconds: milliseconds * 1_000_000,
                receivedAtDate: epoch
            )
            collector.record(sample)
        }

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 3)
        #expect(summary.rejectedSampleCount == 1)
        #expect(summary.intervalCount == 2)
        #expect(summary.meanIntervalMilliseconds == 100)
    }

    @Test("empirical resolution tracks the smallest observed nonzero speed step")
    func empiricalResolution() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        let speedsKPH = [0.0, 0.0, 1.0, 1.5, 3.5]

        for (index, speedKPH) in speedsKPH.enumerated() {
            let sample = try SpeedTelemetrySample(
                source: .scooterBluetooth,
                provenance: .absoluteMeasurement,
                metersPerSecond: speedKPH / 3.6,
                receivedAtUptimeNanoseconds: UInt64(index + 1) * 100_000_000,
                receivedAtDate: epoch
            )
            collector.record(sample)
        }

        let summary = collector.summary
        #expect(summary.duplicateSpeedValueCount == 1)
        #expect(abs((summary.empiricalMinimumNonzeroSpeedStepKilometersPerHour ?? 0) - 0.5) < 0.000_001)
    }

    @Test("GPS delivery latency uses source timestamp only when available")
    func gpsDeliveryLatency() throws {
        var collector = TelemetryBenchmarkCollector(source: .gps)
        let measurement = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: 4,
            receivedAtUptimeNanoseconds: 1_000_000_000,
            receivedAtDate: measurement.addingTimeInterval(0.125),
            measurementDate: measurement,
            speedAccuracyMetersPerSecond: 0.4
        )
        let second = try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: 4.5,
            receivedAtUptimeNanoseconds: 2_000_000_000,
            receivedAtDate: measurement.addingTimeInterval(1.180),
            measurementDate: measurement.addingTimeInterval(1),
            speedAccuracyMetersPerSecond: 0.5
        )
        collector.record(first)
        collector.record(second)

        let summary = collector.summary
        #expect(summary.deliveryLatencySampleCount == 2)
        #expect(abs((summary.meanDeliveryLatencyMilliseconds ?? 0) - 152.5) < 0.001)
        #expect(abs((summary.minimumDeliveryLatencyMilliseconds ?? 0) - 125) < 0.001)
        #expect(abs((summary.maximumDeliveryLatencyMilliseconds ?? 0) - 180) < 0.001)
    }

    @Test("motion assist cannot masquerade as an authoritative speed measurement")
    func motionAssistProvenanceIsEnforced() throws {
        #expect(throws: SpeedTelemetryValidationError.invalidProvenanceForSource) {
            try SpeedTelemetrySample(
                source: .motionAssist,
                provenance: .absoluteMeasurement,
                metersPerSecond: 2,
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: .now
            )
        }

        let valid = try SpeedTelemetrySample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            metersPerSecond: 2,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )
        #expect(valid.isAuthoritativeMeasurement == false)
    }

    @Test("invalid speed and accuracy never enter telemetry evidence")
    func invalidValuesAreRejected() {
        #expect(throws: SpeedTelemetryValidationError.invalidSpeed) {
            try SpeedTelemetrySample(
                source: .gps,
                provenance: .absoluteMeasurement,
                metersPerSecond: -.infinity,
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: .now
            )
        }
        #expect(throws: SpeedTelemetryValidationError.invalidAccuracy) {
            try SpeedTelemetrySample(
                source: .gps,
                provenance: .absoluteMeasurement,
                metersPerSecond: 1,
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: .now,
                speedAccuracyMetersPerSecond: -1
            )
        }
    }

    @Test("a benchmark collector never mixes sources")
    func sourceMixingIsRejected() throws {
        var collector = TelemetryBenchmarkCollector(source: .scooterBluetooth)
        let gps = try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: 3,
            receivedAtUptimeNanoseconds: 1,
            receivedAtDate: .now
        )
        #expect(collector.record(gps) == .rejected(.sourceMismatch))
        #expect(collector.summary.acceptedSampleCount == 0)
        #expect(collector.summary.rejectedSampleCount == 1)
    }
}

@Suite("Simulated raw speed stream")
struct SimulatedRawSpeedStreamTests {
    @Test("subscribing does not replay cached speed as a fake fresh measurement")
    func noCachedReplay() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .riding),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedTelemetryUpdates()
        var iterator = stream.makeAsyncIterator()

        let next = Task { await iterator.next() }
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(next.isCancelled == false)

        await service.simulateRide(speedKilometersPerHour: 19.2, elapsedSeconds: 0.1)
        let sample = await next.value
        #expect(sample?.source == .simulatorQA)
        #expect(sample?.provenance == .absoluteMeasurement)
        #expect(abs((sample?.kilometersPerHour ?? 0) - 19.2) < 0.000_001)
    }

    @Test("back-to-back simulated QA samples remain strictly monotonic")
    func backToBackSamplesStayMonotonic() async throws {
        let service = SimulatedScooterService(
            initialState: SimulatedScooterService.state(for: .connectedStopped),
            commandLatencyNanoseconds: 0
        )
        let stream = await service.speedTelemetryUpdates()
        var iterator = stream.makeAsyncIterator()
        var collector = TelemetryBenchmarkCollector(source: .simulatorQA)
        var priorUptime: UInt64?

        for speed in [1.0, 2.0, 3.0, 4.0] {
            // This elapsed value advances simulated ride evidence only. It must
            // not manufacture an equally spaced raw packet-arrival cadence.
            await service.simulateRide(speedKilometersPerHour: speed, elapsedSeconds: 0.1)
            let sample = try #require(await iterator.next())
            if let priorUptime {
                #expect(sample.receivedAtUptimeNanoseconds > priorUptime)
            }
            priorUptime = sample.receivedAtUptimeNanoseconds
            #expect(collector.record(sample) == .accepted)
        }

        let summary = collector.summary
        #expect(summary.acceptedSampleCount == 4)
        #expect(summary.intervalCount == 3)
    }
}

@Suite("Simulation telemetry numeric safety")
struct SimulationTelemetryNumericSafetyTests {
    @Test("overflowing ride inputs never poison persisted simulation state")
    func overflowingRideIsRejected() async {
        let initial = SimulatedScooterService.state(for: .connectedStopped)
        let service = SimulatedScooterService(initialState: initial, commandLatencyNanoseconds: 0)
        await service.simulateRide(speedKilometersPerHour: Double.greatestFiniteMagnitude, elapsedSeconds: Double.greatestFiniteMagnitude)
        let snapshot = await service.snapshot()
        #expect(snapshot.speedKilometersPerHour == initial.speedKilometersPerHour)
        #expect(snapshot.tripKilometers == initial.tripKilometers)
        #expect(snapshot.odometerKilometers == initial.odometerKilometers)
        #expect(snapshot.powerWatts == initial.powerWatts)
    }
}
