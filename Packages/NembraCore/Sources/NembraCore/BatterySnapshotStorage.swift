import Foundation

/// Durable storage boundary for retained battery evidence.
///
/// Storage does not reinterpret authority, freshness, or physical meaning. It only
/// persists snapshots that already passed `RetainedBatterySnapshot` validation.
public protocol RetainedBatterySnapshotStorage: Sendable {
    func load() throws -> RetainedBatterySnapshot?
    func save(_ snapshot: RetainedBatterySnapshot) throws
    func clear() throws
}

/// Shared replacement rule for every retained-battery storage implementation.
///
/// Keeping this decision outside a particular backend prevents previews/tests from
/// accepting replay or chronology rollback that production storage would reject.
private func shouldReplaceRetainedBatterySnapshot(
    _ existing: RetainedBatterySnapshot?,
    with candidate: RetainedBatterySnapshot
) -> Bool {
    guard let existing else { return true }

    // Durable chronology is evidence chronology, not write chronology. A surrounding
    // aggregate publication may repeat the same cached battery value with a newer
    // timestamp; that repetition is not a new battery observation.
    if candidate.percent == existing.percent,
       candidate.authority == existing.authority {
        return false
    }

    // A delayed write cannot roll retained truth back to older (or same-time)
    // evidence, even when its value or authority differs.
    return candidate.observedAt > existing.observedAt
}

/// UserDefaults-backed production storage for the single most recent retained
/// battery observation.
///
/// The encoded payload remains versioned and validated by
/// `RetainedBatterySnapshotCodec`. Corrupt or future-schema payloads are surfaced as
/// errors rather than being coerced into a plausible battery value.
public struct UserDefaultsRetainedBatterySnapshotStorage: RetainedBatterySnapshotStorage, @unchecked Sendable {
    public static let defaultKey = "nembra.vehicle.battery.retained.v1"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> RetainedBatterySnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try RetainedBatterySnapshotCodec.decode(data)
    }

    public func save(_ snapshot: RetainedBatterySnapshot) throws {
        let existing = try load()
        guard shouldReplaceRetainedBatterySnapshot(existing, with: snapshot) else {
            return
        }

        let data = try RetainedBatterySnapshotCodec.encode(snapshot)
        defaults.set(data, forKey: key)
    }

    public func clear() throws {
        defaults.removeObject(forKey: key)
    }
}

/// Small in-memory implementation for app/unit tests and deterministic previews.
/// It deliberately obeys the same chronology/replay contract as production storage.
public final class InMemoryRetainedBatterySnapshotStorage: RetainedBatterySnapshotStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: RetainedBatterySnapshot?

    public init(snapshot: RetainedBatterySnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() throws -> RetainedBatterySnapshot? {
        lock.withLock { snapshot }
    }

    public func save(_ snapshot: RetainedBatterySnapshot) throws {
        lock.withLock {
            guard shouldReplaceRetainedBatterySnapshot(self.snapshot, with: snapshot) else {
                return
            }
            self.snapshot = snapshot
        }
    }

    public func clear() throws {
        lock.withLock { snapshot = nil }
    }
}
