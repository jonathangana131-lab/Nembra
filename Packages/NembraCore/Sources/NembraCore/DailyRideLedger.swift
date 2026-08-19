import Foundation

public enum DailyRideLedgerError: Error, Equatable, Sendable {
    case invalidLocalDay
    case invalidMetricEvidence
    case invalidSegment
    case segmentConflict(AcceptedRideSegmentID)
    case aggregateOverflow
}

/// The exact local-calendar day that owned evidence when Nembra accepted it.
///
/// Nembra deliberately freezes the time zone and day interval at acceptance.
/// Travelling or changing the device time zone later must not silently move
/// already-accepted mileage between days. A ride that continues after a local
/// day or time-zone boundary emits a new segment with a new `RideLocalDay`.
public struct RideLocalDay: Codable, Equatable, Hashable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let timeZoneIdentifier: String
    public let calendarIdentifier: String
    public let era: Int
    public let year: Int
    public let month: Int
    public let day: Int

    private enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case timeZoneIdentifier
        case calendarIdentifier
        case era
        case year
        case month
        case day
    }

    public init(containing date: Date, calendar: Calendar) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let interval = calendar.dateInterval(of: .day, for: date) else {
            throw DailyRideLedgerError.invalidLocalDay
        }
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        guard let era = components.era,
              let year = components.year,
              let month = components.month,
              let day = components.day else {
            throw DailyRideLedgerError.invalidLocalDay
        }
        try self.init(
            startDate: interval.start,
            endDate: interval.end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            calendarIdentifier: String(describing: calendar.identifier),
            era: era,
            year: year,
            month: month,
            day: day
        )
    }

    private init(
        startDate: Date,
        endDate: Date,
        timeZoneIdentifier: String,
        calendarIdentifier: String,
        era: Int,
        year: Int,
        month: Int,
        day: Int
    ) throws {
        guard startDate.timeIntervalSinceReferenceDate.isFinite,
              endDate.timeIntervalSinceReferenceDate.isFinite,
              startDate < endDate,
              !timeZoneIdentifier.isEmpty,
              TimeZone(identifier: timeZoneIdentifier) != nil,
              !calendarIdentifier.isEmpty,
              month > 0,
              day > 0 else {
            throw DailyRideLedgerError.invalidLocalDay
        }
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarIdentifier = calendarIdentifier
        self.era = era
        self.year = year
        self.month = month
        self.day = day
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                startDate: container.decode(Date.self, forKey: .startDate),
                endDate: container.decode(Date.self, forKey: .endDate),
                timeZoneIdentifier: container.decode(String.self, forKey: .timeZoneIdentifier),
                calendarIdentifier: container.decode(String.self, forKey: .calendarIdentifier),
                era: container.decode(Int.self, forKey: .era),
                year: container.decode(Int.self, forKey: .year),
                month: container.decode(Int.self, forKey: .month),
                day: container.decode(Int.self, forKey: .day)
            )
        } catch DailyRideLedgerError.invalidLocalDay {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid frozen local-day evidence.")
            )
        }
    }

    /// Accepted segments may end exactly at the next boundary, but may never
    /// cross it. The next segment then begins at that same instant under the new
    /// day identity, avoiding overlap or invented proportional allocation.
    public func contains(segmentStart: Date, segmentEnd: Date) -> Bool {
        segmentStart >= startDate && segmentStart < endDate
            && segmentEnd >= segmentStart && segmentEnd <= endDate
    }
}

public enum DailyRideMetricDisposition: String, Codable, Equatable, Sendable {
    /// The value covers the whole accepted segment.
    case complete
    /// The value is legitimate but is only a known subtotal for the segment.
    case knownPartial
    /// No legitimate value is available for this segment.
    case unavailable
    /// Sources conflict, so no value may enter an aggregate.
    case conflicting
}

public struct DailyRideMetricEvidence: Codable, Equatable, Sendable {
    public let value: Double?
    public let disposition: DailyRideMetricDisposition

    public init(value: Double?, disposition: DailyRideMetricDisposition) throws {
        if let value {
            guard value.isFinite, value >= 0 else {
                throw DailyRideLedgerError.invalidMetricEvidence
            }
        }
        switch disposition {
        case .complete, .knownPartial:
            guard value != nil else { throw DailyRideLedgerError.invalidMetricEvidence }
        case .unavailable, .conflicting:
            guard value == nil else { throw DailyRideLedgerError.invalidMetricEvidence }
        }
        self.value = value
        self.disposition = disposition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                value: container.decodeIfPresent(Double.self, forKey: .value),
                disposition: container.decode(DailyRideMetricDisposition.self, forKey: .disposition)
            )
        } catch DailyRideLedgerError.invalidMetricEvidence {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid daily ride metric evidence.")
            )
        }
    }
}

public struct AcceptedRideSegmentID: Codable, Equatable, Hashable, Sendable {
    public let sessionID: UUID
    public let sequence: UInt64

    public init(sessionID: UUID, sequence: UInt64) {
        self.sessionID = sessionID
        self.sequence = sequence
    }
}

/// One immutable, day-aligned slice of already-accepted ride evidence.
///
/// This is not a UI counter. A producer must close the current segment whenever
/// the accepted local day or time zone changes. If it lacks a trustworthy
/// checkpoint at that boundary, it records unavailable/partial evidence rather
/// than proportionally spreading distance across the gap.
public struct AcceptedRideSegment: Codable, Equatable, Sendable {
    public let id: AcceptedRideSegmentID
    public let localDay: RideLocalDay
    public let beganAtDate: Date
    public let endedAtDate: Date
    public let distanceMeters: DailyRideMetricEvidence
    public let durationSeconds: DailyRideMetricEvidence
    public let distanceSource: RideDistanceSource?
    public let continuity: RideSessionContinuity
    public let evidenceRevision: String

    private enum CodingKeys: String, CodingKey {
        case id
        case localDay
        case beganAtDate
        case endedAtDate
        case distanceMeters
        case durationSeconds
        case distanceSource
        case continuity
        case evidenceRevision
    }

    public init(
        id: AcceptedRideSegmentID,
        localDay: RideLocalDay,
        beganAtDate: Date,
        endedAtDate: Date,
        distanceMeters: DailyRideMetricEvidence,
        durationSeconds: DailyRideMetricEvidence,
        distanceSource: RideDistanceSource?,
        continuity: RideSessionContinuity,
        evidenceRevision: String
    ) throws {
        let trimmedRevision = evidenceRevision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard beganAtDate.timeIntervalSinceReferenceDate.isFinite,
              endedAtDate.timeIntervalSinceReferenceDate.isFinite,
              localDay.contains(segmentStart: beganAtDate, segmentEnd: endedAtDate),
              !trimmedRevision.isEmpty else {
            throw DailyRideLedgerError.invalidSegment
        }
        if distanceMeters.value != nil {
            guard distanceSource != nil else { throw DailyRideLedgerError.invalidSegment }
        } else if distanceSource != nil {
            throw DailyRideLedgerError.invalidSegment
        }

        self.id = id
        self.localDay = localDay
        self.beganAtDate = beganAtDate
        self.endedAtDate = endedAtDate
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.distanceSource = distanceSource
        self.continuity = continuity
        self.evidenceRevision = trimmedRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: container.decode(AcceptedRideSegmentID.self, forKey: .id),
                localDay: container.decode(RideLocalDay.self, forKey: .localDay),
                beganAtDate: container.decode(Date.self, forKey: .beganAtDate),
                endedAtDate: container.decode(Date.self, forKey: .endedAtDate),
                distanceMeters: container.decode(DailyRideMetricEvidence.self, forKey: .distanceMeters),
                durationSeconds: container.decode(DailyRideMetricEvidence.self, forKey: .durationSeconds),
                distanceSource: container.decodeIfPresent(RideDistanceSource.self, forKey: .distanceSource),
                continuity: container.decode(RideSessionContinuity.self, forKey: .continuity),
                evidenceRevision: container.decode(String.self, forKey: .evidenceRevision)
            )
        } catch DailyRideLedgerError.invalidSegment {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid accepted ride segment.")
            )
        }
    }
}

public enum DailyRideMetricAvailability: String, Codable, Equatable, Sendable {
    case noEvidence
    case unavailable
    case partial
    case complete
}

public struct DailyRideMetricSummary: Equatable, Sendable {
    public let value: Double?
    public let availability: DailyRideMetricAvailability
    public let includedSegmentCount: Int
    public let excludedSegmentCount: Int
}

public struct DailyRideSummary: Equatable, Sendable {
    public let localDay: RideLocalDay
    public let segmentCount: Int
    public let rideCount: Int
    public let distanceMeters: DailyRideMetricSummary
    public let durationSeconds: DailyRideMetricSummary
    public let containsRecoveredRide: Bool
}

public struct CurrentRideSummary: Equatable, Sendable {
    public let sessionID: UUID
    public let segmentCount: Int
    public let distanceMeters: DailyRideMetricSummary
    public let durationSeconds: DailyRideMetricSummary
}

public struct TodayAndCurrentRideSummary: Equatable, Sendable {
    public let today: DailyRideSummary
    public let currentRide: CurrentRideSummary?
}

public enum DailyRideLedgerProjection {
    public static func todayAndCurrentRide(
        segments: [AcceptedRideSegment],
        today: RideLocalDay,
        currentRideSessionID: UUID?
    ) throws -> TodayAndCurrentRideSummary {
        let canonical = try deduplicated(segments)
        let todaySegments = canonical.filter { $0.localDay == today }
        let todaySummary = DailyRideSummary(
            localDay: today,
            segmentCount: todaySegments.count,
            rideCount: Set(todaySegments.map(\.id.sessionID)).count,
            distanceMeters: try summarize(todaySegments.map(\.distanceMeters)),
            durationSeconds: try summarize(todaySegments.map(\.durationSeconds)),
            containsRecoveredRide: todaySegments.contains { $0.continuity == .recoveredCheckpoint }
        )

        let currentSummary: CurrentRideSummary?
        if let currentRideSessionID {
            let currentSegments = canonical.filter { $0.id.sessionID == currentRideSessionID }
            currentSummary = CurrentRideSummary(
                sessionID: currentRideSessionID,
                segmentCount: currentSegments.count,
                distanceMeters: try summarize(currentSegments.map(\.distanceMeters)),
                durationSeconds: try summarize(currentSegments.map(\.durationSeconds))
            )
        } else {
            currentSummary = nil
        }

        return TodayAndCurrentRideSummary(today: todaySummary, currentRide: currentSummary)
    }

    private static func deduplicated(_ segments: [AcceptedRideSegment]) throws -> [AcceptedRideSegment] {
        var byID: [AcceptedRideSegmentID: AcceptedRideSegment] = [:]
        for segment in segments {
            if let existing = byID[segment.id] {
                guard existing == segment else {
                    throw DailyRideLedgerError.segmentConflict(segment.id)
                }
            } else {
                byID[segment.id] = segment
            }
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.beganAtDate != rhs.beganAtDate { return lhs.beganAtDate < rhs.beganAtDate }
            if lhs.id.sessionID != rhs.id.sessionID {
                return lhs.id.sessionID.uuidString < rhs.id.sessionID.uuidString
            }
            return lhs.id.sequence < rhs.id.sequence
        }
    }

    private static func summarize(_ metrics: [DailyRideMetricEvidence]) throws -> DailyRideMetricSummary {
        guard !metrics.isEmpty else {
            return DailyRideMetricSummary(
                value: nil,
                availability: .noEvidence,
                includedSegmentCount: 0,
                excludedSegmentCount: 0
            )
        }

        var sum = 0.0
        var compensation = 0.0
        var included = 0
        var excluded = 0
        var hasPartial = false

        for metric in metrics {
            switch metric.disposition {
            case .complete, .knownPartial:
                guard let value = metric.value else {
                    throw DailyRideLedgerError.invalidMetricEvidence
                }
                let next = sum + value
                guard next.isFinite else { throw DailyRideLedgerError.aggregateOverflow }
                if abs(sum) >= abs(value) {
                    compensation += (sum - next) + value
                } else {
                    compensation += (value - next) + sum
                }
                guard compensation.isFinite else { throw DailyRideLedgerError.aggregateOverflow }
                sum = next
                included += 1
                if metric.disposition == .knownPartial { hasPartial = true }
            case .unavailable, .conflicting:
                excluded += 1
            }
        }

        let total = sum + compensation
        guard total.isFinite else { throw DailyRideLedgerError.aggregateOverflow }
        let availability: DailyRideMetricAvailability
        if included == 0 {
            availability = .unavailable
        } else if excluded > 0 || hasPartial {
            availability = .partial
        } else {
            availability = .complete
        }

        return DailyRideMetricSummary(
            value: included == 0 ? nil : total,
            availability: availability,
            includedSegmentCount: included,
            excludedSegmentCount: excluded
        )
    }
}
