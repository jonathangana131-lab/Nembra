import Foundation

/// The authority carried by a battery value that is eligible for local retention.
///
/// This deliberately describes what Nembra knows about the value, not where a future
/// ES80 transport byte came from. Bluetooth/Tuya semantics remain unassigned until
/// hardware evidence proves them.
public enum BatteryObservationAuthority: String, Codable, CaseIterable, Sendable {
    /// Direct physical/vehicle measurement whose meaning has been validated upstream.
    case measured

    /// A value calculated from other evidence. It must never be restored as measured.
    case estimated

    /// A user-facing/vehicle-facing display value whose underlying physical semantics
    /// are not established strongly enough to call it a measurement.
    case displayOnly
}

/// Durable battery state for app relaunch/reconnect continuity.
///
/// A retained snapshot is explicitly *not live*. Consumers must combine it with current
/// connection/session state before deciding how to label it in UI.
public struct RetainedBatterySnapshot: Equatable, Codable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let percent: Int
    public let authority: BatteryObservationAuthority
    public let observedAt: Date
    public let retainedAt: Date

    public init?(
        percent: Int,
        authority: BatteryObservationAuthority,
        observedAt: Date,
        retainedAt: Date = .now
    ) {
        guard (0...100).contains(percent),
              observedAt.timeIntervalSince1970.isFinite,
              retainedAt.timeIntervalSince1970.isFinite,
              retainedAt >= observedAt else {
            return nil
        }

        self.schemaVersion = Self.schemaVersion
        self.percent = percent
        self.authority = authority
        self.observedAt = observedAt
        self.retainedAt = retainedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case percent
        case authority
        case observedAt
        case retainedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let percent = try container.decode(Int.self, forKey: .percent)
        let authority = try container.decode(BatteryObservationAuthority.self, forKey: .authority)
        let observedAt = try container.decode(Date.self, forKey: .observedAt)
        let retainedAt = try container.decode(Date.self, forKey: .retainedAt)

        guard schemaVersion == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported retained battery snapshot schema"
            )
        }
        guard (0...100).contains(percent) else {
            throw DecodingError.dataCorruptedError(
                forKey: .percent,
                in: container,
                debugDescription: "Retained battery percent must be within 0...100"
            )
        }
        guard observedAt.timeIntervalSince1970.isFinite,
              retainedAt.timeIntervalSince1970.isFinite,
              retainedAt >= observedAt else {
            throw DecodingError.dataCorruptedError(
                forKey: .retainedAt,
                in: container,
                debugDescription: "Retained battery chronology is invalid"
            )
        }

        self.schemaVersion = schemaVersion
        self.percent = percent
        self.authority = authority
        self.observedAt = observedAt
        self.retainedAt = retainedAt
    }

    /// Age is a presentation/input-quality fact only. It does not change authority.
    public func age(at date: Date) -> TimeInterval? {
        let seconds = date.timeIntervalSince(observedAt)
        guard seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    /// Reconstructs the original authority-bearing observation without promoting
    /// retained data to live/current evidence. Storage time remains storage chronology;
    /// only the original observation time crosses back into the battery truth model.
    public var authoritativeObservation: AuthoritativeBatteryObservation? {
        AuthoritativeBatteryObservation(
            percent: percent,
            authority: authority,
            observedAt: observedAt
        )
    }
}

/// Small persistence codec kept separate from storage choice so UserDefaults/files/SwiftData
/// can share one validation boundary.
public enum RetainedBatterySnapshotCodec {
    public static func encode(_ snapshot: RetainedBatterySnapshot) throws -> Data {
        try JSONEncoder().encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> RetainedBatterySnapshot {
        try JSONDecoder().decode(RetainedBatterySnapshot.self, from: data)
    }
}
