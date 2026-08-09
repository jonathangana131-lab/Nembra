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
        if let existing = try load() {
            // Durable chronology is evidence chronology, not write chronology.
            // A surrounding aggregate state publication may carry the same cached
            // battery value with a newer timestamp. Re-saving that unchanged value
            // must not manufacture a newer battery observation.
            if snapshot.percent == existing.percent,
               snapshot.authority == existing.authority {
                return
            }

            // Persistence is monotonic in observation time. A delayed write cannot
            // roll retained battery truth back to older evidence, even when its value
            // differs from the current snapshot.
            if snapshot.observedAt <= existing.observedAt {
                return
            }
        }

        let data = try RetainedBatterySnapshotCodec.encode(snapshot)
        defaults.set(data, forKey: key)
    }

    public func clear() throws {
        defaults.removeObject(forKey: key)
    }
}

/// Small in-memory implementation for app/unit tests and deterministic previews.
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
        lock.withLock { self.snapshot = snapshot }
    }

    public func clear() throws {
        lock.withLock { snapshot = nil }
    }
}
