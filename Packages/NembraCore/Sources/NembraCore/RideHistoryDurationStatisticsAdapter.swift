import Foundation

/// Trusted production bridge from a validated completed-history duration join into
/// the existing duration-statistics domain.
///
/// App code cannot construct `RideDurationStatisticsRide` from independent raw
/// completed/duration records because that package initializer is intentionally
/// sealed. Requiring `RideHistoryDurationJoinedRecord` here preserves the
/// session/continuity validation performed by the history join before statistics
/// can consume observed elapsed-time evidence.
public extension RideDurationStatisticsRide {
    init(
        historyDurationRecord record: RideHistoryDurationJoinedRecord,
        calendarAttribution: RideStatisticsCalendarAttribution
    ) throws {
        try self.init(
            completedRide: record.historyRecord.evidence,
            durationEvidence: record.durationRecord.evidence,
            calendarAttribution: calendarAttribution
        )
    }
}
