import Foundation
import Testing
import NembraCore

@Suite("Speed telemetry Codable validation")
struct SpeedTelemetryCodableValidationTests {
    private struct UncheckedPayload: Encodable {
        let source: SpeedTelemetrySource
        let provenance: SpeedTelemetryProvenance
        let metersPerSecond: Double
        let receivedAtUptimeNanoseconds: UInt64
        let receivedAtDate: Date
        let measurementDate: Date?
        let speedAccuracyMetersPerSecond: Double?
    }

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("valid public sample survives Codable round trip")
    func validRoundTrip() throws {
        let sample = try SpeedTelemetrySample(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: 4.25,
            receivedAtUptimeNanoseconds: 9_000_000_000,
            receivedAtDate: epoch,
            measurementDate: epoch.addingTimeInterval(-0.5),
            speedAccuracyMetersPerSecond: 0.7
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(SpeedTelemetrySample.self, from: data)

        #expect(decoded == sample)
    }

    @Test("import cannot relabel motion assist as an absolute measurement")
    func rejectsImpossibleSourceProvenancePair() throws {
        let data = try JSONEncoder().encode(UncheckedPayload(
            source: .motionAssist,
            provenance: .absoluteMeasurement,
            metersPerSecond: 3,
            receivedAtUptimeNanoseconds: 1_000,
            receivedAtDate: epoch,
            measurementDate: nil,
            speedAccuracyMetersPerSecond: nil
        ))

        #expect(throws: SpeedTelemetryValidationError.invalidProvenanceForSource) {
            try JSONDecoder().decode(SpeedTelemetrySample.self, from: data)
        }
    }

    @Test("import rejects negative speed just like live construction")
    func rejectsNegativeSpeed() throws {
        let data = try JSONEncoder().encode(UncheckedPayload(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: -0.1,
            receivedAtUptimeNanoseconds: 2_000,
            receivedAtDate: epoch,
            measurementDate: nil,
            speedAccuracyMetersPerSecond: nil
        ))

        #expect(throws: SpeedTelemetryValidationError.invalidSpeed) {
            try JSONDecoder().decode(SpeedTelemetrySample.self, from: data)
        }
    }

    @Test("import rejects negative accuracy just like live construction")
    func rejectsNegativeAccuracy() throws {
        let data = try JSONEncoder().encode(UncheckedPayload(
            source: .gps,
            provenance: .absoluteMeasurement,
            metersPerSecond: 3,
            receivedAtUptimeNanoseconds: 3_000,
            receivedAtDate: epoch,
            measurementDate: epoch,
            speedAccuracyMetersPerSecond: -0.1
        ))

        #expect(throws: SpeedTelemetryValidationError.invalidAccuracy) {
            try JSONDecoder().decode(SpeedTelemetrySample.self, from: data)
        }
    }
}
