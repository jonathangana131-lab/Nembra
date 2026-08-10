import Foundation

/// Provenance for one odometer continuity segment.
///
/// A user-recorded segment is real reference history supplied by the owner, but it is
/// intentionally not promoted to device-verified telemetry. This lets Nembra preserve
/// lifetime mileage across scooter/controller resets without lying about where the
/// number came from.
public enum OdometerContinuitySource: String, Codable, Sendable, Equatable {
    case userRecorded
    case deviceVerified
    case rideReconciled
}

public enum OdometerContinuityConfidence: String, Codable, Sendable, Equatable {
    case referenceOnly
    case mixedReferenceAndVerified
    case verified
}

public enum OdometerContinuityError: Error, Equatable, Sendable {
    case invalidDistance
    case currentReadingRegressed(previousKilometers: Double, observedKilometers: Double)
    case resetRequiresPreviousReading
}

public struct OdometerContinuitySegment: Codable, Sendable, Equatable {
    public let distanceKilometers: Double
    public let source: OdometerContinuitySource
    public let note: String?

    public init(
        distanceKilometers: Double,
        source: OdometerContinuitySource,
        note: String? = nil
    ) throws {
        guard distanceKilometers.isFinite, distanceKilometers >= 0 else {
            throw OdometerContinuityError.invalidDistance
        }
        self.distanceKilometers = distanceKilometers
        self.source = source
        self.note = note
    }
}

public struct OdometerContinuityReading: Codable, Sendable, Equatable {
    public let kilometers: Double
    public let source: OdometerContinuitySource

    public init(kilometers: Double, source: OdometerContinuitySource) throws {
        guard kilometers.isFinite, kilometers >= 0 else {
            throw OdometerContinuityError.invalidDistance
        }
        self.kilometers = kilometers
        self.source = source
    }
}

public struct OdometerContinuitySnapshot: Codable, Sendable, Equatable {
    public let completedSegments: [OdometerContinuitySegment]
    public let currentReading: OdometerContinuityReading?

    public var completedKilometers: Double {
        completedSegments.reduce(0) { $0 + $1.distanceKilometers }
    }

    public var lifetimeKilometers: Double {
        completedKilometers + (currentReading?.kilometers ?? 0)
    }

    public var confidence: OdometerContinuityConfidence {
        var sources = completedSegments.map(\.source)
        if let currentReading {
            sources.append(currentReading.source)
        }
        guard !sources.isEmpty else { return .referenceOnly }
        let hasReference = sources.contains(.userRecorded)
        let hasVerified = sources.contains { $0 == .deviceVerified || $0 == .rideReconciled }
        switch (hasReference, hasVerified) {
        case (true, true): return .mixedReferenceAndVerified
        case (false, true): return .verified
        default: return .referenceOnly
        }
    }
}

/// Reset-aware lifetime odometer accumulator.
///
/// Device odometers are allowed to reset, but Nembra never silently interprets a
/// backwards reading as a reset. The caller must explicitly confirm the reset, at
/// which point the last accepted counter value is frozen into a completed segment
/// and the new counter begins a fresh generation.
public struct OdometerContinuityLedger: Codable, Sendable, Equatable {
    public private(set) var completedSegments: [OdometerContinuitySegment]
    public private(set) var currentReading: OdometerContinuityReading?

    public init(
        completedSegments: [OdometerContinuitySegment] = [],
        currentReading: OdometerContinuityReading? = nil
    ) {
        self.completedSegments = completedSegments
        self.currentReading = currentReading
    }

    public var snapshot: OdometerContinuitySnapshot {
        OdometerContinuitySnapshot(
            completedSegments: completedSegments,
            currentReading: currentReading
        )
    }

    /// Accept a same-generation counter update. A regression never mutates the
    /// ledger because it might be a reset, replay, wrong-device sample, or bad DP.
    public mutating func acceptCurrentReading(_ reading: OdometerContinuityReading) throws {
        if let previous = currentReading,
           reading.kilometers < previous.kilometers {
            throw OdometerContinuityError.currentReadingRegressed(
                previousKilometers: previous.kilometers,
                observedKilometers: reading.kilometers
            )
        }
        currentReading = reading
    }

    /// Explicitly close the previous counter generation and begin a new one after
    /// a known reset. This is the only path that permits the current counter to move
    /// backwards while lifetime distance remains monotonic.
    public mutating func confirmReset(
        newReading: OdometerContinuityReading,
        closedSegmentNote: String? = nil
    ) throws {
        guard let previous = currentReading else {
            throw OdometerContinuityError.resetRequiresPreviousReading
        }
        let closed = try OdometerContinuitySegment(
            distanceKilometers: previous.kilometers,
            source: previous.source,
            note: closedSegmentNote
        )
        completedSegments.append(closed)
        currentReading = newReading
    }

    /// Adds a historical owner-known segment without pretending it was observed
    /// live by the scooter transport.
    public mutating func appendHistoricalSegment(_ segment: OdometerContinuitySegment) {
        completedSegments.append(segment)
    }
}
