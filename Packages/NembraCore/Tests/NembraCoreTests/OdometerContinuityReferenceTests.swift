import Foundation
import Testing
@testable import NembraCore

@Suite("Odometer continuity reference")
struct OdometerContinuityReferenceTests {
    @Test("physical capture reference preserves all reset segments")
    func physicalReferencePreservesSegments() throws {
        let recordedAt = Date(timeIntervalSince1970: 1_775_000_000)
        let reference = try OdometerContinuityReference.physicalCaptureC7D09A22Reference(
            recordedAt: recordedAt
        )

        #expect(reference.provenance == .userRecordedHistory)
        #expect(reference.recordedAt == recordedAt)
        #expect(reference.segments.map(\.miles) == [665.3, 429.5, 1_070.0])
        #expect(reference.segments.map(\.evidenceSource) == [
            .userRecordedHistory,
            .userRecordedHistory,
            .tuyaAppDisplayReference
        ])
        #expect(abs(reference.totalMiles - 2_164.8) < 0.000_001)
        #expect(abs(reference.totalKilometers - (2_164.8 * 1.609_344)) < 0.000_001)
    }

    @Test("Tuya display reference remains non-Bluetooth evidence")
    func tuyaDisplayReferenceCannotBecomeBluetoothTruth() throws {
        let reference = try OdometerContinuityReference.physicalCaptureC7D09A22Reference(
            recordedAt: Date(timeIntervalSince1970: 1_775_000_000)
        )
        let currentDisplay = try #require(reference.segments.last)

        #expect(currentDisplay.evidenceSource == .tuyaAppDisplayReference)
        #expect(currentDisplay.miles == 1_070.0)
        #expect(currentDisplay.isBluetoothTelemetry == false)
        #expect(currentDisplay.authorizesDeviceReportedOdometer == false)
    }

    @Test("user continuity cannot become device-reported odometer truth")
    func continuityCannotMintDeviceOdometer() throws {
        let reference = try OdometerContinuityReference.physicalCaptureC7D09A22Reference(
            recordedAt: Date(timeIntervalSince1970: 1_775_000_000)
        )

        #expect(reference.authorizesDeviceReportedOdometer == false)
        #expect(reference.mayProjectIntoVehicleStateOdometer == false)
        #expect(reference.segments.allSatisfy { !$0.isBluetoothTelemetry })
        #expect(reference.segments.allSatisfy { !$0.authorizesDeviceReportedOdometer })
    }

    @Test("older serialized segments decode without source authority")
    func legacySegmentDecodeIsBackwardCompatible() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","miles":12.5,"note":"legacy"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(OdometerContinuityReference.Segment.self, from: json)
        #expect(decoded.evidenceSource == nil)
        #expect(decoded.isBluetoothTelemetry == false)
        #expect(decoded.authorizesDeviceReportedOdometer == false)
    }

    @Test("reference rejects impossible mileage")
    func invalidMileageFailsClosed() throws {
        #expect(throws: OdometerContinuityReference.ValidationError.invalidMiles) {
            _ = try OdometerContinuityReference.Segment(miles: -Double.infinity, note: "invalid")
        }
        #expect(throws: OdometerContinuityReference.ValidationError.invalidMiles) {
            _ = try OdometerContinuityReference.Segment(miles: -1, note: "invalid")
        }
    }

    @Test("reference cannot exist without history")
    func emptyHistoryFailsClosed() throws {
        #expect(throws: OdometerContinuityReference.ValidationError.emptySegments) {
            _ = try OdometerContinuityReference(segments: [], recordedAt: Date())
        }
    }
}
