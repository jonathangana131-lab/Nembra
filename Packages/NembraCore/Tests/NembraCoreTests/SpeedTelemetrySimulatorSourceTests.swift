import Foundation
import Testing
@testable import NembraCore

@Suite("Simulator speed source truth")
struct SpeedTelemetrySimulatorSourceTests {
    @Test("simulator source accepts only absolute synthetic observations")
    func simulatorSourceProvenanceBoundary() throws {
        let sample = try SpeedTelemetrySample(
            source: .simulatorQA,
            provenance: .absoluteMeasurement,
            metersPerSecond: 5,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(sample.source == .simulatorQA)
        #expect(sample.isAuthoritativeMeasurement)

        #expect(throws: SpeedTelemetryValidationError.invalidProvenanceForSource) {
            try SpeedTelemetrySample(
                source: .simulatorQA,
                provenance: .shortHorizonEstimate,
                metersPerSecond: 5,
                receivedAtUptimeNanoseconds: 101,
                receivedAtDate: Date(timeIntervalSince1970: 1_700_000_001)
            )
        }
    }

    @Test("simulator source survives Codable without becoming Bluetooth evidence")
    func simulatorSourceCodableRoundTrip() throws {
        let original = try SpeedTelemetrySample(
            source: .simulatorQA,
            provenance: .absoluteMeasurement,
            metersPerSecond: 0,
            receivedAtUptimeNanoseconds: 200,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_002)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeedTelemetrySample.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.source == .simulatorQA)
        #expect(decoded.source != .scooterBluetooth)
    }
}
