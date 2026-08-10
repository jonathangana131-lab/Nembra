import Foundation

/// A user-maintained continuity record for an odometer that has reset.
///
/// This is deliberately separate from `VehicleState.odometerKilometers`: a continuity
/// reference is historical/operator evidence, not a Bluetooth measurement and not a
/// protocol-derived correction. Product surfaces may display it only with its provenance.
public struct OdometerContinuityReference: Codable, Equatable, Sendable {
    public enum Provenance: String, Codable, Equatable, Sendable {
        case userRecordedHistory
    }

    public struct Segment: Codable, Equatable, Sendable, Identifiable {
        public enum EvidenceSource: String, Codable, Equatable, Sendable {
            case userRecordedHistory
            case tuyaAppDisplayReference
        }

        public let id: UUID
        public let miles: Double
        public let note: String
        public let evidenceSource: EvidenceSource?

        public init(
            id: UUID = UUID(),
            miles: Double,
            note: String,
            evidenceSource: EvidenceSource = .userRecordedHistory
        ) throws {
            guard miles.isFinite, miles >= 0 else {
                throw ValidationError.invalidMiles
            }
            self.id = id
            self.miles = miles
            self.note = note
            self.evidenceSource = evidenceSource
        }

        public var isBluetoothTelemetry: Bool { false }
        public var authorizesDeviceReportedOdometer: Bool { false }
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidMiles
        case emptySegments
    }

    public let segments: [Segment]
    public let provenance: Provenance
    public let recordedAt: Date

    public init(
        segments: [Segment],
        provenance: Provenance = .userRecordedHistory,
        recordedAt: Date
    ) throws {
        guard !segments.isEmpty else { throw ValidationError.emptySegments }
        guard segments.allSatisfy({ $0.miles.isFinite && $0.miles >= 0 }) else {
            throw ValidationError.invalidMiles
        }
        self.segments = segments
        self.provenance = provenance
        self.recordedAt = recordedAt
    }

    public var totalMiles: Double {
        segments.reduce(0) { $0 + $1.miles }
    }

    public var totalKilometers: Double {
        totalMiles * 1.609_344
    }

    public var authorizesDeviceReportedOdometer: Bool { false }
    public var mayProjectIntoVehicleStateOdometer: Bool { false }
}

public extension OdometerContinuityReference {
    static func physicalCaptureC7D09A22Reference(recordedAt: Date) throws -> Self {
        try Self(
            segments: [
                Segment(
                    miles: 665.3,
                    note: "Pre-reset segment 1",
                    evidenceSource: .userRecordedHistory
                ),
                Segment(
                    miles: 429.5,
                    note: "Pre-reset segment 2",
                    evidenceSource: .userRecordedHistory
                ),
                Segment(
                    miles: 1_070.0,
                    note: "Current Tuya display at reference time",
                    evidenceSource: .tuyaAppDisplayReference
                )
            ],
            recordedAt: recordedAt
        )
    }
}
