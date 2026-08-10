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
        public let id: UUID
        public let miles: Double
        public let note: String

        public init(id: UUID = UUID(), miles: Double, note: String) throws {
            guard miles.isFinite, miles >= 0 else {
                throw ValidationError.invalidMiles
            }
            self.id = id
            self.miles = miles
            self.note = note
        }
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
}

public extension OdometerContinuityReference {
    /// Current physical field reference supplied by the scooter owner after two
    /// odometer resets. This constant is reference history only; it must never be
    /// projected into `VehicleState.odometerKilometers` or labeled device-reported.
    static func physicalCaptureC7D09A22Reference(recordedAt: Date) throws -> Self {
        try Self(
            segments: [
                Segment(miles: 665.3, note: "Pre-reset segment 1"),
                Segment(miles: 429.5, note: "Pre-reset segment 2"),
                Segment(miles: 1_070.0, note: "Current Tuya display at reference time")
            ],
            recordedAt: recordedAt
        )
    }
}
